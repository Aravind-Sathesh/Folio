import Foundation
import Testing
@testable import Folio

/// End-to-end Restructure with the real model on a sandbox shaped like scripts/run-sandbox.sh: the fixture tree,
/// with the 50-file corpus and the markdown edge cases dumped into Documents/Misc. Slow, so only when asked:
///   TEST_RUNNER_FOLIO_RESTRUCTURE_RUN=1 xcodebuild ... test -only-testing:FolioTests/RestructureRunTests
/// Questions get the first option (as a stand-in for the user). Writes docs/restructure-run.md.
@Suite(.serialized)
struct RestructureRunTests {
    static let enabled = ProcessInfo.processInfo.environment["FOLIO_RESTRUCTURE_RUN"] != nil

    private func files(_ root: URL) -> [String] {
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
        var out: [String] = []
        while let url = walker?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true { out.append(String(url.path.dropFirst(root.path.count))) }
        }
        return out.sorted()
    }

    @Test(.enabled(if: enabled)) func fullSessionAppliesAndUndoesCleanly() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: Fixtures.documentsTree.path) {
            try fm.copyItem(at: Fixtures.documentsTree.appendingPathComponent(name), to: sb.paths.documents.appendingPathComponent(name))
        }
        let misc = sb.paths.documents.appendingPathComponent("Misc", isDirectory: true)
        try fm.copyItem(at: Fixtures.corpus, to: misc)
        try fm.copyItem(at: Fixtures.mdSamples, to: misc.appendingPathComponent("md-samples"))
        let before = files(sb.paths.documents)

        let client = OllamaClient()
        let log = MoveLog(paths: sb.paths)
        let mover = Mover(log: log)
        let cache = SummaryCache(paths: sb.paths)

        var t = Date()
        let candidates = RestructureScanner(paths: sb.paths).candidates()
        let summaries = try await Summarizer(client: client, cache: cache).summariseAll(candidates) { _, _ in }
        let summariseSeconds = Date().timeIntervalSince(t)

        t = Date()
        let proposer = RestructureProposer(client: client, paths: sb.paths)
        var proposal = try await proposer.propose(summaries)
        let proposeSeconds = Date().timeIntervalSince(t)
        let questions = proposal.questions
        var changedByAnswers = 0
        if !questions.isEmpty {
            let answers = questions.map { RestructureAnswer(questionID: $0.id, question: $0.text, choice: $0.options.first) }
            let affected = Set(questions.flatMap(\.affected))
            let subset = proposal.items.filter { affected.contains($0.path) }
            let others = proposal.items.filter { !affected.contains($0.path) }
            let revised = try await proposer.propose(subset, answers: answers, planned: plannedFolders(others), maxQuestions: 0)
            let byPath = Dictionary(uniqueKeysWithValues: revised.items.map { ($0.path, $0) })
            changedByAnswers = subset.filter { byPath[$0.path]?.proposedFolder != $0.proposedFolder }.count
            proposal.items = proposal.items.map { byPath[$0.path] ?? $0 }
        }
        let invalid = proposal.items.filter { $0.note != nil }
        let changes = changes(in: proposal.items, documents: sb.paths.documents)

        let session = UUID()
        let report = await RestructureApplier(paths: sb.paths, mover: mover).apply(proposal.items, sessionID: session)
        for record in report.moved {
            #expect(isInside(URL(fileURLWithPath: record.destination), sb.paths.documents))
            #expect(fm.fileExists(atPath: record.destination))
        }
        let after = files(sb.paths.documents)
        #expect(after.count == before.count) // nothing lost, nothing duplicated

        t = Date()
        _ = try await Summarizer(client: client, cache: cache).summariseAll(candidates) { _, _ in }
        let cachedSeconds = Date().timeIntervalSince(t)

        let undo = await Undoer(mover: mover, paths: sb.paths).run(undoPlan(records: await log.all(), selection: .session(session)))
        let restored = files(sb.paths.documents)
        #expect(restored == before)

        var md = "# Restructure run (gemma4:12b, sandbox)\n\n"
        md += "| Step | Result |\n|---|---|\n"
        md += "| Files read | \(candidates.count) |\n"
        md += String(format: "| Summaries | %.0f s (%.1f s a file, 2 at a time) |\n", summariseSeconds, summariseSeconds / Double(max(1, candidates.count)))
        md += String(format: "| Second run, all from cache | %.1f s |\n", cachedSeconds)
        md += String(format: "| Plan | %.0f s in %d batches |\n", proposeSeconds, batches(summaries).count)
        md += "| Questions asked | \(questions.count); answering them changed \(changedByAnswers) files |\n"
        md += "| Proposals refused by validation | \(invalid.count) |\n"
        md += "| Suggested changes | \(changes.count) of \(proposal.items.count) files (\(moves(in: proposal.items, documents: sb.paths.documents).count) to another folder, the rest renamed in place) |\n"
        md += "| Applied | \(report.moved.count) moved, \(report.failed.count) failed |\n"
        md += "| Undo | \(undo.restored.count) restored, \(undo.skipped.count) skipped; tree identical to before: \(restored == before) |\n\n"
        if !questions.isEmpty { md += "Questions:\n" + questions.map { "- \($0.text) (\($0.options.joined(separator: " / ")))" }.joined(separator: "\n") + "\n\n" }
        if !invalid.isEmpty { md += "Refused: " + invalid.map { "\(URL(fileURLWithPath: $0.path).lastPathComponent) (\($0.note ?? ""))" }.joined(separator: "; ") + "\n\n" }
        md += "Suggested changes, folder moves first:\n\n| Before | After | Reason |\n|---|---|---|\n"
        for item in changes.sorted(by: { (relativeFolder(of: $0.path, in: sb.paths.documents) == $0.proposedFolder ? 1 : 0, $0.path) < (relativeFolder(of: $1.path, in: sb.paths.documents) == $1.proposedFolder ? 1 : 0, $1.path) }).prefix(60) {
            let from = String(item.path.dropFirst(sb.paths.documents.path.count + 1))
            md += "| \(from) | \(item.proposedFolder ?? "")/\(item.proposedName ?? "") | \(item.reason ?? "") |\n"
        }
        try md.write(to: EvalRunTests.docs.appendingPathComponent("restructure-run.md"), atomically: true, encoding: .utf8)
        print("RESTRUCTURE RUN\n\(md)")
    }
}
