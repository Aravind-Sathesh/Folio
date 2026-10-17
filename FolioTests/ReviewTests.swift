import Foundation
import Testing
@testable import Folio

struct ReviewTests {
    private func rig() throws -> (Sandbox, ReviewActions, ReviewStore, CorrectionTracker) {
        let sb = try Sandbox()
        try sb.makeFolder("Finance/Invoices")
        let store = ReviewStore(paths: sb.paths)
        let tracker = CorrectionTracker(paths: sb.paths)
        let actions = ReviewActions(paths: sb.paths, mover: Mover(log: MoveLog(paths: sb.paths)), store: store, tracker: tracker)
        return (sb, actions, store, tracker)
    }

    @Test func itemRoundTripsAndSurvivesRelaunchButDropsMissingFiles() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let kept = try sb.makeFile("kept.pdf")
        let gone = try sb.makeFile("gone.pdf")
        let store = ReviewStore(paths: sb.paths)
        await store.add(ReviewItem(path: kept.path, suggestion: Suggestion(name: "Kept", folder: "Finance"), reason: "Not sure where this goes"))
        await store.add(ReviewItem(path: gone.path, suggestion: nil, reason: "x"))
        #expect(await store.add(ReviewItem(path: kept.path, suggestion: nil, reason: "dup")) == false)
        try FileManager.default.removeItem(at: gone)
        let relaunched = ReviewStore(paths: sb.paths)
        let items = await relaunched.items
        #expect(items.map(\.path) == [kept.path])
        #expect(items.first?.suggestion == Suggestion(name: "Kept", folder: "Finance"))
        // The dropped item is also gone from disk, not just from memory.
        #expect(await ReviewStore(paths: sb.paths).items.count == 1)
    }

    @Test func acceptFilesTheSuggestionAsAReviewMoveAndRemovesTheItem() async throws {
        let (sb, actions, store, tracker) = try rig()
        defer { sb.cleanUp() }
        let file = try sb.makeFile("q.pdf")
        let item = ReviewItem(path: file.path, suggestion: Suggestion(name: "Q Invoice", folder: "Finance/Invoices"), reason: "r")
        await store.add(item)
        let record = try await actions.accept(item).get()
        #expect(record.kind == .review)
        #expect(FileManager.default.fileExists(atPath: sb.paths.documents.appendingPathComponent("Finance/Invoices/Q Invoice.pdf").path))
        #expect(await store.items.isEmpty)
        #expect(await tracker.corrections().isEmpty) // accepting the suggestion is not a correction
        #expect(await tracker.trackedCount == 1)      // but a later move by the user will be
    }

    @Test func editIsRevalidatedAndCountsAsACorrection() async throws {
        let (sb, actions, store, tracker) = try rig()
        defer { sb.cleanUp() }
        let file = try sb.makeFile("q.pdf")
        let item = ReviewItem(path: file.path, suggestion: Suggestion(name: "Q", folder: "Finance/Invoices"), reason: "r")
        await store.add(item)
        #expect(await actions.edit(item, name: "x", folder: "../../etc") == .failure(.invalid(.traversal)))
        #expect(FileManager.default.fileExists(atPath: file.path)) // nothing moved, still queued
        #expect(await store.items.count == 1)
        let record = try await actions.edit(item, name: "Q Receipt", folder: "Finance/Receipts").get()
        #expect(record.newName == "Q Receipt.pdf")
        let corrections = await tracker.corrections()
        #expect(corrections.count == 1)
        #expect(corrections.first?.folioChoice == Choice(name: "Q", folder: "Finance/Invoices"))
        #expect(corrections.first?.userChoice == Choice(name: "Q Receipt", folder: "Finance/Receipts"))
    }

    @Test func missingFileAndMissingSuggestionAreReportedInPlainWords() async throws {
        let (sb, actions, store, _) = try rig()
        defer { sb.cleanUp() }
        let ghost = ReviewItem(path: sb.paths.downloads.appendingPathComponent("ghost.pdf").path, suggestion: Suggestion(name: "G", folder: "Finance"), reason: "r")
        await store.add(ghost)
        #expect(await actions.accept(ghost) == .failure(.fileGone))
        #expect(await store.items.isEmpty)
        let blank = ReviewItem(path: "/x", suggestion: nil, reason: "r")
        #expect(await actions.accept(blank) == .failure(.noSuggestion))
        #expect(ReviewError.fileGone.plainMessage == "That file is no longer there")
    }

    @Test func leaveKeepsTheFileAndDropsTheItem() async throws {
        let (sb, actions, store, _) = try rig()
        defer { sb.cleanUp() }
        let file = try sb.makeFile("l.pdf")
        let item = ReviewItem(path: file.path, suggestion: nil, reason: "r")
        await store.add(item)
        await actions.leave(item)
        #expect(await store.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
