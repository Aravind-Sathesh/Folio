import ServiceManagement
import SwiftUI

struct SettingsView: View {
    let state: AppState
    let supportFolder: URL?
    @AppStorage(Settings.thresholdKey) private var threshold = defaultConfidenceThreshold
    @AppStorage(Settings.notifyKey) private var notify = true
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Start Folio when I log in", isOn: Binding(get: { loginStatus == .enabled }, set: setLogin))
                if loginStatus == .requiresApproval {
                    Text("Allow Folio in System Settings › General › Login Items.")
                    Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                }
                if let loginError { Text(loginError).foregroundStyle(.red) }
            }
            Section("How careful should Folio be?") {
                Slider(value: $threshold, in: Settings.thresholdRange) {
                    Text("Care")
                } minimumValueLabel: {
                    Text("Files more on its own")
                } maximumValueLabel: {
                    Text("Asks me more")
                }
                Text("The more careful it is, the more files wait for your review.").foregroundStyle(.secondary)
                Toggle("Tell me when files need review", isOn: $notify)
            }
            Section {
                DisclosureGroup("For developers") { developerDetails }
            }
        }
        .formStyle(.grouped)
        .onAppear { loginStatus = SMAppService.mainApp.status }
    }

    private var developerDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Filing and Restructure model: \(ModelSpec.autonomous.name)")
            Text("Search model: \(ModelSpec.embedding.name)")
            Text("Ollama: \(state.isModelOnline ? "running" : "not reachable")")
            Text(String(format: "Threshold: %.2f", threshold))
            Text("Last classifications").font(.headline).padding(.top, 4)
            if state.classifications.isEmpty { Text("None yet").foregroundStyle(.secondary) }
            ForEach(state.classifications) { note in
                Text(String(format: "%@ · %@ · %.1f s · %d corrections used", note.file, note.outcome, note.seconds, note.corrections)).font(.caption)
            }
            if let supportFolder {
                Button("Open support folder") { NSWorkspace.shared.open(supportFolder) }
            }
        }
    }

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Couldn't change this: \(error.localizedDescription)"
        }
        loginStatus = SMAppService.mainApp.status
    }
}
