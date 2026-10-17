import AppKit
import SwiftUI

/// A folder chooser sheet; nil when the user cancels.
@MainActor
func pickFolder(startingAt start: URL?, prompt: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = prompt
    panel.directoryURL = start
    return panel.runModal() == .OK ? panel.url?.realPath : nil
}

/// "~/Documents/Work" instead of the full path.
func shortPath(_ path: String) -> String {
    let home = FolioPaths.home.path
    return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
}

struct FoldersView: View {
    let model: AppModel
    @State private var config: FolderConfig?
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                ForEach(config?.watched ?? []) { folder in
                    HStack {
                        folderLabel(folder.path)
                        Spacer()
                        Text("Subfolders").foregroundStyle(.secondary)
                        Toggle("Subfolders", isOn: Binding(get: { folder.subfolders }, set: { on in
                            change { c in if let i = c.watched.firstIndex(where: { $0.path == folder.path }) { c.watched[i].subfolders = on } }
                        }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                        removeButton { change { $0.watched.removeAll { $0.path == folder.path } } }
                    }
                }
                Button("Add folder…") { add(.watched) }
            } header: {
                Text("Watch these folders")
            } footer: {
                Text("New files here are renamed and filed into Documents.").foregroundStyle(.secondary)
            }

            Section {
                if config?.excluded.isEmpty ?? true { Text("Nothing excluded").foregroundStyle(.secondary) }
                ForEach(config?.excluded ?? [], id: \.self) { path in
                    HStack {
                        folderLabel(path)
                        Spacer()
                        removeButton { change { $0.excluded.removeAll { $0 == path } } }
                    }
                }
                Button("Add folder…") { add(.excluded) }
            } header: {
                Text("Never touch these folders")
            } footer: {
                Text("Folio won't take files from them, file into them, or restructure them. Hidden folders, apps and Library are always left alone.")
                    .foregroundStyle(.secondary)
            }

            if let problem { Text(problem).foregroundStyle(.red) }
        }
        .formStyle(.grouped)
        .onAppear { config = model.folderConfig }
    }

    private func folderLabel(_ path: String) -> some View {
        Label {
            VStack(alignment: .leading) {
                Text(URL(fileURLWithPath: path).lastPathComponent)
                Text(shortPath(path)).font(.caption).foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: "folder.fill").foregroundStyle(.blue)
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
            .buttonStyle(.plain)
            .help("Remove")
    }

    private enum Target { case watched, excluded }

    private func add(_ target: Target) {
        guard let url = pickFolder(startingAt: FolioPaths.home, prompt: target == .watched ? "Watch" : "Exclude") else { return }
        if let issue = folderChoiceProblem(url, home: FolioPaths.home) { problem = issue; return }
        problem = nil
        change { c in
            switch target {
            case .watched where !c.watched.contains(where: { $0.path == url.path }):
                c.watched.append(WatchedFolder(path: url.path, subfolders: true))
            case .excluded where !c.excluded.contains(url.path):
                c.excluded.append(url.path)
            default: break
            }
        }
    }

    private func change(_ edit: (inout FolderConfig) -> Void) {
        model.updateFolders(edit)
        config = model.folderConfig
    }
}
