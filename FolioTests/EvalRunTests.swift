import Foundation
import Testing
@testable import Folio

/// Runs the real model over the 50-file corpus. Slow, needs Ollama, so it only runs when asked:
///   TEST_RUNNER_FOLIO_EVAL=e2b xcodebuild ... test -only-testing:FolioTests/EvalRunTests     (or =12b, or =e2b-think)
/// Raw answers are saved to docs/ so thresholds can be re-swept without asking the model again.
@Suite(.serialized)
struct EvalRunTests {
    struct RawRow: Codable {
        let file: String
        let seconds: Double
        let answer: ModelAnswer?
        let textCharacters: Int
        let rejected: String?
    }

    static let which = ProcessInfo.processInfo.environment["FOLIO_EVAL"]
    static let docs = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs")

    @Test(.enabled(if: which != nil)) func runCorpus() async throws {
        let label = Self.which ?? "e2b"
        var model: ModelSpec = label == "12b" ? .restructure : .small
        if label == "e2b-think" { model.think = true; model = ModelSpec(name: model.name, timeout: 180, keepAlive: model.keepAlive, think: true) }
        let sb = try Sandbox.withCorpus()
        defer { sb.cleanUp() }
        let tree = listFolders(in: sb.paths.documents)
        let classifier = Classifier(client: OllamaClient(), paths: sb.paths, model: model)
        let entries = try Fixtures.loadExpected()

        var raws: [String: RawClassification] = [:]
        var rows: [RawRow] = []
        for entry in entries {
            let raw = try await classifier.raw(sb.paths.downloads.appendingPathComponent(entry.file), tree: tree)
            raws[entry.file] = raw
            var rejected: String?
            if case .failure(let reason)? = raw.validation { rejected = "\(reason)" }
            rows.append(RawRow(file: entry.file, seconds: raw.seconds, answer: raw.answer, textCharacters: raw.context.text.count, rejected: rejected))
        }
        let finished = raws // immutable copy for the @Sendable classifier closure below
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(rows).write(to: Self.docs.appendingPathComponent("eval-raw-\(label).json"))

        let times = rows.map(\.seconds).sorted()
        var md = "# Eval run: gemma4:\(label) on the 50-file corpus\n\n"
        md += String(format: "Time per file (extract + model): median %.2fs, p95 %.2fs, max %.2fs\n\n", times[times.count / 2], times[Int(Double(times.count - 1) * 0.95)], times.last ?? 0)
        md += "| threshold | correct of auto-moved | wrong of all | auto-moved | queued | wrong auto-moves |\n|---|---|---|---|---|---|\n"
        var details = ""
        for threshold in [0.5, 0.6, 0.7, 0.8] {
            let report = await evaluate(entries) { entry in
                guard let raw = finished[entry.file] else { return .queue }
                switch classifier.decision(from: raw, threshold: threshold) {
                case .file(let move, _, _): return .file(folder: Self.relativeFolder(move.destinationFolder, sb.paths.documents))
                case .review: return .queue
                }
            }
            md += String(format: "| %.1f | %.0f%% | %.1f%% | %d | %d | %d |\n", threshold, report.correctRate * 100, report.wrongRate * 100,
                         report.autoMoved, report.queuedCorrectly + report.queuedUnnecessarily, report.wrong)
            if threshold == 0.6 { details = report.summary }
        }
        md += "\nDetail at threshold 0.6:\n\n```\n\(details)\n```\n"
        try md.write(to: Self.docs.appendingPathComponent("eval-\(label).md"), atomically: true, encoding: .utf8)
        print("EVAL \(label)\n\(md)")
    }

    static func relativeFolder(_ folder: URL, _ documents: URL) -> String {
        String(folder.path.dropFirst(documents.path.count + 1))
    }
}
