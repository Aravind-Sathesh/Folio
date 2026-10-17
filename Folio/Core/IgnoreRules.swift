import Foundation

private let ignoredExtensions: Set<String> = ["crdownload", "download", "part", "icloud", "localized", "app", "pkg"]

/// True for anything Folio must never process: hidden files (covers .DS_Store and `.name.icloud` placeholders),
/// partial downloads, folders, packages.
func shouldIgnore(path: String, isDirectory: Bool, isPackage: Bool) -> Bool {
    if isDirectory || isPackage { return true }
    let url = URL(fileURLWithPath: path)
    return url.lastPathComponent.hasPrefix(".") || ignoredExtensions.contains(url.pathExtension.lowercased())
}
