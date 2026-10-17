import Foundation

/// A file must be unchanged this long before Folio touches it.
let settleSeconds: TimeInterval = 60

struct FileSighting: Equatable, Sendable {
    let date: Date
    let size: Int64
    let mtime: Date
}

enum SettleDecision: Equatable, Sendable {
    case ready
    case wait(until: Date)
    case drop
}

/// `observations` are in chronological order. Only the trailing run of identical (size, mtime) counts;
/// a growing file restarts the clock. Nothing observed means nothing to wait for.
func settleDecision(_ observations: [FileSighting], now: Date, quiet: TimeInterval = settleSeconds) -> SettleDecision {
    guard let last = observations.last else { return .drop }
    let stableSince = observations.reversed()
        .prefix { $0.size == last.size && $0.mtime == last.mtime }
        .last?.date ?? last.date
    let readyAt = stableSince.addingTimeInterval(quiet)
    return now >= readyAt ? .ready : .wait(until: readyAt)
}

/// What makes "the same file" for G1/G3. Rename and move keep all three, so Folio's own moves match.
struct FileIdentity: Hashable, Codable, Sendable {
    let resourceID: String
    let size: Int64
    /// Whole milliseconds, so it survives a JSON round trip.
    let mtimeMillis: Int64

    init(resourceID: String, size: Int64, mtime: Date) {
        self.resourceID = resourceID
        self.size = size
        mtimeMillis = Int64((mtime.timeIntervalSince1970 * 1000).rounded())
    }
}

// An edited file has a new identity and is processed again; only an unchanged file is skipped.
func shouldProcess(_ identity: FileIdentity, processed: Set<FileIdentity>) -> Bool {
    !processed.contains(identity)
}
