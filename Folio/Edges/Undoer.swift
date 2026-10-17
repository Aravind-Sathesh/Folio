import Foundation

struct UndoReport: Sendable {
    enum Skip: Sendable, Equatable { case fileGone, folderGone, outsideRoots, failed(String) }
    var restored: [MoveRecord] = []
    var skipped: [(record: MoveRecord, reason: Skip)] = []
}

/// Replays a plan through the same `Mover` path, logging each undo before it happens.
/// The restored file lands in the log as a destination, so the watcher treats it as Folio's own move (G1).
struct Undoer: Sendable {
    let mover: Mover
    let paths: FolioPaths
    /// Other watched folders a file may have come from.
    var extraRoots: @Sendable () -> [URL] = { [] }

    func run(_ plan: [MoveRecord]) async -> UndoReport {
        var report = UndoReport()
        let fm = FileManager.default
        for record in plan {
            let current = URL(fileURLWithPath: record.destination)
            let originalFolder = URL(fileURLWithPath: record.source).deletingLastPathComponent()
            guard fm.fileExists(atPath: current.path) else { report.skipped.append((record, .fileGone)); continue }
            guard isInsideRoots(current), isInsideRoots(originalFolder) || isRoot(originalFolder) else {
                report.skipped.append((record, .outsideRoots))
                continue
            }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: originalFolder.path, isDirectory: &isDir), isDir.boolValue else {
                report.skipped.append((record, .folderGone))
                continue
            }
            let move = ValidatedMove(source: current, destinationFolder: originalFolder, name: record.originalName, createsFolder: false)
            do {
                try await mover.perform(move, kind: .undo, undoes: record.id)
                report.restored.append(record)
            } catch {
                report.skipped.append((record, .failed(String(describing: error))))
            }
        }
        return report
    }

    private func isRoot(_ url: URL) -> Bool {
        let u = url.standardizedFileURL
        return ([paths.downloads, paths.documents] + extraRoots()).contains { u == $0.standardizedFileURL }
    }

    private func isInsideRoots(_ url: URL) -> Bool {
        ([paths.downloads, paths.documents] + extraRoots()).contains { isInside(url, $0) }
    }
}
