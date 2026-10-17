import CryptoKit
import Foundation

private let noiseFolderNames: Set<String> = ["node_modules", "Library", "__MACOSX", "Pods", "venv", "DerivedData"]
private let hashBytes = 10 * 1024 * 1024

/// Read-only walk of Documents. Nothing here changes the filesystem.
struct RestructureScanner: Sendable {
    let paths: FolioPaths

    /// The newest files under Documents, skipping hidden files, packages, symlinks, partial downloads and anything `isBusy`.
    func candidates(cap: Int = restructureFileCap, excluded: [URL] = [], isBusy: (String) -> Bool = { _ in false }) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey]
        guard let walker = FileManager.default.enumerator(at: paths.documents, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [(url: URL, modified: Date)] = []
        while let url = walker.nextObject() as? URL {
            let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: Set(keys))
            if values?.isSymbolicLink == true { walker.skipDescendants(); continue } // never follow a link out of Documents
            if values?.isDirectory == true {
                if noiseFolderNames.contains(url.lastPathComponent) || excluded.contains(where: { $0.path == url.path || isInside(url, $0) }) { walker.skipDescendants() }
                continue
            }
            guard values?.isRegularFile == true, !shouldIgnore(path: url.path, isDirectory: false, isPackage: values?.isPackage ?? false),
                  !isBusy(url.path), isInside(url.realPath, paths.documents) else { continue }
            found.append((url, values?.contentModificationDate ?? .distantPast))
        }
        return selectFiles(found, cap: cap)
    }

    /// SHA-256 of the first 10 MB (G12), or nil if the file can't be read.
    static func contentHash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url), let data = try? handle.read(upToCount: hashBytes) else { return nil }
        try? handle.close()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
