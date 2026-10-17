import Foundation

enum ReviewError: Error, Equatable {
    case noSuggestion
    case invalid(RejectReason)
    case fileGone
    case failed(String)

    var plainMessage: String {
        switch self {
        case .noSuggestion: "There is no suggestion for this file. Use Edit to choose a folder"
        case .invalid(let reason): plainReason(reason)
        case .fileGone: "That file is no longer there"
        case .failed(let message): "Couldn't move the file: \(message)"
        }
    }
}

/// What the user can do with a queued file. Every move is validated again and goes through `Mover`.
struct ReviewActions: Sendable {
    let paths: FolioPaths
    let mover: Mover
    let store: ReviewStore
    let tracker: CorrectionTracker
    var folders: @Sendable () -> FolderConfig? = { nil }

    /// Accepting is Folio's own choice, so a later move by the user is tracked as a correction.
    func accept(_ item: ReviewItem) async -> Result<MoveRecord, ReviewError> {
        guard let suggestion = item.suggestion else { return .failure(.noSuggestion) }
        let summary = await summary(of: item)
        let result = await file(item, as: Proposal(name: suggestion.name, folder: suggestion.folder))
        if case .success(let record) = result { await tracker.track(record, summary: summary) }
        return result
    }

    /// Picking something other than the suggestion is a correction right away (G4).
    func edit(_ item: ReviewItem, name: String, folder: String) async -> Result<MoveRecord, ReviewError> {
        let summary = await summary(of: item)
        let result = await file(item, as: Proposal(name: name, folder: folder))
        if case .success(let record) = result, let suggestion = item.suggestion, suggestion.name != name || suggestion.folder != folder {
            let moved = URL(fileURLWithPath: record.destination)
            let userFolder = moved.deletingLastPathComponent().path.dropFirst(paths.documents.path.count + 1)
            await tracker.record(summary: summary, folioChoice: Choice(name: suggestion.name, folder: suggestion.folder),
                                 userChoice: Choice(name: moved.deletingPathExtension().lastPathComponent, folder: String(userFolder)))
        }
        return result
    }

    /// The file stays where it is; it just stops asking.
    func leave(_ item: ReviewItem) async {
        await store.remove(item.id)
    }

    private func summary(of item: ReviewItem) async -> String {
        let url = URL(fileURLWithPath: item.path)
        let context = await Extractor().extract(url)
        return correctionSummary(text: context.text, fileExtension: url.pathExtension, whereFrom: context.whereFrom)
    }

    private func file(_ item: ReviewItem, as proposal: Proposal) async -> Result<MoveRecord, ReviewError> {
        let source = URL(fileURLWithPath: item.path)
        let move: ValidatedMove
        switch validate(proposal: proposal, source: source, paths: paths, config: folders()) {
        case .success(let value): move = value
        case .failure(let reason): return .failure(.invalid(reason))
        }
        do {
            let record = try await mover.perform(move, kind: .review, reason: item.reason)
            await store.remove(item.id)
            return .success(record)
        } catch MoverError.sourceMissing {
            await store.remove(item.id)
            return .failure(.fileGone)
        } catch MoverError.alreadyThere {
            await store.remove(item.id)
            return .failure(.failed("it is already there"))
        } catch {
            return .failure(.failed(String(describing: error)))
        }
    }
}
