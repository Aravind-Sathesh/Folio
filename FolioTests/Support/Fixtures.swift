import Foundation
@testable import Folio

/// Locates `Tests/Fixtures` from this source file, so tests don't depend on bundle resources.
enum Fixtures {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Tests/Fixtures", isDirectory: true)
    static let corpus = root.appendingPathComponent("corpus", isDirectory: true)
    static let documentsTree = root.appendingPathComponent("documents-tree", isDirectory: true)

    static let mdSamples = root.appendingPathComponent("md-samples", isDirectory: true)

    struct MdSample: Decodable, Sendable {
        let path: String
        /// text, empty, binary, ignored or directory
        let kind: String
        let note: String
        var url: URL { Fixtures.mdSamples.appendingPathComponent(path) }
    }

    static func loadMdSamples() throws -> [MdSample] {
        try JSONDecoder().decode([MdSample].self, from: Data(contentsOf: mdSamples.appendingPathComponent("manifest.json")))
    }

    static func url(_ corpusFile: String) -> URL { corpus.appendingPathComponent(corpusFile) }

    static func loadExpected() throws -> [CorpusEntry] {
        try JSONDecoder().decode([CorpusEntry].self, from: Data(contentsOf: root.appendingPathComponent("expected.json")))
    }

    /// Relative folder paths of the fixture Documents tree, sorted.
    static func treeFolders() throws -> [String] {
        let fm = FileManager.default
        let base = documentsTree.realPath.path
        let enumerator = fm.enumerator(at: documentsTree.realPath, includingPropertiesForKeys: [.isDirectoryKey])
        var folders: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                folders.append(String(url.realPath.path.dropFirst(base.count + 1)))
            }
        }
        return folders.sorted()
    }
}

extension Sandbox {
    /// A sandbox shaped like a real setup: the corpus sits in Downloads and the fixture tree is Documents.
    static func withCorpus() throws -> Sandbox {
        let sb = try Sandbox()
        let fm = FileManager.default
        for name in try fm.contentsOfDirectory(atPath: Fixtures.corpus.path) {
            try fm.copyItem(at: Fixtures.url(name), to: sb.paths.downloads.appendingPathComponent(name))
        }
        for name in try fm.contentsOfDirectory(atPath: Fixtures.documentsTree.path) {
            try fm.copyItem(at: Fixtures.documentsTree.appendingPathComponent(name), to: sb.paths.documents.appendingPathComponent(name))
        }
        return sb
    }
}
