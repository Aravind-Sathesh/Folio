import Foundation

struct ApplyReport: Sendable {
    var moved: [MoveRecord] = []
    var failed: [(path: String, reason: String)] = []
}

/// Applies the rows the user approved, one `Mover` call each, all tagged with one session id so they undo together.
struct RestructureApplier: Sendable {
    let paths: FolioPaths
    let mover: Mover

    func apply(_ items: [RestructureItem], sessionID: UUID, progress: @escaping @Sendable (Int, Int) -> Void = { _, _ in }) async -> ApplyReport {
        var report = ApplyReport()
        let todo = changes(in: items, documents: paths.documents).filter(\.included)
        let planned = plannedFolders(todo)
        for (index, item) in todo.enumerated() {
            if Task.isCancelled { break } // rows already moved stay moved, and undo with the rest of the session
            defer { progress(index + 1, todo.count) }
            guard let folder = item.proposedFolder, let name = item.proposedName else { continue }
            // Validated again right before the move: the disk may have changed since the proposal.
            switch validate(proposal: Proposal(name: name, folder: folder), source: URL(fileURLWithPath: item.path), paths: paths, virtualFolders: planned) {
            case .failure(let reason):
                report.failed.append((item.path, plainReason(reason)))
            case .success(let move):
                do {
                    report.moved.append(try await mover.perform(move, kind: .restructure, reason: item.reason, sessionID: sessionID))
                } catch {
                    report.failed.append((item.path, "\(error)"))
                }
            }
        }
        return report
    }
}
