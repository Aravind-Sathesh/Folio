import Foundation
import Testing
@testable import Folio

/// Collects `ready` URLs in the background so tests can wait on wall-clock time.
private actor Collector {
    private(set) var urls: [URL] = []
    func add(_ url: URL) { urls.append(url) }
}

@Suite(.serialized)
struct WatcherTests {
    private struct Rig {
        let sb: Sandbox
        let queue: SettleQueue
        let collector: Collector
        let tasks: [Task<Void, Never>]
    }

    private func start(_ sb: Sandbox, quiet: TimeInterval = 0.8, subfolders: Bool = false, excluded: [String] = [], ownMove: @escaping @Sendable (URL) async -> Bool = { _ in false }) -> Rig {
        let queue = SettleQueue(quiet: quiet, poll: .milliseconds(100), isOwnMove: ownMove)
        var config = FolderConfig.defaults(sb.paths)
        for i in config.watched.indices { config.watched[i].subfolders = subfolders }
        config.excluded = excluded
        let events = FolderWatcher.events(config: config, latency: 0.1)
        let collector = Collector()
        let run = Task { await queue.run(candidates: events) }
        let collect = Task { for await url in queue.ready { await collector.add(url) } }
        return Rig(sb: sb, queue: queue, collector: collector, tasks: [run, collect])
    }

    private func settle(_ seconds: Double) async { try? await Task.sleep(for: .seconds(seconds)) }

    @Test func chunkedWriteEmitsExactlyOneReadyAfterItStopsGrowing() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let rig = start(sb)
        defer { rig.tasks.forEach { $0.cancel() } }
        await settle(0.4) // let the stream start
        let url = sb.paths.downloads.appendingPathComponent("a.pdf")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        for _ in 0..<6 {
            try handle.write(contentsOf: Data(repeating: 1, count: 1000))
            try handle.synchronize()
            await settle(0.25)
            let early = await rig.collector.urls
            #expect(early.isEmpty, "must not be ready while still growing: \(early)")
        }
        try handle.close()
        let lastWrite = Date()
        await settle(2.0)
        let urls = await rig.collector.urls
        #expect(urls.map(\.lastPathComponent) == ["a.pdf"])
        #expect(Date().timeIntervalSince(lastWrite) >= 0.8)
    }

    @Test func partialDownloadNeverEmitsButItsFinalNameDoes() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let rig = start(sb)
        defer { rig.tasks.forEach { $0.cancel() } }
        await settle(0.4)
        let partial = try sb.makeFile("b.pdf.crdownload", contents: "partial")
        await settle(1.5)
        #expect(await rig.collector.urls.isEmpty)
        let final = sb.paths.downloads.appendingPathComponent("b.pdf")
        try FileManager.default.moveItem(at: partial, to: final)
        await settle(2.0)
        #expect(await rig.collector.urls.map(\.lastPathComponent) == ["b.pdf"])
    }

    @Test func createdThenDeletedNeverEmits() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let rig = start(sb)
        defer { rig.tasks.forEach { $0.cancel() } }
        await settle(0.4)
        let url = try sb.makeFile("gone.pdf")
        await settle(0.3)
        try FileManager.default.removeItem(at: url)
        await settle(2.0)
        let emitted = await rig.collector.urls
        #expect(emitted.isEmpty, "\(emitted)")
        #expect(await rig.queue.pendingCount == 0)
    }

    @Test func existingFilesSubfoldersHiddenAndOwnMovesAreIgnoredButDocumentsTopLevelWorks() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFile("preexisting.pdf") // G2: there before Folio started
        await settle(1.5) // FSEvents can replay events from the last second before "now"; older ones never appear
        let own = sb.paths.downloads.appendingPathComponent("undone.pdf").path
        let rig = start(sb, ownMove: { $0.path == own })
        defer { rig.tasks.forEach { $0.cancel() } }
        await settle(0.4)
        try sb.makeFile("deep/inside.pdf")
        try sb.makeFile(".hidden.pdf")
        try sb.makeFile("undone.pdf")
        try sb.makeFile("top.pdf", in: sb.paths.documents)
        try sb.makeFile("Sub/nested.pdf", in: sb.paths.documents)
        await settle(2.5)
        let names = await rig.collector.urls.map(\.lastPathComponent)
        #expect(names == ["top.pdf"], "got \(names)")
    }

    @Test func subfoldersAreWatchedButExcludedHiddenAndDependencyFoldersAreNot() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let private_ = sb.paths.documents.appendingPathComponent("Private").path
        let rig = start(sb, subfolders: true, excluded: [private_])
        defer { rig.tasks.forEach { $0.cancel() } }
        await settle(0.4)
        try sb.makeFile("unzipped/inner/report.pdf")
        try sb.makeFile("Work/new.pdf", in: sb.paths.documents)
        try sb.makeFile("Private/secret.pdf", in: sb.paths.documents)
        try sb.makeFile(".git/objects/x.pdf", in: sb.paths.documents)
        try sb.makeFile("node_modules/pkg/readme.md", in: sb.paths.documents)
        await settle(2.5)
        let names = await rig.collector.urls.map(\.lastPathComponent).sorted()
        #expect(names == ["new.pdf", "report.pdf"], "got \(names)")
    }

    @Test func editingAFileThatWasAlreadyThereNeverMakesItNew() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let existing = try sb.makeFile("Work/draft.md", in: sb.paths.documents, contents: "v1")
        await settle(1.5)
        let rig = start(sb, subfolders: true)
        defer { rig.tasks.forEach { $0.cancel() } }
        await settle(0.4)
        let handle = try FileHandle(forWritingTo: existing)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(" v2".utf8))
        try handle.close()
        await settle(2.5)
        #expect(await rig.collector.urls.isEmpty)
    }

    @Test func tickWithInjectedClockHonoursTheQuietPeriod() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let queue = SettleQueue(quiet: 60, poll: .seconds(5))
        let url = try sb.makeFile("c.pdf")
        let t0 = Date()
        await queue.submit(url)
        await queue.tick(now: t0.addingTimeInterval(30))
        #expect(await queue.pendingCount == 1)
        let collector = Collector()
        let reader = Task { for await u in queue.ready { await collector.add(u); break } }
        await queue.tick(now: t0.addingTimeInterval(61))
        await reader.value
        #expect(await collector.urls.map(\.lastPathComponent) == ["c.pdf"])
        #expect(await queue.pendingCount == 0)
    }
}
