import Foundation
import Observation

struct RecentMove: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    /// Documents-relative folder, e.g. "Finance/Invoices".
    let folder: String
}

enum MainSection: String, CaseIterable, Identifiable {
    case activity = "Activity", review = "Review", restructure = "Restructure", folders = "Folders", settings = "Settings"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .activity: "clock"
        case .review: "tray.full"
        case .restructure: "wand.and.stars"
        case .folders: "folder"
        case .settings: "gearshape"
        }
    }
}

/// One line of the "For developers" list: what happened to a file and how long the model took.
struct ClassificationNote: Identifiable, Sendable, Equatable {
    let id = UUID()
    let file: String
    let outcome: String
    let seconds: TimeInterval
    let corrections: Int
}

@MainActor @Observable
final class AppState {
    enum Status: Equatable { case needsSetup, watching, paused, modelOffline, working }

    static let recentLimit = 20
    private static let pausedKey = "paused"

    var isModelOnline = true
    var isWorking = false
    var reviewCount = 0
    var notificationsOff = false
    /// True until first-run setup is finished; nothing is watched or moved before then.
    var needsOnboarding = false
    /// While a restructure session is open, autonomous filing waits so the two can't fight over files.
    var restructureOpen = false {
        didSet { if oldValue && !restructureOpen && !isPaused { onResume?() } }
    }
    var section: MainSection = .activity
    /// One line, shown in the menu until the next success clears it.
    var lastError: String?
    private(set) var recentMoves: [RecentMove] = []
    private(set) var classifications: [ClassificationNote] = []

    var isPaused: Bool {
        didSet {
            defaults.set(isPaused, forKey: Self.pausedKey)
            if oldValue && !isPaused { onResume?() }
        }
    }

    /// Called when Pause is switched off, so files held back meanwhile get filed.
    var onResume: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isPaused = defaults.bool(forKey: Self.pausedKey)
    }

    var status: Status {
        if needsOnboarding { return .needsSetup }
        if isPaused { return .paused }
        if !isModelOnline { return .modelOffline }
        return isWorking ? .working : .watching
    }

    func record(_ move: RecentMove) {
        recentMoves.insert(move, at: 0)
        if recentMoves.count > Self.recentLimit { recentMoves.removeLast(recentMoves.count - Self.recentLimit) }
    }

    func note(_ note: ClassificationNote) {
        classifications.insert(note, at: 0)
        if classifications.count > 10 { classifications.removeLast(classifications.count - 10) }
    }

    func forget(_ id: UUID) {
        recentMoves.removeAll { $0.id == id }
    }
}
