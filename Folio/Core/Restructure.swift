import Foundation

/// The first run reads this many of the most recently changed files; the user can run again for more.
let restructureFileCap = 300
let restructureBatchSize = 40
let restructureMaxQuestions = 5

struct RestructureItem: Codable, Identifiable, Sendable, Equatable {
    /// Absolute path of the file today.
    let path: String
    let summary: String
    let contentHash: String
    var proposedFolder: String?
    /// Final file name, extension included.
    var proposedName: String?
    var reason: String?
    var included = true
    /// Why the file stays put when the model's proposal was unusable.
    var note: String?

    var id: String { path }
}

struct RestructureQuestion: Codable, Identifiable, Sendable, Equatable {
    let id: Int
    let text: String
    let options: [String]
    /// Paths of the files this question is about.
    let affected: [String]
}

struct RestructureAnswer: Codable, Sendable, Equatable {
    let questionID: Int
    let question: String
    /// nil means "Not sure".
    let choice: String?
}

/// Newest first, capped. Ties break by path so the choice is stable.
func selectFiles(_ files: [(url: URL, modified: Date)], cap: Int = restructureFileCap) -> [URL] {
    files.sorted { ($0.modified, $1.url.path) > ($1.modified, $0.url.path) }.prefix(max(0, cap)).map(\.url)
}

func batches<T>(_ items: [T], size: Int = restructureBatchSize) -> [[T]] {
    guard size > 0 else { return [] }
    return stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
}

func relativeFolder(of path: String, in documents: URL) -> String {
    let folder = URL(fileURLWithPath: path).deletingLastPathComponent().path
    return folder.count > documents.path.count ? String(folder.dropFirst(documents.path.count + 1)) : ""
}

/// Items whose proposal actually moves or renames the file. Capitalisation, spacing and punctuation-only
/// renames don't count: the model likes Title Case, and "same.md" -> "Same.md" is churn, not tidying.
func changes(in items: [RestructureItem], documents: URL) -> [RestructureItem] {
    items.filter { item in
        guard let folder = item.proposedFolder, let name = item.proposedName else { return false }
        let current = URL(fileURLWithPath: item.path)
        let sameFolder = relativeFolder(of: item.path, in: documents).precomposedStringWithCanonicalMapping == folder.precomposedStringWithCanonicalMapping
        return !(sameFolder && nameKey(current.lastPathComponent) == nameKey(name))
    }
}

/// Folder moves among the changes (the rest are renames in place).
func moves(in items: [RestructureItem], documents: URL) -> [RestructureItem] {
    changes(in: items, documents: documents).filter { relativeFolder(of: $0.path, in: documents) != $0.proposedFolder }
}

/// A name reduced to its letters and digits, lowercased, for "is this really a different name?".
func nameKey(_ name: String) -> String {
    String(name.precomposedStringWithCanonicalMapping.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
}

/// Every proposed folder and each of its parents, for the "planned" tree that later batches and the apply step may build on.
func plannedFolders(_ items: [RestructureItem]) -> Set<String> {
    var out: Set<String> = []
    for folder in items.compactMap(\.proposedFolder) {
        var path = ""
        for part in folder.split(separator: "/") {
            path = path.isEmpty ? String(part) : path + "/" + part
            out.insert(path)
        }
    }
    return out
}
