import Foundation
import Testing
@testable import Folio

@MainActor
struct AppStateTests {
    private func freshDefaults() -> UserDefaults {
        let name = "folio-test-\(UUID().uuidString)"
        UserDefaults().removePersistentDomain(forName: name)
        return UserDefaults(suiteName: name) ?? .standard
    }

    @Test func pauseSurvivesRelaunchAndWinsStatus() {
        let defaults = freshDefaults()
        let first = AppState(defaults: defaults)
        first.isModelOnline = false
        first.isPaused = true
        let second = AppState(defaults: defaults)
        #expect(second.isPaused)
        #expect(second.status == .paused)
        second.isModelOnline = false
        second.isPaused = false
        #expect(second.status == .modelOffline)
    }

    @Test func recentMovesCapAtTwentyNewestFirst() {
        let state = AppState(defaults: freshDefaults())
        for i in 0..<25 { state.record(RecentMove(id: UUID(), name: "f\(i)", folder: "A")) }
        #expect(state.recentMoves.count == 20)
        #expect(state.recentMoves.first?.name == "f24")
    }
}
