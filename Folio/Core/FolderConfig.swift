import Foundation

struct WatchedFolder: Codable, Sendable, Equatable, Identifiable {
    let path: String
    var subfolders: Bool
    var id: String { path }
}

/// Which folders Folio reads new files from, and which it must never touch. Files are still only ever filed into Documents.
struct FolderConfig: Codable, Sendable, Equatable {
    var watched: [WatchedFolder]
    var excluded: [String]

    static func defaults(_ paths: FolioPaths) -> FolderConfig {
        FolderConfig(watched: [WatchedFolder(path: paths.downloads.path, subfolders: true), WatchedFolder(path: paths.documents.path, subfolders: true)],
                     excluded: [])
    }

    var watchedURLs: [URL] { watched.map { URL(fileURLWithPath: $0.path, isDirectory: true) } }
    var excludedURLs: [URL] { excluded.map { URL(fileURLWithPath: $0, isDirectory: true) } }

    func isExcluded(_ url: URL) -> Bool {
        excludedURLs.contains { isInside(url, $0) || url.standardizedFileURL.path == $0.standardizedFileURL.path }
    }
}

private let skippedFolderNames: Set<String> = ["node_modules", "Library", "__MACOSX", "Pods", "venv", "DerivedData"]
private let packageExtensions: Set<String> = ["app", "pkg", "bundle", "framework", "photoslibrary", "musiclibrary", "xcodeproj", "xcworkspace"]

/// True when a file path is one Folio should consider: under a watched folder (directly, or deeper when that folder
/// includes subfolders), not excluded, and not inside a hidden folder, a package or a dependency folder.
func shouldWatch(_ path: String, config: FolderConfig) -> Bool {
    let url = URL(fileURLWithPath: path)
    guard !config.isExcluded(url) else { return false }
    for root in config.watched {
        let rootURL = URL(fileURLWithPath: root.path, isDirectory: true)
        guard isInside(url, rootURL) else { continue }
        let between = Array(url.pathComponents.dropFirst(rootURL.pathComponents.count).dropLast())
        if between.isEmpty { return true }
        guard root.subfolders else { continue }
        let blocked = between.contains { $0.hasPrefix(".") || skippedFolderNames.contains($0) || packageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        if !blocked { return true }
    }
    return false
}

/// Why a folder the user picked can't be watched or restructured, or nil if it's fine.
func folderChoiceProblem(_ url: URL, home: URL) -> String? {
    let path = url.standardizedFileURL.path
    if !(isInside(url, home) || path == home.standardizedFileURL.path) { return "Pick a folder inside your home folder." }
    if path == home.standardizedFileURL.path { return "Pick a specific folder, not your whole home folder." }
    if isInside(url, home.appendingPathComponent("Library")) || path == home.appendingPathComponent("Library").path { return "Folio stays out of Library." }
    if url.pathComponents.contains(where: { $0.hasPrefix(".") }) { return "Folio stays out of hidden folders." }
    return nil
}
