import Foundation

let folderTreeMaxDepth = 3
let folderTreeCap = 300
private let noiseFolders: Set<String> = ["node_modules", "Library", "__MACOSX", "Pods", "venv", "DerivedData"]

/// Folders under `documents` as relative paths ("Finance/Invoices"), up to `maxDepth` levels, at most `cap`.
/// Breadth-first, so when the cap bites it is the deepest folders that drop out. Result is sorted for a stable prompt.
func listFolders(in documents: URL, maxDepth: Int = folderTreeMaxDepth, cap: Int = folderTreeCap, excluding excluded: [URL] = []) -> [String] {
    let fm = FileManager.default
    let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey]
    var found: [String] = []
    var level: [(url: URL, relative: String)] = [(documents, "")]
    for _ in 0..<maxDepth {
        var next: [(URL, String)] = []
        for (dir, relative) in level {
            let entries = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
            for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let values = try? URL(fileURLWithPath: entry.path).resourceValues(forKeys: Set(keys))
                // Symlinks are skipped so the tree can never lead outside Documents.
                guard values?.isDirectory == true, values?.isPackage != true, values?.isSymbolicLink != true,
                      !noiseFolders.contains(entry.lastPathComponent),
                      !excluded.contains(where: { isInside(entry, $0) || entry.path == $0.path }) else { continue }
                if found.count >= cap { return sortedForPrompt(found) }
                let path = relative.isEmpty ? entry.lastPathComponent : relative + "/" + entry.lastPathComponent
                found.append(path)
                next.append((entry, path))
            }
        }
        level = next
    }
    return sortedForPrompt(found)
}

private func sortedForPrompt(_ folders: [String]) -> [String] {
    folders.sorted { ($0.lowercased(), $0) < ($1.lowercased(), $1) }
}
