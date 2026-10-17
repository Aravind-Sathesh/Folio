import Foundation

/// The only roots Folio reads or writes. Injected everywhere so tests and manual runs never touch real folders.
struct FolioPaths: Sendable, Equatable {
    let downloads: URL
    let documents: URL
    let support: URL

    /// Creates the three folders under `root` and resolves symlinks so later prefix checks compare like with like.
    static func under(root: URL) throws -> FolioPaths {
        let fm = FileManager.default
        let paths = ["Downloads", "Documents", "Support"].map { root.appendingPathComponent($0, isDirectory: true) }
        for url in paths { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        let resolved = paths.map { $0.realPath }
        return FolioPaths(downloads: resolved[0], documents: resolved[1], support: resolved[2])
    }

    /// Real home folders, or a sandbox when launched with `-FolioRoot <path>`.
    static func fromLaunchArguments() throws -> FolioPaths {
        if let root = UserDefaults.standard.string(forKey: "FolioRoot") {
            return try under(root: URL(fileURLWithPath: root, isDirectory: true))
        }
        return try live
    }

    // The single place that reads the real home directory.
    static var home: URL { FileManager.default.homeDirectoryForCurrentUser.realPath }

    private static var live: FolioPaths {
        get throws {
            let home = Self.home
            let support = home.appendingPathComponent("Library/Application Support/Folio", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            return FolioPaths(
                downloads: home.appendingPathComponent("Downloads", isDirectory: true).realPath,
                documents: home.appendingPathComponent("Documents", isDirectory: true).realPath,
                support: support.realPath)
        }
    }
}
