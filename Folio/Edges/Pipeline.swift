import Foundation

enum PipelineEvent: Sendable {
    case working(Bool)
    case filed(MoveRecord)
    case queuedForReview(ReviewItem)
    case problem(String)
    case clearProblem
    case classified(file: String, outcome: String, seconds: TimeInterval, corrections: Int)
}

/// Ready files in, moves or review items out. One file at a time so the model is never flooded.
actor Pipeline {
    private let paths: FolioPaths
    private let classifier: Classifier
    private let mover: Mover
    private let review: ReviewStore
    private let tracker: CorrectionTracker
    private let isPaused: @Sendable () async -> Bool
    private let threshold: @Sendable () -> Double
    private let report: @Sendable (PipelineEvent) async -> Void
    private let pendingURL: URL
    private var processed: Set<FileIdentity> = []
    /// Files that couldn't be handled yet (model offline, or paused); retried by `drain`.
    private var pending: [URL] = []

    init(paths: FolioPaths, classifier: Classifier, mover: Mover, review: ReviewStore, tracker: CorrectionTracker,
         isPaused: @escaping @Sendable () async -> Bool,
         threshold: @escaping @Sendable () -> Double = { defaultConfidenceThreshold },
         report: @escaping @Sendable (PipelineEvent) async -> Void) {
        self.paths = paths
        self.classifier = classifier
        self.mover = mover
        self.review = review
        self.tracker = tracker
        self.isPaused = isPaused
        self.threshold = threshold
        self.report = report
        pendingURL = paths.support.appendingPathComponent("pending.json")
        let saved = (try? Data(contentsOf: pendingURL)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? []
        pending = saved.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var pendingCount: Int { pending.count }

    func run(ready: AsyncStream<URL>) async {
        await drain()
        for await url in ready { await process(url) }
    }

    /// Retries what was waiting for the model or for Pause to end.
    func drain() async {
        let waiting = pending
        pending = []
        for url in waiting { await process(url) }
        savePending()
    }

    func process(_ url: URL) async {
        guard let identity = fileIdentity(of: url), shouldProcess(identity, processed: processed) else { return }
        await report(.working(true))
        await handle(url, identity: identity)
        await report(.working(false))
    }

    private func handle(_ url: URL, identity: FileIdentity) async {
        let decision: Decision
        var summary = ""
        do {
            let raw = try await classifier.raw(url, tree: listFolders(in: paths.documents, excluding: classifier.folders()?.excludedURLs ?? []))
            decision = classifier.decision(from: raw, threshold: threshold())
            summary = correctionSummary(text: raw.context.text, fileExtension: url.pathExtension, whereFrom: raw.context.whereFrom)
            let outcome: String
            switch decision {
            case .file(let move, _, _): outcome = "Filed to \(folderDisplay(Self.relative(move.destinationFolder, paths.documents)))"
            case .review: outcome = "Needs review"
            }
            await report(.classified(file: url.lastPathComponent, outcome: outcome, seconds: raw.seconds, corrections: raw.correctionsUsed))
        } catch let error as OllamaError {
            hold(url)
            await report(.problem(Self.plainMessage(error)))
            return
        } catch {
            await report(.problem("Couldn't read \(url.lastPathComponent)"))
            return
        }
        await report(.clearProblem)

        switch decision {
        case .file(let move, let confidence, let reason):
            // Checked here, not at dequeue: the model call above can take seconds.
            if await isPaused() { hold(url); return }
            do {
                let record = try await mover.perform(move, kind: .auto, confidence: confidence, reason: reason)
                if let moved = fileIdentity(of: URL(fileURLWithPath: record.destination)) { processed.insert(moved) }
                await tracker.track(record, summary: summary)
                await report(.filed(record))
            } catch MoverError.alreadyThere {
                processed.insert(identity)
            } catch MoverError.sourceMissing {
                // Gone before we got to it; nothing to do.
            } catch {
                await report(.problem("Couldn't move \(url.lastPathComponent)"))
            }
        case .review(let suggestion, _, let reason):
            let item = ReviewItem(path: url.path, suggestion: suggestion, reason: reason)
            if await review.add(item) { await report(.queuedForReview(item)) }
            processed.insert(identity)
        }
    }

    private func hold(_ url: URL) {
        if !pending.contains(url) { pending.append(url) }
        savePending()
    }

    private func savePending() {
        try? JSONEncoder().encode(pending.map(\.path)).write(to: pendingURL, options: .atomic)
    }

    private static func relative(_ folder: URL, _ documents: URL) -> String {
        String(folder.path.dropFirst(documents.path.count + 1))
    }

    static func plainMessage(_ error: OllamaError) -> String {
        switch error {
        case .offline: "Model offline. Files will wait"
        case .timeout: "The model took too long. Files will wait"
        case .modelMissing(let name): "Model \(name) isn't installed"
        case .badResponse, .forbiddenHost: "The model gave an unusable answer"
        }
    }
}
