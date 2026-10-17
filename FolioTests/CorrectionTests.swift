import Foundation
import Testing
@testable import Folio

struct CorrectionLogicTests {
    @Test func isUserChangeTable() {
        let p = "/docs/Finance/Invoices/A.pdf"
        #expect(!isUserChange(expected: p, current: p))                                  // unchanged
        #expect(isUserChange(expected: p, current: "/docs/Finance/Receipts/A.pdf"))       // moved
        #expect(isUserChange(expected: p, current: "/docs/Finance/Invoices/B.pdf"))       // renamed
        #expect(isUserChange(expected: p, current: "/docs/Housing/B.pdf"))                // moved and renamed
        #expect(!isUserChange(expected: "/docs/caf\u{E9}.pdf", current: "/docs/cafe\u{301}.pdf")) // NFC vs NFD
    }

    private func rec(_ id: UUID, _ src: String, _ dst: String, _ kind: MoveRecord.Kind) -> MoveRecord {
        MoveRecord(id: id, source: src, destination: dst, kind: kind)
    }

    private func rec(_ src: String, _ dst: String, _ kind: MoveRecord.Kind) -> MoveRecord {
        rec(UUID(), src, dst, kind)
    }

    @Test func folioOwnLaterMovesUpdateTheExpectedPathAndUndoEndsTracking() {
        let first = UUID()
        let records = [
            rec(first, "/dl/a.pdf", "/docs/F/a.pdf", .auto),
            rec("/docs/F/a.pdf", "/docs/G/a.pdf", .restructure),
            rec("/docs/other.pdf", "/docs/x.pdf", .auto),        // somebody else's move
        ]
        #expect(folioPath(startingAt: "/docs/F/a.pdf", afterRecord: first, records: records) == .at("/docs/G/a.pdf"))
        let withUndo = records + [rec("/docs/G/a.pdf", "/dl/a.pdf", .undo)]
        #expect(folioPath(startingAt: "/docs/F/a.pdf", afterRecord: first, records: withUndo) == .undone)
        #expect(folioPath(startingAt: "/docs/F/a.pdf", afterRecord: UUID(), records: records) == .at("/docs/F/a.pdf"))
    }

    @Test func aFailedLaterMoveDoesNotCount() {
        let first = UUID()
        let records = [
            rec(first, "/dl/a.pdf", "/docs/F/a.pdf", .auto),
            rec("/docs/F/a.pdf", "/docs/G/a.pdf", .review),
            rec("/docs/F/a.pdf", "/docs/G/a.pdf", .failed),
        ]
        #expect(folioPath(startingAt: "/docs/F/a.pdf", afterRecord: first, records: records) == .at("/docs/F/a.pdf"))
    }

    @Test func summaryHasTypeHostAndTrimmedText() {
        let s = correctionSummary(text: String(repeating: "a", count: 500), fileExtension: "PDF", whereFrom: "https://shop.example.com/x.pdf")
        #expect(s.hasPrefix("type pdf, from shop.example.com, text: aaa"))
        #expect(s.count < 350)
        #expect(correctionSummary(text: "", fileExtension: "png", whereFrom: nil) == "type png, text: ")
    }
}

struct CorrectionTrackerTests {
    private func filed(_ sb: Sandbox, _ mover: Mover, name: String = "a.pdf") async throws -> MoveRecord {
        try sb.makeFolder("Finance/Invoices")
        try sb.makeFolder("Finance/Receipts")
        let source = try sb.makeFile(name)
        let move = try validate(proposal: Proposal(name: "Stripe Invoice 2026-10", folder: "Finance/Invoices"), source: source, paths: sb.paths).get()
        return try await mover.perform(move, kind: .auto)
    }

    @Test func movingAFiledFileProducesOneCorrectionAndLeavingItAloneProducesNone() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let log = MoveLog(paths: sb.paths)
        let mover = Mover(log: log)
        let tracker = CorrectionTracker(paths: sb.paths)
        let moved = try await filed(sb, mover)
        let untouched = try await filed(sb, mover, name: "b.pdf")
        await tracker.track(moved, summary: "type pdf, text: invoice")
        await tracker.track(untouched, summary: "type pdf, text: invoice 2")
        #expect(await tracker.check(records: await log.all()).isEmpty) // nothing changed yet

        let newHome = sb.paths.documents.appendingPathComponent("Finance/Receipts/My Receipt.pdf")
        try FileManager.default.moveItem(atPath: moved.destination, toPath: newHome.path)
        let found = await tracker.check(records: await log.all())
        #expect(found.count == 1)
        #expect(found.first?.folioChoice == Choice(name: "Stripe Invoice 2026-10", folder: "Finance/Invoices"))
        #expect(found.first?.userChoice == Choice(name: "My Receipt", folder: "Finance/Receipts"))
        #expect(found.first?.summary == "type pdf, text: invoice")
        #expect(await tracker.corrections().count == 1)
        #expect(await tracker.trackedCount == 1) // the untouched one is still watched
        #expect(await tracker.check(records: await log.all()).isEmpty) // no duplicate
    }

    @Test func undoDeleteAndLeavingDocumentsAreNotCorrections() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let log = MoveLog(paths: sb.paths)
        let mover = Mover(log: log)
        let tracker = CorrectionTracker(paths: sb.paths)
        let undone = try await filed(sb, mover)
        let deleted = try await filed(sb, mover, name: "c.pdf")
        let left = try await filed(sb, mover, name: "d.pdf")
        for record in [undone, deleted, left] { await tracker.track(record, summary: "s") }
        _ = await Undoer(mover: mover, paths: sb.paths).run([undone])
        try FileManager.default.removeItem(atPath: deleted.destination)
        try FileManager.default.moveItem(atPath: left.destination, toPath: sb.paths.downloads.appendingPathComponent("elsewhere.pdf").path)
        #expect(await tracker.check(records: await log.all()).isEmpty)
        #expect(await tracker.trackedCount == 0)
    }

    @Test func reviewAcceptAfterwardsIsFolioOwnMoveNotACorrection() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let log = MoveLog(paths: sb.paths)
        let mover = Mover(log: log)
        let tracker = CorrectionTracker(paths: sb.paths)
        let record = try await filed(sb, mover)
        await tracker.track(record, summary: "s")
        let move = try validate(proposal: Proposal(name: "Moved By Folio", folder: "Finance/Receipts"), source: URL(fileURLWithPath: record.destination), paths: sb.paths).get()
        try await mover.perform(move, kind: .restructure)
        #expect(await tracker.check(records: await log.all()).isEmpty)
        #expect(await tracker.trackedCount == 1)
    }

    @Test func entriesExpireAfterSevenDays() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let log = MoveLog(paths: sb.paths)
        let mover = Mover(log: log)
        let tracker = CorrectionTracker(paths: sb.paths)
        let record = try await filed(sb, mover)
        await tracker.track(record, summary: "s", now: Date().addingTimeInterval(-8 * 86_400))
        _ = await tracker.check(records: await log.all())
        #expect(await tracker.trackedCount == 0)
    }
}
