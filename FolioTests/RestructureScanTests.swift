import Foundation
import Testing
@testable import Folio

struct RestructureScanTests {
    @Test func selectFilesIsNewestFirstCappedAndStable() {
        let t = Date(timeIntervalSince1970: 1_000_000)
        let files = [("a", 5.0), ("b", 9.0), ("c", 1.0), ("d", 9.0)].map { (url: URL(fileURLWithPath: "/d/\($0.0)"), modified: t.addingTimeInterval($0.1)) }
        #expect(selectFiles(files, cap: 3).map(\.lastPathComponent) == ["b", "d", "a"])
        #expect(selectFiles(files, cap: 0).isEmpty)
        #expect(selectFiles([], cap: 5).isEmpty)
        #expect(batches(Array(1...7), size: 3) == [[1, 2, 3], [4, 5, 6], [7]])
        #expect(batches([Int](), size: 3).isEmpty)
        #expect(batches(Array(1...3), size: 0).isEmpty)
    }

    @Test func changesSkipNoOpsAndUnproposedItems() throws {
        let docs = URL(fileURLWithPath: "/docs")
        func item(_ path: String, folder: String?, name: String?) -> RestructureItem {
            RestructureItem(path: path, summary: "s", contentHash: "h", proposedFolder: folder, proposedName: name)
        }
        let items = [
            item("/docs/A/x.pdf", folder: "A", name: "x.pdf"),           // same place, same name: no-op
            item("/docs/A/x2.pdf", folder: "A", name: "renamed.pdf"),    // rename
            item("/docs/A/x3.pdf", folder: "B", name: "x3.pdf"),         // move
            item("/docs/A/x4.pdf", folder: nil, name: nil),              // no proposal (invalid)
            item("/docs/top.pdf", folder: "", name: "top.pdf"),          // top-level stays
            item("/docs/caf\u{E9}.pdf", folder: "", name: "cafe\u{301}.pdf"), // NFC vs NFD is the same name
        ]
        #expect(changes(in: items, documents: docs).map(\.path) == ["/docs/A/x2.pdf", "/docs/A/x3.pdf"])
        // Capitalisation and spacing alone are not a change.
        #expect(changes(in: [item("/docs/A/same name.md", folder: "A", name: "Same  Name.md")], documents: docs).isEmpty)
        #expect(moves(in: items, documents: docs).map(\.path) == ["/docs/A/x3.pdf"])
        #expect(plannedFolders([item("/x", folder: "Taxes/2026", name: "a")]) == ["Taxes", "Taxes/2026"])
    }

    @Test func scannerSkipsHiddenSymlinksPackagesPartialsAndBusyFilesAndKeepsNewestFirst() throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let docs = sb.paths.documents
        let outside = try sb.makeFile("secret.txt", in: sb.root.appendingPathComponent("outside"))
        try sb.makeFile("A/old.md", in: docs)
        try sb.makeFile("A/new.md", in: docs)
        try sb.makeFile("busy.md", in: docs)
        try sb.makeFile(".hidden.md", in: docs)
        try sb.makeFile("A/.hidden/inside.md", in: docs)
        try sb.makeFile("partial.pdf.crdownload", in: docs)
        try sb.makeFile("node_modules/pkg/index.js", in: docs)
        try sb.makeFile("Thing.app/Contents/Info.plist", in: docs)
        try FileManager.default.createSymbolicLink(at: docs.appendingPathComponent("link.md"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: docs.appendingPathComponent("linkdir"), withDestinationURL: outside.deletingLastPathComponent())
        let now = Date()
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-1000)], ofItemAtPath: docs.appendingPathComponent("A/old.md").path)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: docs.appendingPathComponent("A/new.md").path)
        let found = RestructureScanner(paths: sb.paths).candidates(isBusy: { $0.hasSuffix("busy.md") })
        #expect(found.map(\.lastPathComponent) == ["new.md", "old.md"])
        #expect(RestructureScanner(paths: sb.paths).candidates(cap: 1).count == 1)
    }

    @Test func hashIsStableAndContentBased() throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let a = try sb.makeFile("a.txt", contents: "same")
        let b = try sb.makeFile("b.txt", contents: "same")
        let c = try sb.makeFile("c.txt", contents: "different")
        #expect(RestructureScanner.contentHash(of: a) == RestructureScanner.contentHash(of: b))
        #expect(RestructureScanner.contentHash(of: a) != RestructureScanner.contentHash(of: c))
        #expect(RestructureScanner.contentHash(of: sb.paths.downloads.appendingPathComponent("nope.txt")) == nil)
    }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func hit() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

struct SummarizerTests {
    private func chat(_ summary: String) -> Data {
        let content = "{\"summary\":\"\(summary)\"}"
        return (try? JSONSerialization.data(withJSONObject: ["message": ["role": "assistant", "content": content]])) ?? Data()
    }

    @Test func secondRunIsServedEntirelyFromTheCache() async throws {
        let sb = try Sandbox.withCorpus()
        defer { sb.cleanUp() }
        // 60 files in a Documents tree: the corpus plus copies with distinct content.
        for i in 0..<10 { try sb.makeFile("Notes/extra\(i).md", in: sb.paths.documents, contents: "Extra note number \(i) about quarterly planning and budgets.") }
        for name in try FileManager.default.contentsOfDirectory(atPath: sb.paths.downloads.path) {
            try FileManager.default.moveItem(at: sb.paths.downloads.appendingPathComponent(name), to: sb.paths.documents.appendingPathComponent("Misc/\(name)", isDirectory: false).deletingLastPathComponent().appendingPathComponent(name).createParents())
        }
        let calls = CallCounter()
        let client = StubURLProtocol.client { _ in calls.hit(); return (200, self.chat("A short summary.")) }
        let cache = SummaryCache(paths: sb.paths)
        let summarizer = Summarizer(client: client, cache: cache)
        let files = RestructureScanner(paths: sb.paths).candidates()
        #expect(files.count == 60)

        let first = try await summarizer.summariseAll(files) { _, _ in }
        #expect(first.count == 60 && first.allSatisfy { !$0.summary.isEmpty })
        let firstCalls = calls.count
        #expect(firstCalls > 0 && firstCalls < 60) // empty and unreadable files never reach the model

        let second = try await summarizer.summariseAll(files) { _, _ in }
        #expect(calls.count == firstCalls)           // zero new model calls
        #expect(second.map(\.summary) == first.map(\.summary))
        // A restart still hits the cache.
        let relaunched = Summarizer(client: client, cache: SummaryCache(paths: sb.paths))
        _ = try await relaunched.summariseAll(files) { _, _ in }
        #expect(calls.count == firstCalls)
    }

    @Test func duplicateContentSharesOneSummaryAndUnusableAnswersFallBack() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let a = try sb.makeFile("a.md", in: sb.paths.documents, contents: "Identical text that is long enough to summarise properly.")
        let b = try sb.makeFile("b.md", in: sb.paths.documents, contents: "Identical text that is long enough to summarise properly.")
        let calls = CallCounter()
        let ok = Summarizer(client: StubURLProtocol.client { _ in calls.hit(); return (200, self.chat("Same.")) }, cache: SummaryCache(paths: sb.paths))
        _ = try await ok.summariseAll([a, b], concurrency: 1) { _, _ in }
        #expect(calls.count == 1)

        let sb2 = try Sandbox()
        defer { sb2.cleanUp() }
        let c = try sb2.makeFile("c.md", in: sb2.paths.documents, contents: "Some readable text that the model fails to summarise.")
        let broken = Summarizer(client: StubURLProtocol.client { _ in (200, Data("garbage".utf8)) }, cache: SummaryCache(paths: sb2.paths))
        #expect(try await broken.summarise(c).summary == "No summary available.")
        let offline = Summarizer(client: StubURLProtocol.client { _ in throw URLError(.cannotConnectToHost) }, cache: SummaryCache(paths: sb2.paths))
        await #expect(throws: OllamaError.offline) { try await offline.summarise(c) }
    }

    @Test func cancellingStopsTheRunAndLeavesFilesAlone() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        var urls: [URL] = []
        for i in 0..<20 { urls.append(try sb.makeFile("f\(i).md", in: sb.paths.documents, contents: "File number \(i) with enough words to be summarised by the model.")) }
        let summarizer = Summarizer(client: StubURLProtocol.client { _ in Thread.sleep(forTimeInterval: 0.05); return (200, self.chat("S.")) }, cache: SummaryCache(paths: sb.paths))
        let task = Task { try await summarizer.summariseAll(urls) { _, _ in } }
        try await Task.sleep(for: .milliseconds(120))
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }
}

private extension URL {
    /// Creates the parent folder and returns self, for tests that move files into a new subfolder.
    func createParents() -> URL {
        try? FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
