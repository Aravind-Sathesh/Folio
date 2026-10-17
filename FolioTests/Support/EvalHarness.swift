import Foundation

struct CorpusEntry: Decodable, Sendable {
    let file: String
    let folder: String?
    let acceptable: [String]?
    let shouldQueue: Bool
}

enum EvalOutcome: Sendable, Equatable {
    case file(folder: String)
    case queue
}

struct EvalReport: Sendable {
    var correct = 0
    var acceptable = 0
    var wrong = 0
    var queuedCorrectly = 0
    var queuedUnnecessarily = 0
    var wrongMoves: [(file: String, got: String, expected: String)] = []

    var autoMoved: Int { correct + acceptable + wrong }
    var total: Int { autoMoved + queuedCorrectly + queuedUnnecessarily }
    /// Share of auto-moved files that landed somewhere defensible (the "≥ 80%" metric).
    var correctRate: Double { autoMoved == 0 ? 0 : Double(correct + acceptable) / Double(autoMoved) }
    /// Wrong auto-moves as a share of all files (the "≤ 5%" metric).
    var wrongRate: Double { total == 0 ? 0 : Double(wrong) / Double(total) }

    var summary: String {
        var lines = [
            "files \(total): correct \(correct), acceptable \(acceptable), wrong \(wrong), queued \(queuedCorrectly + queuedUnnecessarily) "
                + "(\(queuedCorrectly) rightly, \(queuedUnnecessarily) needlessly)",
            String(format: "correct of auto-moved %.0f%%, wrong of all %.1f%%", correctRate * 100, wrongRate * 100),
        ]
        for move in wrongMoves { lines.append("  wrong: \(move.file) -> \(move.got) (expected \(move.expected))") }
        return lines.joined(separator: "\n")
    }
}

/// Scores a classifier against the corpus ground truth. Classifiers decide folder-or-queue; no files are moved.
func evaluate(_ entries: [CorpusEntry], classify: @Sendable (CorpusEntry) async -> EvalOutcome) async -> EvalReport {
    var report = EvalReport()
    for entry in entries {
        switch await classify(entry) {
        case .queue:
            if entry.shouldQueue { report.queuedCorrectly += 1 } else { report.queuedUnnecessarily += 1 }
        case .file(let folder):
            if !entry.shouldQueue, folder == entry.folder {
                report.correct += 1
            } else if !entry.shouldQueue, entry.acceptable?.contains(folder) == true {
                report.acceptable += 1
            } else {
                report.wrong += 1
                report.wrongMoves.append((entry.file, folder, entry.folder ?? "(queue)"))
            }
        }
    }
    return report
}
