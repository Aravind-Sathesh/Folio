import Foundation

/// What the model said and how long it took, before any decision logic. Kept so thresholds can be re-tried without re-asking.
struct RawClassification: Sendable {
    let answer: ModelAnswer?
    let validation: Result<ValidatedMove, RejectReason>?
    let context: ExtractedContext
    let seconds: TimeInterval
    /// How many past corrections went into the prompt. Only the count is kept, never their contents.
    let correctionsUsed: Int
}

/// extract -> prompt -> model -> validate. Network and model failures are thrown for the pipeline to retry;
/// an unusable answer is not an error, it just becomes a review item.
struct Classifier: Sendable {
    let client: OllamaClient
    let extractor = Extractor()
    let paths: FolioPaths
    var model: ModelSpec = .autonomous
    /// Past corrections that look like this file; empty when there are none or the lookup fails.
    var corrections: @Sendable (_ summary: String) async -> [CorrectionExample] = { _ in [] }
    /// Watched and excluded folders; nil means just Downloads and Documents.
    var folders: @Sendable () -> FolderConfig? = { nil }

    func raw(_ file: URL, tree: [String], now: Date = Date()) async throws -> RawClassification {
        let started = Date()
        let context = await extractor.extract(file)
        let examples = await corrections(correctionSummary(text: context.text, fileExtension: file.pathExtension, whereFrom: context.whereFrom))
        let prompt = Prompt.build(fileName: file.lastPathComponent, context: context, tree: tree, corrections: examples, now: now)
        let answer: ModelAnswer?
        do {
            answer = try await client.chat(model, system: prompt.system, user: prompt.user, schema: classificationSchema, as: ModelAnswer.self)
        } catch OllamaError.badResponse {
            answer = nil
        }
        let validation = answer.map { validate(proposal: Proposal(name: $0.name, folder: $0.folder), source: file, paths: paths, config: folders()) }
        return RawClassification(answer: answer, validation: validation, context: context, seconds: Date().timeIntervalSince(started), correctionsUsed: examples.count)
    }

    func decision(from raw: RawClassification, threshold: Double) -> Decision {
        guard let answer = raw.answer, let validation = raw.validation else {
            return .review(suggestion: nil, confidence: 0, reason: "Folio couldn't read the model's answer")
        }
        return decide(answer: answer, validation: validation, context: raw.context, threshold: threshold)
    }

    func classify(_ file: URL, tree: [String], threshold: Double = defaultConfidenceThreshold) async throws -> Decision {
        decision(from: try await raw(file, tree: tree), threshold: threshold)
    }
}
