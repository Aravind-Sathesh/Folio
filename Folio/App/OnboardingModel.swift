import Foundation
import Observation
import ServiceManagement
import UserNotifications

@MainActor @Observable
final class OnboardingModel {
    struct ModelCheck: Identifiable, Equatable {
        let name: String
        let purpose: String
        let required: Bool
        var installed = false
        var id: String { name }
        var fix: String { "ollama pull \(name)" }
    }

    private(set) var ollamaRunning = false
    private(set) var checks = [
        ModelCheck(name: ModelSpec.autonomous.name, purpose: "files new downloads and runs Restructure", required: true),
        ModelCheck(name: ModelSpec.embedding.name, purpose: "learns from your corrections", required: false),
    ]
    /// nil until the user has been asked.
    private(set) var notificationsAllowed: Bool?
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    var loginError: String?

    private let client: OllamaClient
    private let notifier: Notifier

    init(client: OllamaClient, notifier: Notifier) {
        self.client = client
        self.notifier = notifier
    }

    /// Folio never touches a file until the model that does the filing is there.
    var canStart: Bool { ollamaRunning && checks.first(where: \.required)?.installed == true }

    func refresh() async {
        ollamaRunning = await client.isReachable()
        for i in checks.indices {
            checks[i].installed = ollamaRunning ? ((try? await client.hasModel(checks[i].name)) ?? false) : false
        }
        let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        notificationsAllowed = status == .notDetermined ? nil : (status == .authorized || status == .provisional)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func requestNotifications() async {
        await notifier.requestPermission()
        await refresh()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
