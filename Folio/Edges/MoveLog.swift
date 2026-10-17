import Foundation

/// `moves.jsonl`: the safety log. Every append is flushed to disk before it returns.
actor MoveLog {
    private let url: URL
    /// Read once, then kept in step with appends, so frequent lookups don't re-read the file.
    private var cache: [MoveRecord]?

    init(paths: FolioPaths) {
        url = paths.support.appendingPathComponent("moves.jsonl")
    }

    func append(_ record: MoveRecord) throws {
        try JSONLines.append(record, to: url)
        cache?.append(record)
    }

    func all() -> [MoveRecord] {
        if let cache { return cache }
        let records = JSONLines.readAll(MoveRecord.self, from: url)
        cache = records
        return records
    }

    /// True for a file Folio has moved at some point (found by inode, so later renames and moves still count).
    func hasHandled(_ path: String) -> Bool {
        guard let key = FileKey(path: path) else { return false }
        return all().contains { $0.kind != .failed && $0.fileKey == key }
    }

    /// Run once at launch. A crash between "log" and "move" leaves an intent for a file that never moved;
    /// mark it failed so undo and the correction tracker ignore it. Files are never touched here.
    func reconcile() {
        let fm = FileManager.default
        for record in effectiveRecords(all()) where fm.fileExists(atPath: record.source) && !fm.fileExists(atPath: record.destination) {
            try? append(MoveRecord(sessionID: record.sessionID, source: record.source, destination: record.destination,
                                   reason: "interrupted before the move", kind: .failed))
        }
    }

    func since(_ date: Date) -> [MoveRecord] {
        all().filter { $0.timestamp >= date }
    }

    /// Destinations of moves in the last `seconds`: files Folio may still be settling.
    func destinations(lastSeconds seconds: TimeInterval, now: Date = Date()) -> Set<String> {
        Set(all().filter { now.timeIntervalSince($0.timestamp) < seconds && $0.kind != .failed }.map(\.destination))
    }

    /// Destination paths of recent moves, so the watcher ignores Folio's own work (G1).
    func recentDestinations(days: Int, now: Date = Date()) -> Set<String> {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        return Set(all().filter { $0.timestamp >= cutoff && $0.kind != .failed }.map(\.destination))
    }
}
