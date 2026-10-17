import Foundation

/// At most one review notification per half hour.
let notifyInterval: TimeInterval = 30 * 60

/// True when the queue has something new for the user and enough time has passed since the last ping.
func shouldNotify(queuedCount: Int, lastNotifiedCount: Int, lastNotifiedAt: Date?, now: Date, interval: TimeInterval = notifyInterval) -> Bool {
    guard queuedCount > 0, queuedCount > lastNotifiedCount else { return false }
    guard let lastNotifiedAt else { return true }
    return now.timeIntervalSince(lastNotifiedAt) >= interval
}

struct NotifyGate: Equatable {
    private(set) var lastCount = 0
    private(set) var lastAt: Date?

    /// Records the notification when it says yes. A shrinking queue lowers the bar so later growth counts again.
    mutating func evaluate(queuedCount: Int, now: Date, interval: TimeInterval = notifyInterval) -> Bool {
        lastCount = min(lastCount, queuedCount)
        guard shouldNotify(queuedCount: queuedCount, lastNotifiedCount: lastCount, lastNotifiedAt: lastAt, now: now, interval: interval) else { return false }
        lastCount = queuedCount
        lastAt = now
        return true
    }

    /// When a blocked notification could next go out (nil if nothing is blocked by the interval).
    func nextEligible(queuedCount: Int, interval: TimeInterval = notifyInterval) -> Date? {
        guard queuedCount > lastCount, let lastAt else { return nil }
        return lastAt.addingTimeInterval(interval)
    }
}
