import SwiftUI

struct RestructureView: View {
    let model: RestructureModel

    var body: some View {
        Group {
            switch model.phase {
            case .idle:
                state("wand.and.stars", "Tidy up a folder",
                      "Pick a folder. Folio reads its files, suggests a cleaner layout inside it and asks when it's unsure. Nothing moves until you approve it, and the whole session undoes in one click.") {
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "folder.fill").foregroundStyle(.blue)
                            Text(shortPath(model.root.path)).font(.body.monospaced())
                            Button("Change…") {
                                if let url = pickFolder(startingAt: model.root, prompt: "Restructure") { model.message = model.choose(url) }
                            }
                        }
                        Button("Start") { model.begin() }.buttonStyle(.borderedProminent).controlSize(.large)
                    }
                }
            case .unavailable(let why):
                state("exclamationmark.triangle", "Restructure isn't ready", why) { Button("Try again") { model.begin() } }
            case .scanning: progress("Looking through your Documents…", nil)
            case .summarising(let done, let total): progress("Reading your files", (done, total))
            case .proposing(let done, let total): progress("Planning where things should go", (done, total))
            case .asking: QuestionStep(model: model).padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .review: ReviewStep(model: model).padding(20)
            case .applying(let done, let total): progress("Moving files", (done, total))
            case .finished(let moved, let failed):
                state("checkmark.circle", "Moved \(moved) files",
                      failed > 0 ? "\(failed) couldn't be moved and were left where they are." : "Everything you approved is in its new place.") {
                    Button("Undo all") { model.undoSession() }.controlSize(.large)
                }
            case .cancelled:
                state("xmark.circle", "Cancelled", "Nothing was moved.") { Button("Start again") { model.begin() } }
            case .failed(let why):
                state("exclamationmark.triangle", "Couldn't finish", why) { Button("Start again") { model.begin() } }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let message = model.message {
                Text(message).foregroundStyle(.secondary).padding(10).frame(maxWidth: .infinity).background(.bar)
            }
        }
    }

    private func state<Actions: View>(_ icon: String, _ title: String, _ detail: String, @ViewBuilder actions: () -> Actions) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(detail).frame(maxWidth: 420)
        } actions: {
            actions()
        }
    }

    private func progress(_ title: String, _ counts: (done: Int, total: Int)?) -> some View {
        VStack(spacing: 14) {
            if let counts {
                ProgressView(value: Double(counts.done), total: Double(max(counts.total, 1))).frame(width: 320)
                Text("\(title)… \(counts.done) of \(counts.total)").font(.headline)
            } else {
                ProgressView()
                Text(title).font(.headline)
            }
            if let note = model.capNote { Text(note).foregroundStyle(.secondary) }
            if case .applying = model.phase {} else { Button("Cancel") { model.cancel() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct QuestionStep: View {
    let model: RestructureModel

    var body: some View {
        if let question = model.currentQuestion {
            VStack(alignment: .leading, spacing: 10) {
                Text("Question \(model.questionIndex + 1) of \(model.questions.count)").foregroundStyle(.secondary)
                Text(question.text).font(.title3)
                ForEach(question.options, id: \.self) { option in
                    Button(option) { model.answer(option) }
                }
                Button("Not sure") { model.answer(nil) }
                if model.questionIndex > 0 { Button("Back") { model.back() } }
            }
        }
    }
}

private struct ReviewStep: View {
    let model: RestructureModel
    @State private var editing: String?
    @State private var name = ""
    @State private var folder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(model.changedItems.count) suggested changes").font(.title3)
                Spacer()
                Button("Select all") { model.selectAll(true) }
                Button("Select none") { model.selectAll(false) }
            }
            Text("\(model.unchangedCount) files stay where they are.").foregroundStyle(.secondary)
            List {
                ForEach(model.groups, id: \.folder) { group in
                    Section("\(folderDisplay(group.folder)) (\(group.items.count))") {
                        ForEach(group.items) { item in row(item) }
                    }
                }
            }
            HStack {
                Spacer()
                Button("Apply") { model.apply() }.buttonStyle(.borderedProminent).disabled(!model.changedItems.contains { $0.included })
            }
        }
    }

    private func row(_ item: RestructureItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: Binding(get: { item.included }, set: { model.setIncluded(item.path, $0) })).labelsHidden()
                VStack(alignment: .leading) {
                    Text(URL(fileURLWithPath: item.path).lastPathComponent)
                    Text("→ \(item.proposedName ?? "")").foregroundStyle(.secondary)
                    if let reason = item.reason { Text(reason).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Button(editing == item.path ? "Cancel" : "Edit…") { toggleEdit(item) }
            }
            if editing == item.path {
                TextField("Name", text: $name)
                TextField("Folder (inside Documents)", text: $folder)
                Button("Save") { if model.edit(item.path, name: name, folder: folder) { editing = nil } }
            }
        }
    }

    private func toggleEdit(_ item: RestructureItem) {
        if editing == item.path { editing = nil; return }
        editing = item.path
        name = item.proposedName ?? ""
        folder = item.proposedFolder ?? ""
    }
}
