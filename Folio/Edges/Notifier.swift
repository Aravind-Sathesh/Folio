import Foundation
import UserNotifications

/// Batched "N files need review" notifications with Review and Undo last actions.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    private static let categoryID = "folio.review"
    private var gate = NotifyGate()
    private var scheduled: Task<Void, Never>?
    private let state: AppState
    private let isEnabled: () -> Bool
    private let onReview: () -> Void
    private let onUndoLast: () -> Void
    private let deliver: (String) async -> Void

    init(state: AppState, isEnabled: @escaping () -> Bool = { true }, onReview: @escaping () -> Void, onUndoLast: @escaping () -> Void,
         deliver: ((String) async -> Void)? = nil) {
        self.state = state
        self.isEnabled = isEnabled
        self.onReview = onReview
        self.onUndoLast = onUndoLast
        self.deliver = deliver ?? Self.postToSystem
        super.init()
    }

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let review = UNNotificationAction(identifier: "review", title: "Review", options: [.foreground])
        let undo = UNNotificationAction(identifier: "undoLast", title: "Undo last", options: [])
        center.setNotificationCategories([UNNotificationCategory(identifier: Self.categoryID, actions: [review, undo], intentIdentifiers: [])])
    }

    /// Asked during first-run setup, not at launch.
    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            state.notificationsOff = !granted
        } catch {
            // An error (not a "no") means notifications can't work for this build; the menu says so too.
            state.notificationsOff = true
        }
    }

    func refreshPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        state.notificationsOff = settings.authorizationStatus == .denied
    }

    /// Call whenever the review queue size changes.
    func queueChanged(count: Int, now: Date = Date()) {
        scheduled?.cancel()
        guard isEnabled() else { return }
        if gate.evaluate(queuedCount: count, now: now) {
            Task { await deliver(reviewCountText(count)) }
        } else if let next = gate.nextEligible(queuedCount: count) {
            // Blocked only by the interval: look again when it ends, even if nothing else happens until then.
            scheduled = Task { [weak self] in
                try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
                guard !Task.isCancelled, let self else { return }
                queueChanged(count: state.reviewCount)
            }
        }
    }

    private static func postToSystem(_ text: String) async {
        let content = UNMutableNotificationContent()
        content.title = "Folio"
        content.body = text
        content.categoryIdentifier = categoryID
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: delegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        await MainActor.run {
            if action == "undoLast" { onUndoLast() } else { onReview() } // tapping the body opens Review too
        }
    }
}
