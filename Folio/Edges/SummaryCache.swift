import Foundation

/// `summaries.json`: file summaries keyed by content hash, so a second restructure run skips extraction and the model.
actor SummaryCache {
    private let url: URL
    private var entries: [String: String]

    init(paths: FolioPaths) {
        url = paths.support.appendingPathComponent("summaries.json")
        entries = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    func summary(for hash: String) -> String? { entries[hash] }

    func store(_ summary: String, for hash: String) {
        entries[hash] = summary
        try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
    }

    var count: Int { entries.count }
}
