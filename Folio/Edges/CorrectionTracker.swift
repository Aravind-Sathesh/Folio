import Foundation

struct TrackedFile: Codable, Sendable, Equatable {
    let recordID: UUID
    let key: FileKey
    let expectedPath: String
    let folioChoice: Choice
    let summary: String
    let trackedAt: Date
}

/// Notices when the user moves or renames a file Folio filed, and records that as a correction.
/// Undo is deliberately not a correction in this version; the user may want it to count as "wrong" later.
actor CorrectionTracker {
    static let window: TimeInterval = 7 * 86_400

    private let paths: FolioPaths
    private let trackedURL: URL
    private let correctionsURL: URL
    private var tracked: [TrackedFile]
    private let onCorrection: @Sendable (Correction) async -> Void

    init(paths: FolioPaths, onCorrection: @escaping @Sendable (Correction) async -> Void = { _ in }) {
        self.paths = paths
        self.onCorrection = onCorrection
        trackedURL = paths.support.appendingPathComponent("tracked.json")
        correctionsURL = paths.support.appendingPathComponent("corrections.jsonl")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        tracked = (try? Data(contentsOf: trackedURL)).flatMap { try? decoder.decode([TrackedFile].self, from: $0) } ?? []
    }

    var trackedCount: Int { tracked.count }

    func corrections() -> [Correction] {
        JSONLines.readAll(Correction.self, from: correctionsURL)
    }

    /// Call right after Folio moves a file into Documents.
    func track(_ record: MoveRecord, summary: String, now: Date = Date()) {
        guard let key = FileKey(path: record.destination), let choice = choice(forPath: record.destination) else { return }
        tracked.append(TrackedFile(recordID: record.id, key: key, expectedPath: record.destination, folioChoice: choice, summary: summary, trackedAt: now))
        save()
    }

    /// A correction the user made right in the review window (G4), where no waiting is needed.
    @discardableResult
    func record(summary: String, folioChoice: Choice, userChoice: Choice, now: Date = Date()) -> Correction? {
        let correction = Correction(id: UUID(), timestamp: now, summary: summary, folioChoice: folioChoice, userChoice: userChoice)
        guard (try? JSONLines.append(correction, to: correctionsURL)) != nil else { return nil }
        Task { await onCorrection(correction) }
        return correction
    }

    /// Resolves every tracked file to its current path. Returns the corrections found this round.
    @discardableResult
    func check(records: [MoveRecord], now: Date = Date()) -> [Correction] {
        var found: [Correction] = []
        var keep: [TrackedFile] = []
        for file in tracked {
            guard now.timeIntervalSince(file.trackedAt) < Self.window, let current = file.key.currentPath else { continue } // expired or gone
            switch folioPath(startingAt: file.expectedPath, afterRecord: file.recordID, records: records) {
            case .undone: continue
            case .at(let folioPath):
                guard isUserChange(expected: folioPath, current: current) else { keep.append(file); continue }
                // Moved out of Documents (Desktop, another volume) says nothing about which folder it belongs in.
                if let userChoice = choice(forPath: current) {
                    let correction = Correction(id: UUID(), timestamp: now, summary: file.summary, folioChoice: file.folioChoice, userChoice: userChoice)
                    if (try? JSONLines.append(correction, to: correctionsURL)) != nil {
                        found.append(correction)
                        Task { await onCorrection(correction) }
                    }
                }
            }
        }
        tracked = keep
        save()
        return found
    }

    private func choice(forPath path: String) -> Choice? {
        let url = URL(fileURLWithPath: path)
        guard isInside(url, paths.documents) else { return nil }
        let folder = url.deletingLastPathComponent().path
        guard folder.count > paths.documents.path.count else { return nil }
        return Choice(name: url.deletingPathExtension().lastPathComponent, folder: String(folder.dropFirst(paths.documents.path.count + 1)))
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(tracked).write(to: trackedURL, options: .atomic)
    }
}
