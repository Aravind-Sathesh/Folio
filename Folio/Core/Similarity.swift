import Foundation

/// Corrections closer than this to the new file are used as examples; unrelated ones stay out of the prompt. Tuned in task 18.
let minimumSimilarity: Float = 0.5
let correctionExampleCount = 5

struct EmbeddedCorrection: Sendable, Equatable {
    let correction: Correction
    let vector: [Float]
}

/// 1 for the same direction, 0 for unrelated. Mismatched sizes and zero vectors score 0 rather than crash.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot: Float = 0, normA: Float = 0, normB: Float = 0
    for i in a.indices {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    let denominator = (normA * normB).squareRoot()
    return denominator > 0 && denominator.isFinite ? dot / denominator : 0
}

/// The `k` corrections most similar to `query`, best first, none below the cutoff.
func topK(query: [Float], corrections: [EmbeddedCorrection], k: Int = correctionExampleCount, cutoff: Float = minimumSimilarity) -> [Correction] {
    corrections
        .map { (item: $0, score: cosineSimilarity(query, $0.vector)) }
        .filter { $0.score >= cutoff }
        .sorted { $0.score > $1.score }
        .prefix(max(0, k))
        .map(\.item.correction)
}
