import AppKit
import SwiftUI

struct ReviewView: View {
    let model: ReviewModel

    var body: some View {
        VStack(spacing: 0) {
            if model.items.isEmpty {
                ContentUnavailableView("Nothing to review", systemImage: "checkmark.circle", description: Text("Files Folio isn't sure about will show up here."))
            } else {
                List(model.items) { item in
                    ReviewRow(item: item, model: model)
                }
            }
            if let message = model.message {
                Text(message).foregroundStyle(.red).padding(8)
            }
        }
        .task { await model.reload() }
    }
}

private struct ReviewRow: View {
    let item: ReviewItem
    let model: ReviewModel
    @State private var editing = false
    @State private var name = ""
    @State private var parent = ""
    @State private var newFolder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(URL(fileURLWithPath: item.path).lastPathComponent).font(.headline)
            Text(item.reason).foregroundStyle(.secondary)
            if let suggestion = item.suggestion {
                Text("Suggested: \(folderDisplay(suggestion.folder)) › \(suggestion.name)")
            }
            if editing { editor }
            HStack {
                Button("File it") { Task { await model.accept(item) } }.disabled(item.suggestion == nil)
                Button(editing ? "Cancel" : "Edit…") { startEditing() }
                Button("Leave it") { Task { await model.leave(item) } }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) }
            }
        }
        .padding(.vertical, 4)
    }

    private var editor: some View {
        VStack(alignment: .leading) {
            TextField("Name", text: $name)
            Picker("Folder", selection: $parent) {
                ForEach(model.folders, id: \.self) { Text(folderDisplay($0)).tag($0) }
            }
            TextField("New folder inside it (optional)", text: $newFolder)
            Button("File here") {
                let folder = newFolder.trimmingCharacters(in: .whitespaces).isEmpty ? parent : parent + "/" + newFolder
                Task { if await model.edit(item, name: name, folder: folder) { editing = false } }
            }
            .disabled(parent.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func startEditing() {
        editing.toggle()
        guard editing else { return }
        name = item.suggestedName ?? ""
        parent = item.suggestedFolder.flatMap { model.folders.contains($0) ? $0 : nil } ?? model.folders.first ?? ""
        newFolder = ""
    }
}
