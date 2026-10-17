import Foundation

struct Choice: Codable, Sendable, Equatable {
    /// File name without extension.
    let name: String
    /// Folder relative to Documents.
    let folder: String

    var display: String { "\(folder)/\(name)" }
}

/// The user changed what Folio did. Holds a short summary of the file, never its contents or real location.
struct Correction: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let timestamp: Date
    let summary: String
    let folioChoice: Choice
    let userChoice: Choice

    var example: CorrectionExample {
        CorrectionExample(summary: summary, folioChoice: folioChoice.display, userChoice: userChoice.display)
    }
}

/// What the model sees about a past file: type, source site and the first words. About 300 characters of text.
func correctionSummary(text: String, fileExtension: String, whereFrom: String?) -> String {
    var parts = ["type \(fileExtension.lowercased())"]
    if let host = whereFrom.flatMap({ URL(string: $0)?.host }) { parts.append("from \(host)") }
    parts.append("text: " + String(text.prefix(300)))
    return parts.joined(separator: ", ")
}

/// Compared as Unicode-canonical strings, so NFC and NFD spellings of one name are the same file.
func isUserChange(expected: String, current: String) -> Bool {
    expected.precomposedStringWithCanonicalMapping != current.precomposedStringWithCanonicalMapping
}

enum FolioPathStatus: Equatable {
    case at(String)
    /// Folio itself moved the file back out; that is not a correction.
    case undone
}

/// Where Folio last put the file, following Folio's own later moves (review accept, restructure) recorded after `recordID`.
/// A failed move cancels the intent right before it.
func folioPath(startingAt expected: String, afterRecord recordID: UUID, records: [MoveRecord]) -> FolioPathStatus {
    guard let start = records.firstIndex(where: { $0.id == recordID }) else { return .at(expected) }
    let later = effectiveRecords(Array(records[(start + 1)...]))
    var path = expected
    for record in later where record.source == path {
        if record.kind == .undo { return .undone }
        path = record.destination
    }
    return .at(path)
}
