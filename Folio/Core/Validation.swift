import Foundation

/// What the model (or the user, in an edit) asks for. `folder` is relative to Documents.
struct Proposal: Sendable, Equatable {
    let name: String
    let folder: String
}

struct ValidatedMove: Sendable, Equatable {
    let source: URL
    let destinationFolder: URL
    let name: String
    /// Folders that don't exist yet, parents first. Autonomous moves create at most one; a restructure plan may chain.
    let foldersToCreate: [URL]

    var createsFolder: Bool { !foldersToCreate.isEmpty }
    var destination: URL { destinationFolder.appendingPathComponent(name) }

    init(source: URL, destinationFolder: URL, name: String, foldersToCreate: [URL]) {
        self.source = source
        self.destinationFolder = destinationFolder
        self.name = name
        self.foldersToCreate = foldersToCreate
    }

    init(source: URL, destinationFolder: URL, name: String, createsFolder: Bool) {
        self.init(source: source, destinationFolder: destinationFolder, name: name, foldersToCreate: createsFolder ? [destinationFolder] : [])
    }
}

enum RejectReason: Error, Equatable, Sendable {
    case sourceOutsideRoots
    case emptyName, illegalName, nameTooLong
    case emptyFolder, absoluteFolder, traversal, illegalFolder
    case folderOutsideDocuments, folderIsAFile, newFolderTooDeep, folderExcluded
}

private let maxNameBytes = 255

/// True when `child` is strictly below `parent`, compared by path components (not string prefix).
/// Dot components are resolved lexically; `standardizedFileURL` is avoided because it rewrites /private/var only for paths that exist.
func isInside(_ child: URL, _ parent: URL) -> Bool {
    func components(_ url: URL) -> [String] {
        var out: [String] = []
        for part in url.pathComponents where part != "/" && part != "." {
            if part == ".." { _ = out.popLast() } else { out.append(part) }
        }
        return out
    }
    let c = components(child), p = components(parent)
    return c.count > p.count && Array(c.prefix(p.count)) == p
}

private func hasIllegalCharacters(_ text: String) -> Bool {
    text.unicodeScalars.contains { scalar in
        switch scalar.properties.generalCategory {
        case .control, .format, .lineSeparator, .paragraphSeparator: true
        default: scalar == "/" || scalar == ":"
        }
    }
}

/// A proposed extension we are willing to replace: short, has a letter, no punctuation ("docx" yes, "2026-10" or "2" no).
private func looksLikeExtension(_ ext: String) -> Bool {
    (1...5).contains(ext.count) && ext.allSatisfy { $0.isLetter || $0.isNumber } && ext.contains { $0.isLetter }
}

/// Cleans a model-proposed file name: trims, rejects anything unsafe, and forces the original extension.
func sanitizedName(_ proposed: String, originalExtension: String) -> Result<String, RejectReason> {
    var name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty { return .failure(.emptyName) }
    if hasIllegalCharacters(name) || name.hasPrefix(".") { return .failure(.illegalName) }
    while name.hasSuffix(".") { name.removeLast() }

    if !originalExtension.isEmpty {
        let ext = (name as NSString).pathExtension
        if ext.lowercased() == originalExtension.lowercased() {
            name = (name as NSString).deletingPathExtension + "." + originalExtension
        } else {
            if looksLikeExtension(ext) { name = (name as NSString).deletingPathExtension }
            name += "." + originalExtension
        }
    }
    name = name.trimmingCharacters(in: .whitespaces)
    if (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces).isEmpty || name.hasSuffix(".") {
        return .failure(.illegalName)
    }
    if name.utf8.count > maxNameBytes { return .failure(.nameTooLong) }
    return .success(name)
}

private func sanitizedFolderComponents(_ folder: String) -> Result<[String], RejectReason> {
    if folder.hasPrefix("/") || folder.hasPrefix("~") { return .failure(.absoluteFolder) }
    let parts = folder.split(separator: "/", omittingEmptySubsequences: true).map {
        String($0).trimmingCharacters(in: .whitespaces)
    }.filter { !$0.isEmpty }
    if parts.isEmpty { return .failure(.emptyFolder) }
    if parts.contains(where: { $0 == ".." || $0 == "." }) { return .failure(.traversal) }
    for part in parts where part.hasPrefix(".") || hasIllegalCharacters(part) || part.utf8.count > maxNameBytes {
        return .failure(.illegalFolder)
    }
    return .success(parts)
}

/// All AGENTS.md checks for one move, with filesystem reads only (existence and symlink resolution).
/// `virtualFolders` are folders a restructure plan has already proposed (relative paths): they count as existing
/// for the "one new level" rule, but still end up in `foldersToCreate`.
/// With `config`, sources may come from any watched folder and destinations must avoid excluded folders.
func validate(proposal: Proposal, source: URL, paths: FolioPaths, virtualFolders: Set<String> = [], config: FolderConfig? = nil) -> Result<ValidatedMove, RejectReason> {
    // Resolve the parent, not the file, so a symlink *in* Downloads is moved as a link, not followed out.
    let resolvedParent = source.deletingLastPathComponent().realPath
    let resolvedSource = resolvedParent.appendingPathComponent(source.lastPathComponent)
    let sourceRoots = [paths.downloads, paths.documents] + (config?.watchedURLs ?? [])
    guard sourceRoots.contains(where: { isInside(resolvedSource, $0) }) else { return .failure(.sourceOutsideRoots) }

    let name: String
    switch sanitizedName(proposal.name, originalExtension: source.pathExtension) {
    case .success(let value): name = value
    case .failure(let reason): return .failure(reason)
    }

    let components: [String]
    switch sanitizedFolderComponents(proposal.folder) {
    case .success(let value): components = value
    case .failure(let reason): return .failure(reason)
    }

    let fm = FileManager.default
    var current = paths.documents
    var relative = ""
    var toCreate: [URL] = []
    var unknown = 0 // components that are neither on disk nor already planned
    for part in components {
        let next = current.appendingPathComponent(part, isDirectory: true)
        relative = relative.isEmpty ? part : relative + "/" + part
        if toCreate.isEmpty {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: next.path, isDirectory: &isDir) {
                if !isDir.boolValue { return .failure(.folderIsAFile) }
                // Symlinked folder that leads outside Documents.
                guard isInside(next.realPath, paths.documents) else { return .failure(.folderOutsideDocuments) }
            } else {
                toCreate.append(next)
                if !virtualFolders.contains(relative) { unknown += 1 }
            }
        } else {
            toCreate.append(next)
            if !virtualFolders.contains(relative) { unknown += 1 }
        }
        current = next
    }
    if unknown > 1 { return .failure(.newFolderTooDeep) }
    guard isInside(current, paths.documents) else { return .failure(.folderOutsideDocuments) }
    if config?.isExcluded(current) == true { return .failure(.folderExcluded) }
    return .success(ValidatedMove(source: resolvedSource, destinationFolder: current, name: name, foldersToCreate: toCreate))
}

/// `name`, or `stem (2).ext`, `stem (3).ext`... until `exists` says the path is free.
func uniqueDestination(base: URL, name: String, exists: (URL) -> Bool) -> URL {
    let first = base.appendingPathComponent(name)
    if !exists(first) { return first }
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    for n in 2...10_000 {
        let candidate = base.appendingPathComponent(ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)")
        if !exists(candidate) { return candidate }
    }
    // Practically unreachable; a UUID still never overwrites.
    return base.appendingPathComponent(ext.isEmpty ? "\(stem) (\(UUID().uuidString))" : "\(stem) (\(UUID().uuidString)).\(ext)")
}
