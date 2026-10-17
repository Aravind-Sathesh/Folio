import Foundation

private struct StoredVector: Codable { let id: UUID; let vector: [Float] }

/// Finds past corrections that look like a new file. Vectors live in `embeddings.jsonl` next to `corrections.jsonl`,
/// so the corrections file stays append-only and backfilling is just "ids without a vector".
actor CorrectionIndex {
    private let correctionsURL: URL
    private let vectorsURL: URL
    private let client: OllamaClient
    private var vectors: [UUID: [Float]] = [:]

    init(paths: FolioPaths, client: OllamaClient) {
        correctionsURL = paths.support.appendingPathComponent("corrections.jsonl")
        vectorsURL = paths.support.appendingPathComponent("embeddings.jsonl")
        self.client = client
        for stored in JSONLines.readAll(StoredVector.self, from: vectorsURL) { vectors[stored.id] = stored.vector }
    }

    /// Embeds a new correction. Failure is fine: backfill retries it later.
    func add(_ correction: Correction) async {
        guard vectors[correction.id] == nil, let vector = try? await client.embed(input: correction.summary) else { return }
        store(correction.id, vector)
    }

    /// Embeds corrections that were saved while Ollama was away or before this existed.
    func backfill() async {
        for correction in JSONLines.readAll(Correction.self, from: correctionsURL) { await add(correction) }
    }

    /// Up to five examples for a file with this summary. Any failure means no examples, never an error.
    func examples(forSummary summary: String) async -> [CorrectionExample] {
        let embedded = JSONLines.readAll(Correction.self, from: correctionsURL).compactMap { c in
            vectors[c.id].map { EmbeddedCorrection(correction: c, vector: $0) }
        }
        guard !embedded.isEmpty, let query = try? await client.embed(input: summary) else { return [] }
        return topK(query: query, corrections: embedded).map(\.example)
    }

    private func store(_ id: UUID, _ vector: [Float]) {
        vectors[id] = vector
        try? JSONLines.append(StoredVector(id: id, vector: vector), to: vectorsURL)
    }
}
