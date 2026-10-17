import Foundation
import Testing
@testable import Folio

struct SimilarityTests {
    private func correction(_ n: Int) -> Correction {
        Correction(id: UUID(), timestamp: Date(), summary: "s\(n)", folioChoice: Choice(name: "a", folder: "A"), userChoice: Choice(name: "b", folder: "B"))
    }

    @Test func cosineBasics() {
        #expect(cosineSimilarity([1, 0], [1, 0]) == 1)
        #expect(cosineSimilarity([1, 0], [0, 1]) == 0)
        #expect(cosineSimilarity([1, 0], [-1, 0]) == -1)
        #expect(abs(cosineSimilarity([1, 1], [1, 0]) - 0.7071) < 0.001)
        #expect(cosineSimilarity([0, 0], [1, 0]) == 0)   // zero vector
        #expect(cosineSimilarity([1], [1, 0]) == 0)       // mismatched size
        #expect(cosineSimilarity([], []) == 0)
        #expect(cosineSimilarity([.nan, 1], [1, 1]) == 0) // garbage in, "unrelated" out
    }

    @Test func topKOrdersByScoreAppliesCutoffAndLimit() {
        let items = (0..<8).map { EmbeddedCorrection(correction: correction($0), vector: [1, Float($0) * 0.2]) }
        let result = topK(query: [1, 0], corrections: items, k: 3, cutoff: 0.5)
        #expect(result.map(\.summary) == ["s0", "s1", "s2"])         // closest first
        #expect(topK(query: [1, 0], corrections: items, k: 100, cutoff: 0.99).map(\.summary) == ["s0"]) // cutoff
        #expect(topK(query: [0, 1], corrections: items, k: 5, cutoff: 0.99).isEmpty)
        #expect(topK(query: [1, 0], corrections: [], k: 5).isEmpty)
        #expect(topK(query: [1, 0], corrections: items, k: 0).isEmpty)
    }
}

struct CorrectionIndexTests {
    /// Fake embedder: "invoice" texts point one way, "recipe" texts another, anything else is unrelated to both.
    private static func embedHandler(_ request: URLRequest) throws -> (Int, Data) {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable { let n = stream.read(&buf, maxLength: buf.count); if n <= 0 { break }; data.append(buf, count: n) }
            body = data
        }
        let input = ((try? JSONSerialization.jsonObject(with: body ?? Data()) as? [String: Any])?["input"] as? String ?? "").lowercased()
        let vector: [Double] = input.contains("invoice") ? [1, 0.1, 0] : input.contains("recipe") ? [0, 0.1, 1] : [0.5, -1, 0.5]
        return (200, try JSONSerialization.data(withJSONObject: ["embeddings": [vector]]))
    }

    private func correction(_ summary: String) -> Correction {
        Correction(id: UUID(), timestamp: Date(), summary: summary, folioChoice: Choice(name: "X", folder: "Finance/Invoices"), userChoice: Choice(name: "Y", folder: "Finance/Receipts"))
    }

    @Test func similarCorrectionsComeBackAndUnrelatedOnesDoNot() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let index = CorrectionIndex(paths: sb.paths, client: StubURLProtocol.client(Self.embedHandler))
        let tracker = CorrectionTracker(paths: sb.paths, onCorrection: { await index.add($0) })
        for text in ["type pdf, text: Stripe invoice 1", "type pdf, text: Stripe invoice 2", "type txt, text: a pancake recipe"] {
            await tracker.record(summary: text, folioChoice: Choice(name: "X", folder: "Finance/Invoices"), userChoice: Choice(name: "Y", folder: "Finance/Receipts"))
        }
        try await Task.sleep(for: .milliseconds(300)) // onCorrection runs detached
        let examples = await index.examples(forSummary: "type pdf, text: Another invoice from Stripe")
        #expect(examples.count == 2)
        #expect(examples.allSatisfy { $0.summary.contains("invoice") })
        #expect(examples.first?.userChoice == "Finance/Receipts/Y")
        #expect(await index.examples(forSummary: "type png, text: holiday photo").isEmpty) // unrelated: nothing injected
    }

    @Test func emptyStoreAndEmbeddingFailureGiveNoExamplesAndNoError() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let empty = CorrectionIndex(paths: sb.paths, client: StubURLProtocol.client(Self.embedHandler))
        #expect(await empty.examples(forSummary: "invoice").isEmpty)

        let tracker = CorrectionTracker(paths: sb.paths)
        await tracker.record(summary: "invoice", folioChoice: Choice(name: "X", folder: "A"), userChoice: Choice(name: "Y", folder: "B"))
        let offline = CorrectionIndex(paths: sb.paths, client: StubURLProtocol.client { _ in throw URLError(.cannotConnectToHost) })
        await offline.backfill()                                 // can't embed: silently skipped
        #expect(await offline.examples(forSummary: "invoice").isEmpty)
    }

    @Test func backfillEmbedsOldCorrectionsAndSurvivesRestart() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let tracker = CorrectionTracker(paths: sb.paths) // no index attached: simulates corrections from before embeddings existed
        await tracker.record(summary: "old invoice", folioChoice: Choice(name: "X", folder: "A"), userChoice: Choice(name: "Y", folder: "B"))
        let client = StubURLProtocol.client(Self.embedHandler)
        let index = CorrectionIndex(paths: sb.paths, client: client)
        #expect(await index.examples(forSummary: "invoice").isEmpty) // not embedded yet
        await index.backfill()
        #expect(await index.examples(forSummary: "invoice").count == 1)
        let restarted = CorrectionIndex(paths: sb.paths, client: client)
        #expect(await restarted.examples(forSummary: "invoice").count == 1) // vectors were persisted
    }
}
