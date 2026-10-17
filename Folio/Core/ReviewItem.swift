import Foundation

/// A file Folio left alone because it wasn't sure. `suggested*` is nil when the model gave no usable answer.
struct ReviewItem: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let path: String
    let suggestedName: String?
    let suggestedFolder: String?
    let reason: String
    let queuedAt: Date

    init(id: UUID = UUID(), path: String, suggestion: Suggestion?, reason: String, queuedAt: Date = Date()) {
        self.id = id
        self.path = path
        suggestedName = suggestion?.name
        suggestedFolder = suggestion?.folder
        self.reason = reason
        self.queuedAt = queuedAt
    }

    var suggestion: Suggestion? {
        guard let suggestedName, let suggestedFolder else { return nil }
        return Suggestion(name: suggestedName, folder: suggestedFolder)
    }
}
