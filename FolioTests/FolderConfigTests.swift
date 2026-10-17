import Foundation
import Testing
@testable import Folio

struct FolderConfigTests {
    private let config = FolderConfig(
        watched: [WatchedFolder(path: "/h/Downloads", subfolders: true), WatchedFolder(path: "/h/Desktop", subfolders: false)],
        excluded: ["/h/Downloads/Keep"])

    @Test(arguments: [
        ("/h/Downloads/a.pdf", true),
        ("/h/Downloads/zip/inner/a.pdf", true),          // subfolders on
        ("/h/Desktop/a.pdf", true),
        ("/h/Desktop/sub/a.pdf", false),                 // subfolders off
        ("/h/Downloads/Keep/a.pdf", false),              // excluded
        ("/h/Downloads/Keep/deeper/a.pdf", false),
        ("/h/Downloads/Keeper/a.pdf", true),             // only a name prefix, not inside
        ("/h/Downloads/.cache/a.pdf", false),            // hidden folder
        ("/h/Downloads/proj/node_modules/x/a.js", false),
        ("/h/Downloads/Thing.app/Contents/a.plist", false),
        ("/h/Documents/a.pdf", false),                   // not watched
        ("/h/Downloads", false),                         // the folder itself
    ])
    func shouldWatchTable(path: String, expected: Bool) {
        #expect(shouldWatch(path, config: config) == expected)
    }

    @Test func folderChoicesStayInsideHomeAndOutOfLibrary() {
        let home = URL(fileURLWithPath: "/Users/x")
        #expect(folderChoiceProblem(URL(fileURLWithPath: "/Users/x/Desktop"), home: home) == nil)
        #expect(folderChoiceProblem(URL(fileURLWithPath: "/Users/x/Documents/Work"), home: home) == nil)
        #expect(folderChoiceProblem(URL(fileURLWithPath: "/Users/x"), home: home) != nil)
        #expect(folderChoiceProblem(URL(fileURLWithPath: "/"), home: home) != nil)
        #expect(folderChoiceProblem(URL(fileURLWithPath: "/Applications"), home: home) != nil)
        #expect(folderChoiceProblem(URL(fileURLWithPath: "/Users/x/Library/Mail"), home: home) != nil)
        #expect(folderChoiceProblem(URL(fileURLWithPath: "/Users/x/.ssh"), home: home) != nil)
    }

    @Test func excludedFoldersAreNeverADestinationNorOfferedToTheModel() throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFolder("Finance")
        try sb.makeFolder("Private/Taxes")
        let source = try sb.makeFile("a.pdf")
        var config = FolderConfig.defaults(sb.paths)
        config.excluded = [sb.paths.documents.appendingPathComponent("Private").path]
        #expect(validate(proposal: Proposal(name: "A", folder: "Private/Taxes"), source: source, paths: sb.paths, config: config) == .failure(.folderExcluded))
        #expect(validate(proposal: Proposal(name: "A", folder: "Private"), source: source, paths: sb.paths, config: config) == .failure(.folderExcluded))
        #expect(validate(proposal: Proposal(name: "A", folder: "Finance"), source: source, paths: sb.paths, config: config).isSuccess)
        #expect(listFolders(in: sb.paths.documents, excluding: config.excludedURLs) == ["Finance"])
    }

    @Test func filesFromAnyWatchedFolderAreValidSources() throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFolder("Finance")
        let desktop = sb.root.appendingPathComponent("Desktop", isDirectory: true)
        let file = try sb.makeFile("shot.png", in: desktop)
        var config = FolderConfig.defaults(sb.paths)
        #expect(validate(proposal: Proposal(name: "S", folder: "Finance"), source: file, paths: sb.paths, config: config) == .failure(.sourceOutsideRoots))
        config.watched.append(WatchedFolder(path: desktop.realPath.path, subfolders: true))
        #expect(validate(proposal: Proposal(name: "S", folder: "Finance"), source: file, paths: sb.paths, config: config).isSuccess)
    }

    @Test func storePersistsChanges() throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let store = FolderConfigStore(paths: sb.paths)
        #expect(store.current == .defaults(sb.paths))
        store.update { $0.excluded.append("/x") }
        #expect(FolderConfigStore(paths: sb.paths).current.excluded == ["/x"])
    }

    @Test func aFileFolioMovedIsRecognisedEvenAfterTheUserMovesIt() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFolder("Finance")
        let log = MoveLog(paths: sb.paths)
        let source = try sb.makeFile("a.pdf")
        let record = try await Mover(log: log).perform(validate(proposal: Proposal(name: "A", folder: "Finance"), source: source, paths: sb.paths).get(), kind: .auto)
        let elsewhere = sb.paths.documents.appendingPathComponent("Moved by user.pdf")
        try FileManager.default.moveItem(atPath: record.destination, toPath: elsewhere.path)
        #expect(await log.hasHandled(elsewhere.path))
        let stranger = try sb.makeFile("b.pdf")
        #expect(await !log.hasHandled(stranger.path))
    }
}
