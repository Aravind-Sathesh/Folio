import Foundation
import Testing
@testable import Folio

/// Task 23: hostile names and folders thrown at `validate`. Every one must be rejected or end up inside Documents.
struct HostileInputTests {
    private func rig() throws -> (Sandbox, URL) {
        let sb = try Sandbox()
        try sb.makeFolder("Finance/Invoices")
        try sb.makeFolder("Café")
        let outside = sb.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: sb.paths.documents.appendingPathComponent("Escape"), withDestinationURL: outside)
        try FileManager.default.createSymbolicLink(at: sb.paths.documents.appendingPathComponent("Finance/Sneaky"), withDestinationURL: URL(fileURLWithPath: "/etc"))
        return (sb, try sb.makeFile("source.pdf"))
    }

    private static let badNames = [
        "../../../etc/passwd", "..", ".", "a/../b", "a/b", "/etc/passwd", "name\u{0}.pdf", "tab\there", "new\nline", "cr\rline",
        "\u{202E}gnp.exe", "zero\u{200B}width", "family\u{200D}emoji", "\u{FEFF}bom", "line\u{2028}separator", "para\u{2029}separator",
        " ", "", "....", ".hidden", ".DS_Store", "a:b", ":", "name with trailing colon:", ".pdf",
        String(repeating: "a", count: 300), String(repeating: "é", count: 130), String(repeating: "会", count: 100),
    ]

    @Test(arguments: badNames)
    func hostileNamesAreRejected(name: String) throws {
        let (sb, source) = try rig()
        defer { sb.cleanUp() }
        let result = validate(proposal: Proposal(name: name, folder: "Finance"), source: source, paths: sb.paths)
        #expect(!result.isSuccess, "name \(name.debugDescription) should be rejected")
    }

    private static let badFolders = [
        "../../etc", "Finance/../../..", "Finance/./Invoices", "Finance/Invoices/../Receipts", "/etc", "/", "~", "~/Desktop",
        "Escape", "Escape/x", "Finance/Sneaky", "Finance/Sneaky/passwd", "Fin\u{0}ance", "Fin\u{202E}ance", ".git", "Finance/.ssh", "Finance/a:b",
        String(repeating: "a", count: 300), String(repeating: "a/", count: 1000), "Finance/\n", "", " ", "///",
    ]

    @Test(arguments: badFolders)
    func hostileFoldersAreRejected(folder: String) throws {
        let (sb, source) = try rig()
        defer { sb.cleanUp() }
        let result = validate(proposal: Proposal(name: "ok", folder: folder), source: source, paths: sb.paths)
        #expect(!result.isSuccess, "folder \(folder.debugDescription) should be rejected")
    }

    @Test func invisibleCharactersAtTheEdgesAreTrimmedNotKept() throws {
        let (sb, source) = try rig()
        defer { sb.cleanUp() }
        let move = try validate(proposal: Proposal(name: "\u{200B}padded\u{200B}", folder: "Finance"), source: source, paths: sb.paths).get()
        #expect(move.name == "padded.pdf")
    }

    @Test func oddButHarmlessInputsStayInsideDocuments() throws {
        let (sb, source) = try rig()
        defer { sb.cleanUp() }
        for (name, folder) in [("$(rm -rf ~)", "Finance"), ("-rf", "Finance"), ("100% real", "Finance/Invoices"), ("emoji 📄", "Finance"),
                               ("Finance/%2e%2e", "Finance"), ("ok", "Finance/%2e%2e")] where !name.contains("/") {
            let result = validate(proposal: Proposal(name: name, folder: folder), source: source, paths: sb.paths)
            if case .success(let move) = result {
                #expect(isInside(move.destination, sb.paths.documents), "\(name) in \(folder) escaped")
            }
        }
        // Percent-encoding is just letters here: a folder literally called %2e%2e is inside Documents, not a traversal.
        let literal = try validate(proposal: Proposal(name: "ok", folder: "Finance/%2e%2e"), source: source, paths: sb.paths).get()
        #expect(literal.destinationFolder.lastPathComponent == "%2e%2e" && isInside(literal.destination, sb.paths.documents))
    }

    @Test func nameLengthBoundaryIsExactly255Bytes() throws {
        let (sb, source) = try rig()
        defer { sb.cleanUp() }
        let fits = String(repeating: "a", count: 251) // + ".pdf" = 255
        let tooLong = String(repeating: "a", count: 252)
        #expect(validate(proposal: Proposal(name: fits, folder: "Finance"), source: source, paths: sb.paths).isSuccess)
        #expect(validate(proposal: Proposal(name: tooLong, folder: "Finance"), source: source, paths: sb.paths) == .failure(.nameTooLong))
    }

    @Test func unicodeNormalisationDoesNotCreateALookalikeFolder() throws {
        let (sb, source) = try rig()
        defer { sb.cleanUp() }
        let decomposed = "Cafe\u{301}" // the folder on disk was made with the precomposed spelling
        let move = try validate(proposal: Proposal(name: "ok", folder: decomposed), source: source, paths: sb.paths).get()
        #expect(!move.createsFolder, "APFS treats both spellings as one folder, so Folio must not plan a second one")
    }

    @Test func caseOnlyCollisionNeverOverwrites() async throws {
        let (sb, source) = try rig()
        defer { sb.cleanUp() }
        let existing = try sb.makeFile("Report.pdf", in: sb.paths.documents.appendingPathComponent("Finance"), contents: "precious")
        let move = try validate(proposal: Proposal(name: "report", folder: "Finance"), source: source, paths: sb.paths).get()
        let record = try await Mover(log: MoveLog(paths: sb.paths)).perform(move, kind: .auto)
        #expect(try String(contentsOf: existing, encoding: .utf8) == "precious")
        #expect(record.newName == "report (2).pdf")
    }

    @Test func aSymlinkInDownloadsIsMovedAsALinkNotFollowed() async throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        try sb.makeFolder("Finance")
        let victim = try sb.makeFile("victim.txt", in: sb.root.appendingPathComponent("outside"), contents: "untouched")
        let link = sb.paths.downloads.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        let move = try validate(proposal: Proposal(name: "Moved Link", folder: "Finance"), source: link, paths: sb.paths).get()
        _ = try await Mover(log: MoveLog(paths: sb.paths)).perform(move, kind: .auto)
        #expect(try String(contentsOf: victim, encoding: .utf8) == "untouched")
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }
}
