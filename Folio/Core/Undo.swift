import Foundation

enum UndoSelection: Sendable, Equatable {
    case last
    case lastN(Int)
    case since(Date)
    case session(UUID)
}

/// The log minus intents that never happened: a `.failed` entry cancels the matching record right before it,
/// whatever its kind (a crash between "log" and "move" leaves such an intent, and so does a move that throws).
func effectiveRecords(_ records: [MoveRecord]) -> [MoveRecord] {
    var out: [MoveRecord] = []
    for record in records {
        if record.kind == .failed {
            if let i = out.lastIndex(where: { $0.source == record.source && $0.destination == record.destination }) { out.remove(at: i) }
        } else {
            out.append(record)
        }
    }
    return out
}

/// Moves that still stand: filings minus those that failed or were already undone.
func activeMoves(_ records: [MoveRecord]) -> [MoveRecord] {
    var active: [MoveRecord] = []
    for record in effectiveRecords(records) {
        switch record.kind {
        case .auto, .review, .restructure: active.append(record)
        case .undo: active.removeAll { $0.id == record.undoes }
        case .failed: break
        }
    }
    return active
}

/// Records to reverse, newest first, so each file goes back before the one filed ahead of it.
func undoPlan(records: [MoveRecord], selection: UndoSelection) -> [MoveRecord] {
    let active = activeMoves(records)
    let chosen: [MoveRecord]
    switch selection {
    case .last: chosen = Array(active.suffix(1))
    case .lastN(let n): chosen = Array(active.suffix(max(0, n)))
    case .since(let date): chosen = active.filter { $0.timestamp >= date }
    case .session(let id): chosen = active.filter { $0.sessionID == id }
    }
    return chosen.reversed()
}
