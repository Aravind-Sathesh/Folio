import Foundation

/// Holds candidate files until they have stopped changing, then emits each one once on `ready`.
///
/// There is no reliable, lsof-free way to know another app has a file open for writing (O_EXLOCK only sees
/// advisory locks, which download tools don't take), so "still being written" means size or mtime still changing,
/// plus the ignore rules for partial downloads.
actor SettleQueue {
    nonisolated let ready: AsyncStream<URL>
    private let readyContinuation: AsyncStream<URL>.Continuation
    private let quiet: TimeInterval
    private let poll: Duration
    private let isOwnMove: @Sendable (URL) async -> Bool
    /// Only files added to their folder after this count as new. Editing a file doesn't change its "date added",
    /// so a document you work on in a watched subfolder is never picked up just because you saved it.
    private let since: Date
    private var sightings: [URL: [FileSighting]] = [:]
    private var order: [URL] = []

    init(quiet: TimeInterval = settleSeconds, poll: Duration = .seconds(5), isOwnMove: @escaping @Sendable (URL) async -> Bool = { _ in false }, since: Date = Date()) {
        self.since = since
        (ready, readyContinuation) = AsyncStream.makeStream()
        self.quiet = quiet
        self.poll = poll
        self.isOwnMove = isOwnMove
    }

    func submit(_ url: URL) async {
        guard sightings[url] == nil, await !isOwnMove(url) else { return }
        guard let first = observe(url), isNew(url) else { return }
        sightings[url] = [first]
        order.append(url)
    }

    /// Consumes watcher events and checks the pending files every `poll`. Returns when cancelled.
    func run(candidates: AsyncStream<URL>) async {
        let feeder = Task { for await url in candidates { await submit(url) } }
        defer { feeder.cancel() }
        await runPolling()
    }

    /// Checks pending files every `poll` until cancelled. Candidates arrive through `submit`.
    func runPolling() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: poll)
            await tick()
        }
    }

    func tick(now: Date = Date()) async {
        for url in order {
            guard let seen = sightings[url] else { continue }
            guard let latest = observe(url, now: now) else { forget(url); continue }
            var history = seen
            // Only changes matter; an unchanged file keeps the start of its quiet period.
            if history.last.map({ $0.size != latest.size || $0.mtime != latest.mtime }) ?? true { history.append(latest) }
            sightings[url] = history
            switch settleDecision(history, now: now, quiet: quiet) {
            case .ready:
                forget(url)
                if await !isOwnMove(url) { readyContinuation.yield(url) }
            case .drop: forget(url)
            case .wait: break
            }
        }
    }

    private func isNew(_ url: URL) -> Bool {
        guard let added = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate else { return true }
        return added >= since
    }

    var pendingCount: Int { sightings.count }

    private func forget(_ url: URL) {
        sightings[url] = nil
        order.removeAll { $0 == url }
    }

    /// nil when the file is gone, should be ignored, or can't be read.
    private func observe(_ url: URL, now: Date = Date()) -> FileSighting? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey]
        // A URL caches resource values, which would hide growth and deletion; read through a fresh one.
        guard let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: keys),
              values.isSymbolicLink != true, values.isRegularFile == true,
              !shouldIgnore(path: url.path, isDirectory: values.isDirectory ?? false, isPackage: values.isPackage ?? false),
              let size = values.fileSize, let mtime = values.contentModificationDate else { return nil }
        return FileSighting(date: now, size: Int64(size), mtime: mtime)
    }
}
