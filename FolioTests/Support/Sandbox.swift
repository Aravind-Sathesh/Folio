import Foundation
@testable import Folio

/// A throwaway FolioRoot for tests. Real folders are never used.
struct Sandbox {
    let root: URL
    let paths: FolioPaths

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("folio-test-\(UUID().uuidString)")
        paths = try FolioPaths.under(root: root)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: root) }

    @discardableResult
    func makeFile(_ name: String, in dir: URL? = nil, contents: String = "data") throws -> URL {
        let url = (dir ?? paths.downloads).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @discardableResult
    func makeFolder(_ relative: String) throws -> URL {
        let url = paths.documents.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
