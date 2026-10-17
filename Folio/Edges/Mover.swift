import Foundation

enum MoverError: Error, Equatable {
    case sourceMissing
    case alreadyThere
    case failed(String)
}

/// The only code that moves user files. Order is fixed: pick a free name, log, then move.
struct Mover: Sendable {
    let log: MoveLog
    /// Injected so tests can prove the log line exists even when the move throws.
    var moveItem: @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) }

    @discardableResult
    func perform(_ move: ValidatedMove, kind: MoveRecord.Kind, confidence: Double? = nil, reason: String? = nil,
                 sessionID: UUID? = nil, undoes: UUID? = nil) async throws -> MoveRecord {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: move.source.path, isDirectory: &isDir), !isDir.boolValue else { throw MoverError.sourceMissing }
        if move.destination.standardizedFileURL == move.source.standardizedFileURL { throw MoverError.alreadyThere }

        // Create-only, one level at a time, parents first: validate() already proved each lies inside Documents.
        for folder in move.foldersToCreate where !fm.fileExists(atPath: folder.path) {
            do { try fm.createDirectory(at: folder, withIntermediateDirectories: false) } catch {
                throw MoverError.failed(error.localizedDescription)
            }
        }
        let destination = uniqueDestination(base: move.destinationFolder, name: move.name) {
            (try? fm.attributesOfItem(atPath: $0.path)) != nil
        }
        let record = MoveRecord(sessionID: sessionID, source: move.source.path, destination: destination.path,
                                confidence: confidence, reason: reason, kind: kind, undoes: undoes,
                                fileKey: FileKey(path: move.source.path))
        do { try await log.append(record) } catch { throw MoverError.failed("could not write move log") }

        do {
            try moveItem(move.source, destination)
        } catch {
            let note = "move failed: \(error.localizedDescription)"
            try? await log.append(MoveRecord(sessionID: sessionID, source: move.source.path, destination: destination.path,
                                             reason: note, kind: .failed))
            throw MoverError.failed(error.localizedDescription)
        }
        return record
    }
}
