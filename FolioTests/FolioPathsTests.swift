import Foundation
import Testing
@testable import Folio

struct FolioPathsTests {
    @Test func underRootCreatesThreeFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = try FolioPaths.under(root: root)
        for url in [paths.downloads, paths.documents, paths.support] {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
        }
        #expect(paths.downloads.lastPathComponent == "Downloads")
        #expect(paths.documents.lastPathComponent == "Documents")
        #expect(paths.support.lastPathComponent == "Support")
    }
}
