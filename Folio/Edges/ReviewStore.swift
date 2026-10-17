import Foundation

/// `review.json`: files waiting for the user. Written atomically after every change.
actor ReviewStore {
    private let url: URL
    private(set) var items: [ReviewItem] = []

    init(paths: FolioPaths) {
        url = paths.support.appendingPathComponent("review.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let loaded = (try? Data(contentsOf: url)).flatMap { try? decoder.decode([ReviewItem].self, from: $0) } ?? []
        // Files that were moved or deleted while Folio wasn't running are dropped quietly.
        items = loaded.filter { FileManager.default.fileExists(atPath: $0.path) }
        if items.count != loaded.count { try? Self.write(items, to: url) }
    }

    @discardableResult
    func add(_ item: ReviewItem) -> Bool {
        guard !items.contains(where: { $0.path == item.path }) else { return false }
        items.append(item)
        try? Self.write(items, to: url)
        return true
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        try? Self.write(items, to: url)
    }

    private static func write(_ items: [ReviewItem], to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(items).write(to: url, options: .atomic)
    }
}
