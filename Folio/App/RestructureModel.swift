import Foundation
import Observation

@MainActor @Observable
final class RestructureModel {
    enum Phase: Equatable {
        case idle
        case unavailable(String)
        case scanning
        case summarising(done: Int, total: Int)
        case proposing(done: Int, total: Int)
        case asking
        case review
        case applying(done: Int, total: Int)
        case finished(moved: Int, failed: Int)
        case cancelled
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var items: [RestructureItem] = []
    private(set) var questions: [RestructureQuestion] = []
    private(set) var answers: [RestructureAnswer] = []
    private(set) var questionIndex = 0
    private(set) var capNote: String?
    /// One line for edit errors and undo results.
    var message: String?
    private(set) var sessionID = UUID()

    private let paths: FolioPaths
    private let client: OllamaClient
    private let mover: Mover
    private let log: MoveLog
    private let cache: SummaryCache
    private let state: AppState
    private var task: Task<Void, Never>?
    private let folders: @Sendable () -> FolderConfig?

    /// The folder this session reorganises. Files only move within it.
    private(set) var root: URL

    /// The session's world: validation, scanning and undo all treat `root` as the top.
    private var scope: FolioPaths { FolioPaths(downloads: paths.downloads, documents: root, support: paths.support) }

    /// Returns a plain-words problem, or nil when the folder was accepted.
    func choose(_ url: URL) -> String? {
        if let problem = folderChoiceProblem(url, home: FolioPaths.home) { return problem }
        if folders()?.isExcluded(url) == true { return "That folder is excluded in Folders." }
        guard !isRunning else { return nil }
        root = url.realPath
        phase = .idle
        return nil
    }

    init(paths: FolioPaths, client: OllamaClient, mover: Mover, log: MoveLog, cache: SummaryCache, state: AppState,
         folders: @escaping @Sendable () -> FolderConfig? = { nil }) {
        self.folders = folders
        root = paths.documents
        self.paths = paths
        self.client = client
        self.mover = mover
        self.log = log
        self.cache = cache
        self.state = state
    }

    var isRunning: Bool {
        switch phase {
        case .scanning, .summarising, .proposing, .applying: true
        default: false
        }
    }

    var currentQuestion: RestructureQuestion? { questions.indices.contains(questionIndex) ? questions[questionIndex] : nil }
    var changedItems: [RestructureItem] { changes(in: items, documents: scope.documents) }
    var unchangedCount: Int { items.count - changedItems.count }

    /// Rows grouped by destination folder, with how many files each group receives.
    var groups: [(folder: String, items: [RestructureItem])] {
        Dictionary(grouping: changedItems, by: { $0.proposedFolder ?? "" }).map { ($0.key, $0.value) }.sorted { $0.0.lowercased() < $1.0.lowercased() }
    }

    // MARK: flow

    func begin() {
        guard !isRunning else { return }
        sessionID = UUID()
        items = []; questions = []; answers = []; questionIndex = 0; message = nil
        state.restructureOpen = true
        phase = .scanning
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        if isRunning { phase = .cancelled }
        state.restructureOpen = false
    }

    /// Window closed: stop whatever is running and let autonomous filing resume.
    func close() {
        if case .applying = phase { return } // let a running apply finish; it can't be half-done by closing a window
        cancel()
    }

    private func run() async {
        do {
            guard try await client.hasModel(ModelSpec.restructure.name) else {
                phase = .unavailable("Restructure needs the model \(ModelSpec.restructure.name). In Terminal, run: ollama pull \(ModelSpec.restructure.name)")
                state.restructureOpen = false
                return
            }
            let busy = await log.destinations(lastSeconds: 120)
            let files = RestructureScanner(paths: scope).candidates(excluded: folders()?.excludedURLs ?? [], isBusy: { busy.contains($0) })
            capNote = files.count >= restructureFileCap ? "Organising the \(restructureFileCap) most recent files; run again for more." : nil
            if files.isEmpty { phase = .failed("There are no files in \(root.lastPathComponent) to organise."); state.restructureOpen = false; return }

            phase = .summarising(done: 0, total: files.count)
            let summarizer = Summarizer(client: client, cache: cache)
            let summarised = try await summarizer.summariseAll(files) { [weak self] done, total in
                Task { @MainActor in self?.phase = .summarising(done: done, total: total) }
            }
            phase = .proposing(done: 0, total: summarised.count)
            let proposal = try await RestructureProposer(client: client, paths: scope).propose(summarised) { [weak self] done, total in
                Task { @MainActor in self?.phase = .proposing(done: done, total: total) }
            }
            items = proposal.items
            questions = proposal.questions
            phase = questions.isEmpty ? .review : .asking
        } catch is CancellationError {
            phase = .cancelled
            state.restructureOpen = false
        } catch let error as OllamaError {
            phase = .failed(Pipeline.plainMessage(error))
            state.restructureOpen = false
        } catch {
            phase = .failed("Something went wrong while reading your files.")
            state.restructureOpen = false
        }
    }

    // MARK: questions

    /// `choice == nil` is "Not sure".
    func answer(_ choice: String?) {
        guard let question = currentQuestion else { return }
        answers.removeAll { $0.questionID == question.id }
        answers.append(RestructureAnswer(questionID: question.id, question: question.text, choice: choice))
        if questionIndex + 1 < questions.count {
            questionIndex += 1
        } else {
            finishQuestions()
        }
    }

    func back() {
        guard questionIndex > 0 else { return }
        questionIndex -= 1
        answers.removeAll { $0.questionID == questions[questionIndex].id }
    }

    /// Second, smaller model call for only the files the answered questions were about.
    private func finishQuestions() {
        let answered = answers.filter { $0.choice != nil }
        guard !answered.isEmpty else { phase = .review; return }
        let affected = Set(questions.filter { q in answered.contains { $0.questionID == q.id } }.flatMap(\.affected))
        let subset = items.filter { affected.contains($0.path) }
        let others = items.filter { !affected.contains($0.path) }
        phase = .proposing(done: 0, total: subset.count)
        task = Task {
            do {
                let revised = try await RestructureProposer(client: client, paths: scope)
                    .propose(subset, answers: answered, planned: plannedFolders(others), maxQuestions: 0)
                let byPath = Dictionary(uniqueKeysWithValues: revised.items.map { ($0.path, $0) })
                items = items.map { byPath[$0.path] ?? $0 }
                phase = .review
            } catch is CancellationError {
                phase = .cancelled
                state.restructureOpen = false
            } catch {
                message = "Couldn't use your answers; showing the first proposal."
                phase = .review
            }
        }
    }

    // MARK: review

    func setIncluded(_ path: String, _ included: Bool) {
        if let i = items.firstIndex(where: { $0.path == path }) { items[i].included = included }
    }

    func selectAll(_ included: Bool) {
        for i in items.indices { items[i].included = included }
    }

    /// Re-validated like every other move; on failure the row keeps its old proposal and `message` says why.
    func edit(_ path: String, name: String, folder: String) -> Bool {
        guard let i = items.firstIndex(where: { $0.path == path }) else { return false }
        let planned = plannedFolders(items.filter { $0.path != path })
        switch validate(proposal: Proposal(name: name, folder: folder), source: URL(fileURLWithPath: path), paths: scope, virtualFolders: planned, config: folders()) {
        case .success(let move):
            items[i].proposedFolder = relativeFolder(of: move.destination.path, in: scope.documents)
            items[i].proposedName = move.name
            items[i].reason = "Edited by you"
            items[i].included = true
            message = nil
            return true
        case .failure(let reason):
            message = plainReason(reason)
            return false
        }
    }

    // MARK: apply and undo

    func apply() {
        guard phase == .review else { return }
        let rows = items
        phase = .applying(done: 0, total: changes(in: rows, documents: scope.documents).filter(\.included).count)
        task = Task {
            let report = await RestructureApplier(paths: scope, mover: mover).apply(rows, sessionID: sessionID) { [weak self] done, total in
                Task { @MainActor in self?.phase = .applying(done: done, total: total) }
            }
            phase = .finished(moved: report.moved.count, failed: report.failed.count)
            for record in report.moved { state.record(RecentMove(id: record.id, name: record.newName, folder: relativeFolder(of: record.destination, in: scope.documents))) }
            state.restructureOpen = false
        }
    }

    func undoSession() {
        task = Task {
            let plan = undoPlan(records: await log.all(), selection: .session(sessionID))
            let report = await Undoer(mover: mover, paths: scope).run(plan)
            for record in report.restored { state.forget(record.id) }
            message = report.skipped.isEmpty ? "Put back \(report.restored.count) files." : "Put back \(report.restored.count) files; \(report.skipped.count) had been moved or deleted since."
            phase = .idle
        }
    }
}
