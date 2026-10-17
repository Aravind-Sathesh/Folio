import Foundation
import Observation

@MainActor @Observable
final class ReviewModel {
    private(set) var items: [ReviewItem] = []
    private(set) var folders: [String] = []
    /// One line for the window, cleared by the next successful action.
    var message: String?

    private let actions: ReviewActions
    private let state: AppState

    init(actions: ReviewActions, state: AppState) {
        self.actions = actions
        self.state = state
    }

    func reload() async {
        items = await actions.store.items.filter { FileManager.default.fileExists(atPath: $0.path) }
        folders = listFolders(in: actions.paths.documents, excluding: actions.folders()?.excludedURLs ?? [])
        state.reviewCount = items.count
    }

    func accept(_ item: ReviewItem) async { await finish(actions.accept(item)) }

    func edit(_ item: ReviewItem, name: String, folder: String) async -> Bool {
        await finish(actions.edit(item, name: name, folder: folder))
    }

    func leave(_ item: ReviewItem) async {
        await actions.leave(item)
        message = nil
        await reload()
    }

    @discardableResult
    private func finish(_ result: Result<MoveRecord, ReviewError>) async -> Bool {
        switch result {
        case .success(let record):
            let folder = URL(fileURLWithPath: record.destination).deletingLastPathComponent().path
            state.record(RecentMove(id: record.id, name: record.newName, folder: String(folder.dropFirst(actions.paths.documents.path.count + 1))))
            message = nil
        case .failure(let error):
            message = error.plainMessage
        }
        await reload()
        return result.isSuccess
    }
}
