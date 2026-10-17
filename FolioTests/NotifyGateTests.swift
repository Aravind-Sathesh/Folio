import Foundation
import Testing
@testable import Folio

struct NotifyGateTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    @Test func shouldNotifyTable() {
        #expect(!shouldNotify(queuedCount: 0, lastNotifiedCount: 0, lastNotifiedAt: nil, now: t0))
        #expect(shouldNotify(queuedCount: 3, lastNotifiedCount: 0, lastNotifiedAt: nil, now: t0))
        #expect(!shouldNotify(queuedCount: 3, lastNotifiedCount: 3, lastNotifiedAt: minutes(-60), now: t0)) // did not grow
        #expect(!shouldNotify(queuedCount: 4, lastNotifiedCount: 3, lastNotifiedAt: minutes(-29), now: t0)) // too soon
        #expect(shouldNotify(queuedCount: 4, lastNotifiedCount: 3, lastNotifiedAt: minutes(-30), now: t0))
    }

    @Test func threeQueuedFixturesGiveOneNotificationAndASecondBatchInsideThirtyMinutesDoesNot() {
        var gate = NotifyGate()
        do { let fired = gate.evaluate(queuedCount: 1, now: minutes(0)); #expect(fired) }
        do { let fired = gate.evaluate(queuedCount: 1, now: minutes(1)); #expect(!fired) }
        do { let fired = gate.evaluate(queuedCount: 2, now: minutes(2)); #expect(!fired) }   // grew, but inside the window
        do { let fired = gate.evaluate(queuedCount: 3, now: minutes(3)); #expect(!fired) }
        #expect(gate.nextEligible(queuedCount: 3) == minutes(30))
        do { let fired = gate.evaluate(queuedCount: 3, now: minutes(30)); #expect(fired) }    // one batched ping for all three
        do { let fired = gate.evaluate(queuedCount: 3, now: minutes(95)); #expect(!fired) }   // nothing new
    }

    @Test func clearingTheQueueLetsLaterGrowthNotifyAgain() {
        var gate = NotifyGate()
        do { let fired = gate.evaluate(queuedCount: 3, now: minutes(0)); #expect(fired) }
        do { let fired = gate.evaluate(queuedCount: 0, now: minutes(10)); #expect(!fired) }
        do { let fired = gate.evaluate(queuedCount: 1, now: minutes(40)); #expect(fired) }
    }

    @Test func plainWordsArePluralCorrect() {
        #expect(reviewCountText(1) == "1 file needs review")
        #expect(reviewCountText(4) == "4 files need review")
    }
}
