import AppKit
import Foundation

/// Owns the long-lived pieces and connects them to `AppState`.
@MainActor
final class AppModel {
    let state = AppState()
    private let client = OllamaClient()
    private var services: Services?
    private(set) var review: ReviewModel?
    private(set) var restructure: RestructureModel?
    private(set) var onboarding: OnboardingModel?
    private var watching = false
    private let windows = WindowManager()
    private var statusItem: StatusItemController?

    func showMain(_ section: MainSection? = nil) {
        if let section { state.section = section }
        if state.needsOnboarding { return showOnboarding() }
        windows.show("main", title: "Folio", size: NSSize(width: 900, height: 620)) { MainView(model: self) }
    }

    private func showOnboarding() {
        guard let onboarding else { return }
        windows.show("onboarding", title: "Welcome to Folio", size: NSSize(width: 580, height: 560), resizable: false) {
            OnboardingView(model: onboarding, start: { [weak self] in self?.completeOnboarding() })
        }
    }
    private var notifier: Notifier?
    private static let healthInterval: Duration = .seconds(15)

    var supportFolder: URL? { services?.paths.support }

    private struct Services {
        let paths: FolioPaths
        let log: MoveLog
        let undoer: Undoer
        let review: ReviewStore
        let pipeline: Pipeline
        let queue: SettleQueue
        let reviewActions: ReviewActions
        let tracker: CorrectionTracker
        let index: CorrectionIndex
        let mover: Mover
        let cache: SummaryCache
        let folders: FolderConfigStore
    }

    var menuActions: MenuActions {
        MenuActions(undo: { [weak self] id in Task { await self?.undo(.id(id)) } },
                    undoLast: { [weak self] in Task { await self?.undo(.selection(.last)) } })
    }

    func start() {
        statusItem = StatusItemController { [weak self] in self?.showMain() }
        do {
            let paths = try FolioPaths.fromLaunchArguments()
            services = makeServices(paths)
        } catch {
            state.lastError = "Couldn't open Folio's folders"
            return
        }
        guard let services else { return }
        restructure = RestructureModel(paths: services.paths, client: client, mover: services.mover, log: services.log, cache: services.cache, state: state,
                                       folders: { [folders = services.folders] in folders.current })
        let reviewModel = ReviewModel(actions: services.reviewActions, state: state)
        review = reviewModel
        Task { await reviewModel.reload() }
        let notifier = Notifier(state: state, isEnabled: { Settings.notifyAboutReview }, onReview: { [weak self] in self?.showMain(.review) },
                                onUndoLast: { [weak self] in Task { await self?.undo(.selection(.last)) } })
        notifier.start()
        self.notifier = notifier
        onboarding = OnboardingModel(client: client, notifier: notifier)
        Task { await watchModelHealth(services) }
        if OnboardingMarker.isDone(services.paths) {
            beginWatching()
        } else {
            state.needsOnboarding = true // nothing is watched until the user presses Start
            showOnboarding()
        }
    }

    func completeOnboarding() {
        guard let services else { return }
        OnboardingMarker.markDone(services.paths)
        state.needsOnboarding = false
        windows.close("onboarding")
        beginWatching()
        showMain(.activity)
    }

    private var feeder: Task<Void, Never>?

    var folderConfig: FolderConfig? { services?.folders.current }

    /// Applies a change to watched or excluded folders right away.
    func updateFolders(_ change: (inout FolderConfig) -> Void) {
        services?.folders.update(change)
        if watching { restartWatcher() }
    }

    private func restartWatcher() {
        guard let services else { return }
        feeder?.cancel()
        let events = FolderWatcher.events(config: services.folders.current)
        let queue = services.queue
        feeder = Task { for await url in events { await queue.submit(url) } }
    }

    private func beginWatching() {
        guard let services, !watching else { return }
        watching = true
        Task { await services.queue.runPolling() }
        restartWatcher()
        Task {
            await services.log.reconcile()
            await services.pipeline.run(ready: services.queue.ready)
        }
        Task { await watchCorrections(services) }
        Task { await services.index.backfill() }
        state.onResume = { Task { await services.pipeline.drain() } }
    }

    private func makeServices(_ paths: FolioPaths) -> Services {
        let log = MoveLog(paths: paths)
        let mover = Mover(log: log)
        let review = ReviewStore(paths: paths)
        let folders = FolderConfigStore(paths: paths)
        let index = CorrectionIndex(paths: paths, client: client)
        let tracker = CorrectionTracker(paths: paths, onCorrection: { await index.add($0) })
        let state = self.state
        let pipeline = Pipeline(
            paths: paths, classifier: Classifier(client: client, paths: paths, corrections: { await index.examples(forSummary: $0) }, folders: { folders.current }), mover: mover, review: review, tracker: tracker,
            isPaused: { await MainActor.run { state.isPaused || state.restructureOpen } },
            threshold: { Settings.threshold },
            report: { [weak self] event in await self?.handle(event, documents: paths.documents) })
        let queue = SettleQueue(isOwnMove: { url in
            if await log.hasHandled(url.path) { return true }
            return await log.recentDestinations(days: 7).contains(url.path)
        })
        return Services(paths: paths, log: log, undoer: Undoer(mover: mover, paths: paths, extraRoots: { folders.current.watchedURLs }), review: review, pipeline: pipeline, queue: queue,
                        reviewActions: ReviewActions(paths: paths, mover: mover, store: review, tracker: tracker, folders: { folders.current }), tracker: tracker, index: index, mover: mover, cache: SummaryCache(paths: paths), folders: folders)
    }

    private func handle(_ event: PipelineEvent, documents: URL) async {
        switch event {
        case .working(let on): state.isWorking = on
        case .clearProblem: state.lastError = nil
        case .classified(let file, let outcome, let seconds, let corrections):
            state.note(ClassificationNote(file: file, outcome: outcome, seconds: seconds, corrections: corrections))
        case .problem(let message): state.lastError = message
        case .queuedForReview:
            await review?.reload()
            notifier?.queueChanged(count: state.reviewCount)
        case .filed(let record):
            let folder = URL(fileURLWithPath: record.destination).deletingLastPathComponent().path
            state.record(RecentMove(id: record.id, name: record.newName, folder: String(folder.dropFirst(documents.path.count + 1))))
        }
    }

    private func watchModelHealth(_ services: Services) async {
        var wasOnline = true
        while !Task.isCancelled {
            let online = await client.isReachable()
            state.isModelOnline = online
            await notifier?.refreshPermission()
            if online && !wasOnline { await services.pipeline.drain() }
            wasOnline = online
            try? await Task.sleep(for: Self.healthInterval)
        }
    }

    /// Every 2 minutes, and whenever the app is brought forward, look for files the user has moved or renamed.
    private func watchCorrections(_ services: Services) async {
        let activations = Task {
            for await _ in NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification) {
                await services.tracker.check(records: await services.log.all())
            }
        }
        defer { activations.cancel() }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(120))
            await services.tracker.check(records: await services.log.all())
        }
    }

    // MARK: undo

    private enum UndoTarget { case id(UUID), selection(UndoSelection) }

    private func undo(_ target: UndoTarget) async {
        guard let services else { return }
        let records = await services.log.all()
        let plan: [MoveRecord]
        switch target {
        case .id(let id): plan = activeMoves(records).filter { $0.id == id }
        case .selection(let selection): plan = undoPlan(records: records, selection: selection)
        }
        let report = await services.undoer.run(plan)
        for record in report.restored { state.forget(record.id) }
        if let skipped = report.skipped.first {
            state.lastError = skipped.reason == .fileGone ? "Couldn't undo: the file was moved or deleted" : "Couldn't undo \(skipped.record.originalName)"
        } else {
            state.lastError = nil
        }
    }
}
