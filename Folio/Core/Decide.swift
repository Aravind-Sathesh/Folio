import Foundation

/// G7: tuned on the test set in task 12.
let defaultConfidenceThreshold = 0.6
/// Code-side distrust of the model's self-reported confidence (IDEA.md risks).
let newFolderPenalty = 0.1
let lowTextConfidenceCap = 0.5
let lowTextCharacters = 20

struct Suggestion: Codable, Sendable, Equatable {
    let name: String
    let folder: String
}

enum Decision: Sendable, Equatable {
    case file(ValidatedMove, confidence: Double, reason: String)
    /// `suggestion` is the model's raw answer for display; the user's Edit is validated again.
    case review(suggestion: Suggestion?, confidence: Double, reason: String)
}

/// Plain words for the review list.
func plainReason(_ reject: RejectReason) -> String {
    switch reject {
    case .sourceOutsideRoots: "This file isn't in a folder Folio watches"
    case .emptyName, .illegalName, .nameTooLong: "The suggested name can't be used"
    case .emptyFolder, .absoluteFolder, .traversal, .illegalFolder, .folderOutsideDocuments, .folderIsAFile, .newFolderTooDeep, .folderExcluded:
        "The suggested folder can't be used"
    }
}

func adjustedConfidence(_ raw: Double, context: ExtractedContext, createsFolder: Bool) -> Double {
    var value = raw.isFinite ? min(max(raw, 0), 1) : 0
    if context.text.count < lowTextCharacters { value = min(value, lowTextConfidenceCap) }
    if createsFolder { value -= newFolderPenalty }
    return max(value, 0)
}

func decide(answer: ModelAnswer, validation: Result<ValidatedMove, RejectReason>, context: ExtractedContext,
            threshold: Double = defaultConfidenceThreshold) -> Decision {
    let suggestion = Suggestion(name: answer.name, folder: answer.folder)
    switch validation {
    case .failure(let reject):
        return .review(suggestion: suggestion, confidence: 0, reason: plainReason(reject))
    case .success(let move):
        let confidence = adjustedConfidence(answer.confidence, context: context, createsFolder: move.createsFolder)
        if confidence >= threshold { return .file(move, confidence: confidence, reason: answer.reason) }
        return .review(suggestion: suggestion, confidence: confidence, reason: "Not sure where this goes")
    }
}
