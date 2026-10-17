import Foundation
import Testing
@testable import Folio

struct ValidationTests {
    private func makeSandbox() throws -> (Sandbox, URL) {
        let sb = try Sandbox()
        try sb.makeFolder("Finance/Invoices")
        // A folder that is really a symlink out of Documents, and a file posing as a folder.
        let outside = sb.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sb.paths.documents.appendingPathComponent("Escape"), withDestinationURL: outside)
        try sb.makeFile("Afile", in: sb.paths.documents)
        return (sb, try sb.makeFile("invoice (3).pdf"))
    }

    @Test(arguments: [
        ("Stripe Invoice 2026-10", "Finance/Invoices", Result<String, RejectReason>.success("Stripe Invoice 2026-10.pdf")),
        ("Report.docx", "Finance", .success("Report.pdf")),
        ("Report.PDF", "Finance", .success("Report.pdf")),
        ("v1.2", "Finance", .success("v1.2.pdf")),
        ("Report...", "Finance", .success("Report.pdf")),
        ("  Padded name  ", "Finance", .success("Padded name.pdf")),
        ("📄 Receipt", "Finance", .success("📄 Receipt.pdf")),
        ("a/b", "Finance", .failure(.illegalName)),
        ("a:b", "Finance", .failure(.illegalName)),
        ("nul\0byte", "Finance", .failure(.illegalName)),
        ("line\nbreak", "Finance", .failure(.illegalName)),
        ("invoice\u{202E}fdp", "Finance", .failure(.illegalName)),
        (".hidden", "Finance", .failure(.illegalName)),
        ("..", "Finance", .failure(.illegalName)),
        ("   ", "Finance", .failure(.emptyName)),
        (".pdf", "Finance", .failure(.illegalName)),
        (String(repeating: "a", count: 252), "Finance", .failure(.nameTooLong)),
        (String(repeating: "会", count: 90), "Finance", .failure(.nameTooLong)),
    ])
    func names(name: String, folder: String, expected: Result<String, RejectReason>) throws {
        let (sb, source) = try makeSandbox()
        defer { sb.cleanUp() }
        let result = validate(proposal: Proposal(name: name, folder: folder), source: source, paths: sb.paths).map(\.name)
        #expect(result == expected)
    }

    @Test(arguments: [
        ("Finance/Invoices", Result<Bool, RejectReason>.success(false)),
        ("Finance/Receipts", .success(true)),
        ("Brand New", .success(true)),
        ("Finance//Invoices/", .success(false)),
        ("Finance/New/Deeper", .failure(.newFolderTooDeep)),
        ("../../etc", .failure(.traversal)),
        ("Finance/../../x", .failure(.traversal)),
        ("Finance/./Invoices", .failure(.traversal)),
        ("/etc", .failure(.absoluteFolder)),
        ("~/Desktop", .failure(.absoluteFolder)),
        ("Escape/sub", .failure(.folderOutsideDocuments)),
        ("Escape", .failure(.folderOutsideDocuments)),
        ("Afile", .failure(.folderIsAFile)),
        ("", .failure(.emptyFolder)),
        ("//", .failure(.absoluteFolder)),
        (" / ", .failure(.emptyFolder)),
        (".secret", .failure(.illegalFolder)),
        ("Fin:ance", .failure(.illegalFolder)),
        ("Finance/\u{202E}x", .failure(.illegalFolder)),
    ])
    func folders(folder: String, expected: Result<Bool, RejectReason>) throws {
        let (sb, source) = try makeSandbox()
        defer { sb.cleanUp() }
        let result = validate(proposal: Proposal(name: "ok", folder: folder), source: source, paths: sb.paths).map(\.createsFolder)
        #expect(result == expected)
    }

    @Test func plannedFoldersLetARestructureChainButAutonomousMovesCannot() throws {
        let (sb, source) = try makeSandbox()
        defer { sb.cleanUp() }
        let proposal = Proposal(name: "ok", folder: "Taxes/2026/Q3")
        #expect(validate(proposal: proposal, source: source, paths: sb.paths) == .failure(.newFolderTooDeep))
        let planned = validate(proposal: proposal, source: source, paths: sb.paths, virtualFolders: ["Taxes", "Taxes/2026"])
        #expect(try planned.get().foldersToCreate.map(\.lastPathComponent) == ["Taxes", "2026", "Q3"])
        // Planning two levels but proposing a third unknown one is still refused.
        #expect(validate(proposal: Proposal(name: "ok", folder: "Taxes/2026/Q3/X"), source: source, paths: sb.paths, virtualFolders: ["Taxes"]) == .failure(.newFolderTooDeep))
    }

    @Test func sourceMustBeInsideDownloadsOrDocuments() throws {
        let (sb, _) = try makeSandbox()
        defer { sb.cleanUp() }
        let stray = try sb.makeFile("stray.pdf", in: sb.root.appendingPathComponent("elsewhere"))
        let inDocs = try sb.makeFile("top.pdf", in: sb.paths.documents)
        let proposal = Proposal(name: "x", folder: "Finance")
        #expect(validate(proposal: proposal, source: stray, paths: sb.paths) == .failure(.sourceOutsideRoots))
        #expect(validate(proposal: proposal, source: inDocs, paths: sb.paths).isSuccess)
        // The root folders themselves are not files to move.
        #expect(validate(proposal: proposal, source: sb.paths.downloads, paths: sb.paths) == .failure(.sourceOutsideRoots))
    }

    @Test func prefixLookalikeIsNotInside() {
        let docs = URL(fileURLWithPath: "/tmp/Documents")
        #expect(isInside(URL(fileURLWithPath: "/tmp/Documents/a"), docs))
        #expect(!isInside(URL(fileURLWithPath: "/tmp/Documents-evil/a"), docs))
        #expect(!isInside(docs, docs))
    }

    @Test func collisionNamesInsertBeforeExtension() {
        let base = URL(fileURLWithPath: "/d")
        var taken: Set<String> = ["/d/a.pdf", "/d/a (2).pdf", "/d/README", "/d/archive.tar.md"]
        let exists: (URL) -> Bool = { taken.contains($0.path) }
        #expect(uniqueDestination(base: base, name: "a.pdf", exists: exists).lastPathComponent == "a (3).pdf")
        #expect(uniqueDestination(base: base, name: "README", exists: exists).lastPathComponent == "README (2)")
        #expect(uniqueDestination(base: base, name: "archive.tar.md", exists: exists).lastPathComponent == "archive.tar (2).md")
        #expect(uniqueDestination(base: base, name: "fresh.pdf", exists: exists).lastPathComponent == "fresh.pdf")
        taken.removeAll()
    }
}

struct MoveLogTests {
    @Test func survivesTruncatedLastLineAndKeepsAppending() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let log = MoveLog(paths: sb.paths)
        try await log.append(MoveRecord(source: "/a/1.pdf", destination: "/b/1.pdf", kind: .auto))
        // Simulate a crash mid-write: half a line, no newline.
        let url = sb.paths.support.appendingPathComponent("moves.jsonl")
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"id\":\"BROKEN".utf8))
        try handle.close()
        #expect(await log.all().count == 1)
        try await log.append(MoveRecord(source: "/a/2.pdf", destination: "/b/2.pdf", kind: .review))
        let all = await log.all()
        #expect(all.map(\.newName) == ["1.pdf", "2.pdf"])
    }

    @Test func recentDestinationsHonoursWindowAndSkipsFailed() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let log = MoveLog(paths: sb.paths)
        let now = Date()
        try await log.append(MoveRecord(timestamp: now.addingTimeInterval(-8 * 86_400), source: "/a/old.pdf", destination: "/b/old.pdf", kind: .auto))
        try await log.append(MoveRecord(timestamp: now.addingTimeInterval(-86_400), source: "/a/new.pdf", destination: "/b/new.pdf", kind: .auto))
        try await log.append(MoveRecord(timestamp: now, source: "/a/bad.pdf", destination: "/b/bad.pdf", kind: .failed))
        #expect(await log.recentDestinations(days: 7, now: now) == ["/b/new.pdf"])
        #expect(await log.since(now.addingTimeInterval(-3600)).count == 1)
    }
}

struct MoverTests {
    private func setUp() throws -> (Sandbox, MoveLog, URL, ValidatedMove) {
        let sb = try Sandbox()
        try sb.makeFolder("Finance/Invoices")
        let source = try sb.makeFile("invoice (3).pdf", contents: "pdf bytes")
        let move = try validate(proposal: Proposal(name: "Stripe Invoice 2026-10", folder: "Finance/Invoices"), source: source, paths: sb.paths).get()
        return (sb, MoveLog(paths: sb.paths), source, move)
    }

    @Test func movesAndLogs() async throws {
        let (sb, log, source, move) = try setUp()
        defer { sb.cleanUp() }
        let record = try await Mover(log: log).perform(move, kind: .auto, confidence: 0.9, reason: "test")
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOfFile: record.destination, encoding: .utf8) == "pdf bytes")
        #expect(await log.all().map(\.id) == [record.id])
    }

    @Test func logLineExistsEvenWhenTheMoveThrows() async throws {
        struct Boom: Error {}
        let (sb, log, source, move) = try setUp()
        defer { sb.cleanUp() }
        let mover = Mover(log: log, moveItem: { _, _ in throw Boom() })
        await #expect(throws: MoverError.self) { try await mover.perform(move, kind: .auto) }
        let records = await log.all()
        #expect(records.map(\.kind) == [.auto, .failed]) // intent logged first, then the compensating entry
        #expect(FileManager.default.fileExists(atPath: source.path)) // source untouched
    }

    @Test func neverOverwritesAnExistingFile() async throws {
        let (sb, log, _, move) = try setUp()
        defer { sb.cleanUp() }
        let existing = try sb.makeFile("Stripe Invoice 2026-10.pdf", in: move.destinationFolder, contents: "precious")
        let record = try await Mover(log: log).perform(move, kind: .auto)
        #expect(record.newName == "Stripe Invoice 2026-10 (2).pdf")
        #expect(try String(contentsOf: existing, encoding: .utf8) == "precious")
    }

    @Test func createsOneNewFolderAndRefusesMissingSource() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFolder("Finance")
        let source = try sb.makeFile("a.pdf")
        let move = try validate(proposal: Proposal(name: "A", folder: "Finance/Receipts"), source: source, paths: sb.paths).get()
        let mover = Mover(log: MoveLog(paths: sb.paths))
        let record = try await mover.perform(move, kind: .auto)
        #expect(FileManager.default.fileExists(atPath: record.destination))
        await #expect(throws: MoverError.sourceMissing) { try await mover.perform(move, kind: .auto) }
    }

    @Test func movingOntoItselfIsANoOp() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFolder("Finance")
        let source = try sb.makeFile("Report.pdf", in: sb.paths.documents.appendingPathComponent("Finance"))
        let move = try validate(proposal: Proposal(name: "Report", folder: "Finance"), source: source, paths: sb.paths).get()
        await #expect(throws: MoverError.alreadyThere) { try await Mover(log: MoveLog(paths: sb.paths)).perform(move, kind: .auto) }
    }
}
