import Foundation
import Testing
@testable import Folio

struct UndoPlanTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func rec(_ n: Int, kind: MoveRecord.Kind = .auto, session: UUID? = nil, undoes: UUID? = nil, at: Int? = nil) -> MoveRecord {
        MoveRecord(timestamp: t0.addingTimeInterval(Double(at ?? n)), sessionID: session, source: "/dl/\(n).pdf", destination: "/docs/F/\(n).pdf", kind: kind, undoes: undoes)
    }

    @Test func lastAndLastNComeNewestFirst() {
        let r = (1...4).map { rec($0) }
        #expect(undoPlan(records: r, selection: .last).map(\.originalName) == ["4.pdf"])
        #expect(undoPlan(records: r, selection: .lastN(3)).map(\.originalName) == ["4.pdf", "3.pdf", "2.pdf"])
        #expect(undoPlan(records: r, selection: .lastN(0)).isEmpty)
        #expect(undoPlan(records: [], selection: .last).isEmpty)
    }

    @Test func sinceTimeAndSession() {
        let session = UUID()
        let r = [rec(1), rec(2, kind: .restructure, session: session), rec(3, kind: .restructure, session: session), rec(4)]
        #expect(undoPlan(records: r, selection: .since(t0.addingTimeInterval(3))).map(\.originalName) == ["4.pdf", "3.pdf"])
        #expect(undoPlan(records: r, selection: .session(session)).map(\.originalName) == ["3.pdf", "2.pdf"])
    }

    @Test func alreadyUndoneAndFailedMovesAreNotPlanned() {
        let a = rec(1), b = rec(2), c = rec(3)
        let undoB = rec(2, kind: .undo, undoes: b.id, at: 10)
        let failedC = MoveRecord(timestamp: t0.addingTimeInterval(11), source: c.source, destination: c.destination, kind: .failed)
        let plan = undoPlan(records: [a, b, c, undoB, failedC], selection: .lastN(10))
        #expect(plan.map(\.id) == [a.id])
    }
}

struct ReconcileTests {
    @Test func interruptedIntentsAreMarkedFailedAndFinishedMovesAreLeftAlone() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFolder("Finance")
        let log = MoveLog(paths: sb.paths)
        let mover = Mover(log: log)
        // One move that completed.
        let done = try sb.makeFile("done.txt")
        let doneRecord = try await mover.perform(validate(proposal: Proposal(name: "Done", folder: "Finance"), source: done, paths: sb.paths).get(), kind: .auto)
        // One intent logged, then "killed" before the move.
        let stuck = try sb.makeFile("stuck.txt")
        let intent = MoveRecord(source: stuck.path, destination: sb.paths.documents.appendingPathComponent("Finance/Stuck.txt").path, kind: .auto)
        try await log.append(intent)
        // One undo logged, then "killed": the file is still at the Documents path.
        let kept = try await mover.perform(validate(proposal: Proposal(name: "Kept", folder: "Finance"), source: try sb.makeFile("kept.txt"), paths: sb.paths).get(), kind: .auto)
        try await log.append(MoveRecord(source: kept.destination, destination: kept.source, kind: .undo, undoes: kept.id))

        #expect(Set(activeMoves(await log.all()).map(\.id)) == [doneRecord.id, intent.id]) // before: the interrupted undo already hides `kept`
        await log.reconcile()
        let active = activeMoves(await log.all())
        #expect(Set(active.map(\.id)) == [doneRecord.id, kept.id]) // after: stuck intent gone, interrupted undo ignored
        await log.reconcile()
        #expect(await log.all().filter { $0.kind == .failed }.count == 2) // idempotent
        #expect(FileManager.default.fileExists(atPath: stuck.path)) // nothing moved by reconcile
    }
}

struct UndoerTests {
    private func setUp() throws -> (Sandbox, Mover, Undoer) {
        let sb = try Sandbox()
        try sb.makeFolder("Finance/Invoices")
        let mover = Mover(log: MoveLog(paths: sb.paths))
        return (sb, mover, Undoer(mover: mover, paths: sb.paths))
    }

    private func file(_ sb: Sandbox, _ mover: Mover, name: String = "invoice (3).pdf", as newName: String = "Stripe Invoice 2026-10") async throws -> (URL, MoveRecord) {
        let source = try sb.makeFile(name, contents: name)
        let move = try validate(proposal: Proposal(name: newName, folder: "Finance/Invoices"), source: source, paths: sb.paths).get()
        return (source, try await mover.perform(move, kind: .auto))
    }

    @Test func moveThenUndoRestoresFileAndLogsBoth() async throws {
        let (sb, mover, undoer) = try setUp()
        defer { sb.cleanUp() }
        let (source, record) = try await file(sb, mover)
        let report = await undoer.run(undoPlan(records: await mover.log.all(), selection: .last))
        #expect(report.restored.map(\.id) == [record.id])
        #expect(try String(contentsOf: source, encoding: .utf8) == "invoice (3).pdf")
        #expect(!FileManager.default.fileExists(atPath: record.destination))
        let log = await mover.log.all()
        #expect(log.map(\.kind) == [.auto, .undo])
        #expect(log.last?.undoes == record.id)
        #expect(await mover.log.recentDestinations(days: 7).contains(source.path)) // watcher will ignore it
    }

    @Test func missingFileIsSkippedAndTheRestStillRun() async throws {
        let (sb, mover, undoer) = try setUp()
        defer { sb.cleanUp() }
        let (_, first) = try await file(sb, mover, name: "a.pdf", as: "A")
        let (_, second) = try await file(sb, mover, name: "b.pdf", as: "B")
        try FileManager.default.moveItem(atPath: second.destination, toPath: sb.paths.documents.appendingPathComponent("user-moved.pdf").path)
        let report = await undoer.run(undoPlan(records: await mover.log.all(), selection: .lastN(2)))
        #expect(report.skipped.map(\.reason) == [.fileGone])
        #expect(report.restored.map(\.id) == [first.id])
    }

    @Test func nameTakenOnReturnGetsSuffixAndNothingIsOverwritten() async throws {
        let (sb, mover, undoer) = try setUp()
        defer { sb.cleanUp() }
        let (source, _) = try await file(sb, mover)
        let squatter = try sb.makeFile("invoice (3).pdf", contents: "someone else")
        let report = await undoer.run(undoPlan(records: await mover.log.all(), selection: .last))
        #expect(report.restored.count == 1)
        #expect(try String(contentsOf: squatter, encoding: .utf8) == "someone else")
        #expect(FileManager.default.fileExists(atPath: source.deletingLastPathComponent().appendingPathComponent("invoice (3) (2).pdf").path))
    }

    @Test func missingOriginalFolderIsReportedNotRecreated() async throws {
        let (sb, mover, undoer) = try setUp()
        defer { sb.cleanUp() }
        let source = try sb.makeFile("sub/x.pdf", in: sb.paths.documents)
        let move = try validate(proposal: Proposal(name: "X", folder: "Finance"), source: source, paths: sb.paths).get()
        try await mover.perform(move, kind: .auto)
        try FileManager.default.removeItem(at: source.deletingLastPathComponent())
        let report = await undoer.run(undoPlan(records: await mover.log.all(), selection: .last))
        #expect(report.skipped.map(\.reason) == [.folderGone])
    }
}
