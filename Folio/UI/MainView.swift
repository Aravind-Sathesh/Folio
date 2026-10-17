import SwiftUI

struct MenuActions {
    var undo: (UUID) -> Void = { _ in }
    var undoLast: () -> Void = {}
}

/// One window for everything: what Folio is doing, files waiting for you, Restructure and settings.
struct MainView: View {
    let model: AppModel

    var body: some View {
        @Bindable var state = model.state
        NavigationSplitView {
            List(MainSection.allCases, selection: $state.section) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .badge(section == .review ? model.state.reviewCount : 0)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
            .safeAreaInset(edge: .bottom) {
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit Folio", systemImage: "power").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
            }
        } detail: {
            detail(state.section).navigationTitle(state.section.rawValue)
        }
        .frame(minWidth: 760, minHeight: 480)
    }

    @ViewBuilder
    private func detail(_ section: MainSection) -> some View {
            switch section {
            case .activity: ActivityView(state: model.state, actions: model.menuActions,
                                         watched: (model.folderConfig?.watched ?? []).map { URL(fileURLWithPath: $0.path).lastPathComponent })
            case .review:
                if let review = model.review { ReviewView(model: review) }
            case .restructure:
                if let restructure = model.restructure { RestructureView(model: restructure) }
            case .folders: FoldersView(model: model)
            case .settings: SettingsView(state: model.state, supportFolder: model.supportFolder)
            }
    }
}

private struct ActivityView: View {
    @Bindable var state: AppState
    let actions: MenuActions
    let watched: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusCard
                if let error = state.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recently filed").font(.headline)
                        Spacer()
                        if !state.recentMoves.isEmpty { Button("Undo last", action: actions.undoLast) }
                    }
                    if state.recentMoves.isEmpty {
                        ContentUnavailableView("Nothing filed yet", systemImage: "tray",
                                               description: Text("Save or copy a file into Downloads and Folio files it about a minute later."))
                            .frame(maxWidth: .infinity)
                    } else {
                        ForEach(state.recentMoves) { move in row(move) }
                    }
                }
            }
            .padding(24)
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 28)).foregroundStyle(tint).frame(width: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Pause", isOn: $state.isPaused).toggleStyle(.switch).disabled(state.needsOnboarding)
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private func row(_ move: RecentMove) -> some View {
        HStack {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(move.name)
                Text(folderDisplay(move.folder)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Undo") { actions.undo(move.id) }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var icon: String {
        switch state.status {
        case .needsSetup: "wand.and.stars"
        case .watching: "eye"
        case .paused: "pause.circle"
        case .modelOffline: "bolt.slash"
        case .working: "arrow.triangle.2.circlepath"
        }
    }

    private var tint: Color {
        switch state.status {
        case .watching, .working: .green
        case .paused: .orange
        case .modelOffline: .red
        case .needsSetup: .blue
        }
    }

    private var title: String {
        switch state.status {
        case .needsSetup: "Finish setup to start"
        case .watching: "Watching for new files"
        case .paused: "Paused"
        case .modelOffline: "The model isn't running"
        case .working: "Filing a file…"
        }
    }

    private var subtitle: String {
        switch state.status {
        case .needsSetup: "Folio won't touch anything until you press Start in the welcome window."
        case .watching: watched.isEmpty ? "No folders are being watched. Add some in Folders." : ListFormatter.localizedString(byJoining: watched) + "."
        case .paused: "Nothing will be moved until you turn Pause off."
        case .modelOffline: "New files wait until Ollama is back."
        case .working: "This usually takes a few seconds."
        }
    }
}
