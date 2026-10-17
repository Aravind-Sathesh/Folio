import AppKit
import SwiftUI

struct OnboardingView: View {
    let model: OnboardingModel
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Welcome to Folio").font(.title)
            Text("Folio files your downloads for you. It reads each new file on this Mac, renames it and puts it in the right folder in Documents, and nothing leaves your computer.")
                .fixedSize(horizontal: false, vertical: true) // wrap instead of truncating
            Label("Folio never deletes or overwrites anything, and every move can be undone.", systemImage: "arrow.uturn.backward.circle")
                .fixedSize(horizontal: false, vertical: true)

            GroupBox("Before you start") {
                VStack(alignment: .leading, spacing: 8) {
                    status(model.ollamaRunning, "Ollama is running",
                           fix: model.ollamaRunning ? nil : "Ollama isn't running. Open the Ollama app, or run: ollama serve")
                    ForEach(model.checks) { check in
                        status(check.installed, "\(check.name): \(check.purpose)\(check.required ? "" : " (optional)")",
                               fix: check.installed ? nil : check.fix, copy: check.installed ? nil : check.fix)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
            }

            Toggle("Start Folio when I log in", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            if let error = model.loginError { Text(error).foregroundStyle(.red) }
            HStack {
                switch model.notificationsAllowed {
                case nil: Button("Allow notifications") { Task { await model.requestNotifications() } }
                case true?: Label("Notifications are on", systemImage: "bell")
                case false?: Label("Notifications are off. You can turn them on in System Settings.", systemImage: "bell.slash")
                }
            }

            HStack {
                Spacer()
                Button("Check again") { Task { await model.refresh() } }
                Button("Start watching", action: start).buttonStyle(.borderedProminent).disabled(!model.canStart)
            }
        }
        .padding(24)
        .frame(width: 560)
        .task { await model.refresh() }
    }

    private func status(_ ok: Bool, _ title: String, fix: String?, copy: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: ok ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(ok ? Color.primary : Color.red)
            if let fix {
                HStack {
                    Text(fix).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    if let copy {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(copy, forType: .string)
                        }
                        .controlSize(.small)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }
}
