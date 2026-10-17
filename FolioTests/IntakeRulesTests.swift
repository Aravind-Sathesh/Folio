import Foundation
import Testing
@testable import Folio

struct IgnoreRulesTests {
    @Test(arguments: [
        ("/d/.hidden.md", false, false, true),
        ("/d/.DS_Store", false, false, true),
        ("/d/.report.pdf.icloud", false, false, true),
        ("/d/report.pdf.icloud", false, false, true),
        ("/d/file.crdownload", false, false, true),
        ("/d/FILE.CRDOWNLOAD", false, false, true),
        ("/d/file.download", false, false, true),
        ("/d/file.part", false, false, true),
        ("/d/Thing.app", false, false, true),
        ("/d/installer.pkg", false, false, true),
        ("/d/Folder", true, false, true),
        ("/d/folder.md", true, false, true),
        ("/d/Bundle.numbers", false, true, true),
        ("/d/a.localized", false, false, true),
        ("/d/report.pdf", false, false, false),
        ("/d/notes.md", false, false, false),
        ("/d/README", false, false, false),
        ("/d/part.pdf", false, false, false),
    ])
    func table(path: String, isDirectory: Bool, isPackage: Bool, ignored: Bool) {
        #expect(shouldIgnore(path: path, isDirectory: isDirectory, isPackage: isPackage) == ignored)
    }

    @Test func agreesWithMarkdownSampleManifest() throws {
        for sample in try Fixtures.loadMdSamples() where !sample.path.contains("/") {
            let expectedIgnored = sample.kind == "ignored" || sample.kind == "directory"
            let isDir = sample.kind == "directory"
            #expect(shouldIgnore(path: sample.url.path, isDirectory: isDir, isPackage: false) == expectedIgnored, "\(sample.path)")
        }
    }
}

struct SettleTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private func obs(_ s: TimeInterval, size: Int64, mtime: TimeInterval = 0) -> FileSighting {
        FileSighting(date: t0.addingTimeInterval(s), size: size, mtime: t0.addingTimeInterval(mtime))
    }

    @Test func growingThenStableThenReady() {
        var seen = [obs(0, size: 10, mtime: 0)]
        #expect(settleDecision(seen, now: t0, quiet: 60) == .wait(until: t0.addingTimeInterval(60)))
        seen.append(obs(5, size: 500, mtime: 5)) // still growing: clock restarts
        #expect(settleDecision(seen, now: t0.addingTimeInterval(5), quiet: 60) == .wait(until: t0.addingTimeInterval(65)))
        seen.append(obs(10, size: 900, mtime: 10)) // stable from t=10
        seen.append(obs(15, size: 900, mtime: 10))
        seen.append(obs(40, size: 900, mtime: 10))
        #expect(settleDecision(seen, now: t0.addingTimeInterval(69), quiet: 60) == .wait(until: t0.addingTimeInterval(70)))
        #expect(settleDecision(seen, now: t0.addingTimeInterval(70), quiet: 60) == .ready)
    }

    @Test func sameSizeButNewMtimeRestartsClock() {
        let seen = [obs(0, size: 10, mtime: 0), obs(30, size: 10, mtime: 29)]
        #expect(settleDecision(seen, now: t0.addingTimeInterval(61), quiet: 60) == .wait(until: t0.addingTimeInterval(90)))
    }

    @Test func nothingObservedIsDropped() {
        #expect(settleDecision([], now: t0) == .drop)
    }
}

struct FileIdentityTests {
    @Test func processedIdentitySkippedEditedOneIsNot() {
        let mtime = Date(timeIntervalSince1970: 1_700_000_000.1234)
        let id = FileIdentity(resourceID: "abc", size: 10, mtime: mtime)
        #expect(!shouldProcess(id, processed: [id]))
        #expect(shouldProcess(FileIdentity(resourceID: "abc", size: 11, mtime: mtime), processed: [id]))
        #expect(shouldProcess(FileIdentity(resourceID: "abc", size: 10, mtime: mtime.addingTimeInterval(1)), processed: [id]))
        #expect(shouldProcess(id, processed: []))
    }

    @Test func survivesJSONRoundTrip() throws {
        let id = FileIdentity(resourceID: "abc", size: 10, mtime: Date(timeIntervalSince1970: 1_700_000_000.1234567))
        let back = try JSONDecoder().decode(FileIdentity.self, from: JSONEncoder().encode(id))
        #expect(back == id)
    }
}
