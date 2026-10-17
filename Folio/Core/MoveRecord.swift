import Foundation

struct MoveRecord: Codable, Identifiable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case auto, review, restructure, undo, failed }

    let id: UUID
    let timestamp: Date
    let sessionID: UUID?
    let source: String
    let destination: String
    let originalName: String
    let newName: String
    let confidence: Double?
    let reason: String?
    let kind: Kind
    /// For `.undo`: the id of the record this reverses.
    let undoes: UUID?
    /// Volume and inode of the file, so Folio recognises a file it has moved even after the user moves it again.
    let fileKey: FileKey?

    init(id: UUID = UUID(), timestamp: Date = Date(), sessionID: UUID? = nil, source: String, destination: String,
         confidence: Double? = nil, reason: String? = nil, kind: Kind, undoes: UUID? = nil, fileKey: FileKey? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.source = source
        self.destination = destination
        originalName = URL(fileURLWithPath: source).lastPathComponent
        newName = URL(fileURLWithPath: destination).lastPathComponent
        self.confidence = confidence
        self.reason = reason
        self.kind = kind
        self.undoes = undoes
        self.fileKey = fileKey
    }
}
