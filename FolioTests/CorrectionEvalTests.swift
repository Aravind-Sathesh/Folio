import Foundation
import Testing
@testable import Folio

/// Before/after proof for corrections (leave-one-out). Needs Ollama and takes minutes, so it only runs when asked:
///   TEST_RUNNER_FOLIO_EVAL_CORR=e2b xcodebuild ... test -only-testing:FolioTests/CorrectionEvalTests
/// Every file the model got wrong gets a simulated user correction (the right folder from expected.json).
/// Then every file is classified again with examples taken from the *other* files' corrections, never its own.
@Suite(.serialized)
struct CorrectionEvalTests {
    static let which = ProcessInfo.processInfo.environment["FOLIO_EVAL_CORR"]
    static let cutoff: Float = Float(ProcessInfo.processInfo.environment["FOLIO_EVAL_CUTOFF"] ?? "") ?? minimumSimilarity

    private struct Item {
        let file: String
        let expectedFolder: String
        let correction: Correction
        let vector: [Float]
    }

    @Test(.enabled(if: which != nil)) func beforeAndAfter() async throws {
        let label = Self.which ?? "e2b"
        let model: ModelSpec = label == "12b" ? .restructure : .small
        let sb = try Sandbox.withCorpus()
        defer { sb.cleanUp() }
        let client = OllamaClient()
        let entries = try Fixtures.loadExpected()
        let tree = listFolders(in: sb.paths.documents)
        let plain = Classifier(client: client, paths: sb.paths, model: model)
        let threshold = defaultConfidenceThreshold

        func ok(_ entry: CorpusEntry, _ raw: RawClassification) -> Bool {
            switch plain.decision(from: raw, threshold: threshold) {
            case .review: return entry.shouldQueue
            case .file(let move, _, _):
                let folder = EvalRunTests.relativeFolder(move.destinationFolder, sb.paths.documents)
                return !entry.shouldQueue && (folder == entry.folder || entry.acceptable?.contains(folder) == true)
            }
        }
        func outcome(_ raw: RawClassification) -> EvalOutcome {
            if case .file(let move, _, _) = plain.decision(from: raw, threshold: threshold) {
                return .file(folder: EvalRunTests.relativeFolder(move.destinationFolder, sb.paths.documents))
            }
            return .queue
        }

        // Before: no corrections.
        var before: [String: RawClassification] = [:]
        for entry in entries { before[entry.file] = try await plain.raw(sb.paths.downloads.appendingPathComponent(entry.file), tree: tree) }
        let beforeSnapshot = before

        // Simulated user corrections for every file that was filed wrongly or needlessly queued.
        var items: [Item] = []
        var summaries: [String: String] = [:]
        for entry in entries {
            guard let raw = beforeSnapshot[entry.file] else { continue }
            let summary = correctionSummary(text: raw.context.text, fileExtension: (entry.file as NSString).pathExtension, whereFrom: raw.context.whereFrom)
            summaries[entry.file] = summary
            guard !entry.shouldQueue, !ok(entry, raw), let expected = entry.folder, let wrong = raw.answer else { continue }
            let userName = ((entry.file as NSString).deletingPathExtension)
            let correction = Correction(id: UUID(), timestamp: Date(), summary: summary,
                                        folioChoice: Choice(name: wrong.name, folder: wrong.folder), userChoice: Choice(name: userName, folder: expected))
            items.append(Item(file: entry.file, expectedFolder: expected, correction: correction, vector: try await client.embed(input: summary)))
        }

        // After: leave-one-out.
        var after: [String: RawClassification] = [:]
        var injectedFrom: [String: [String]] = [:]
        for entry in entries {
            let query = try await client.embed(input: summaries[entry.file] ?? "")
            let pool = items.filter { $0.file != entry.file }.map { EmbeddedCorrection(correction: $0.correction, vector: $0.vector) }
            let chosen = topK(query: query, corrections: pool, cutoff: Self.cutoff)
            injectedFrom[entry.file] = items.filter { item in chosen.contains { $0.id == item.correction.id } }.map(\.file)
            let examples = chosen.map(\.example)
            let withExamples = Classifier(client: client, paths: sb.paths, model: model, corrections: { _ in examples })
            after[entry.file] = try await withExamples.raw(sb.paths.downloads.appendingPathComponent(entry.file), tree: tree)
        }
        let afterSnapshot = after

        let beforeOutcomes = beforeSnapshot.mapValues { outcome($0) }
        let afterOutcomes = afterSnapshot.mapValues { outcome($0) }
        let beforeReport = await evaluate(entries) { beforeOutcomes[$0.file] ?? .queue }
        let afterReport = await evaluate(entries) { afterOutcomes[$0.file] ?? .queue }

        var fixed: [String] = [], broke: [String] = [], repeats: [String] = [], stillWrong: [String] = []
        let correctedFolders = Dictionary(grouping: items, by: \.expectedFolder)
        for entry in entries {
            guard let b = beforeSnapshot[entry.file], let a = afterSnapshot[entry.file] else { continue }
            let (wasOK, isOK) = (ok(entry, b), ok(entry, a))
            if !wasOK && isOK { fixed.append(entry.file) }
            if wasOK && !isOK { broke.append(entry.file) }
            if !wasOK && !isOK {
                stillWrong.append(entry.file)
                // A repeat mistake: the same kind of file (same right folder) had already been corrected by someone else.
                if let folder = entry.folder, correctedFolders[folder]?.contains(where: { $0.file != entry.file }) == true { repeats.append(entry.file) }
            }
        }
        func pct(_ v: Double) -> String { String(format: "%.0f%%", v * 100) }
        var md = "# Corrections, before and after (gemma4:\(label), leave-one-out)\n\n"
        md += "\(items.count) simulated corrections from the files the model got wrong. Each file was then filed again using only the other files' corrections (similarity cutoff \(Self.cutoff), up to \(correctionExampleCount) examples).\n\n"
        md += "| | correct of auto-moved | wrong of all files | wrong auto-moves | queued |\n|---|---|---|---|---|\n"
        md += "| Before | \(pct(beforeReport.correctRate)) | \(String(format: "%.1f%%", beforeReport.wrongRate * 100)) | \(beforeReport.wrong) | \(beforeReport.queuedCorrectly + beforeReport.queuedUnnecessarily) |\n"
        md += "| After | \(pct(afterReport.correctRate)) | \(String(format: "%.1f%%", afterReport.wrongRate * 100)) | \(afterReport.wrong) | \(afterReport.queuedCorrectly + afterReport.queuedUnnecessarily) |\n\n"
        md += "- Fixed by corrections: \(fixed.count)\n- Broken by corrections: \(broke.count)\n- Still wrong: \(stillWrong.count)\n"
        md += "- **Repeat mistakes** (same kind of file as an already-corrected one, still wrong): \(repeats.count) (target 0)\n\n"
        md += "Fixed: \(fixed.joined(separator: ", "))\n\nBroken: \(broke.joined(separator: ", "))\n\nRepeat mistakes: \(repeats.joined(separator: ", "))\n\n"
        md += "Examples injected per file: " + entries.map { "\(injectedFrom[$0.file]?.count ?? 0)" }.joined(separator: " ") + "\n"
        try md.write(to: EvalRunTests.docs.appendingPathComponent("eval-corrections-\(label)-cutoff\(Self.cutoff).md"), atomically: true, encoding: .utf8)
        print("CORRECTION EVAL\n\(md)")
    }
}
