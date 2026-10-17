import Foundation
import Testing
@testable import Folio

struct EvalHarnessTests {
    @Test func corpusMatchesGroundTruth() throws {
        let entries = try Fixtures.loadExpected()
        #expect(entries.count == 50)
        let folders = Set(try Fixtures.treeFolders())
        for entry in entries {
            #expect(FileManager.default.fileExists(atPath: Fixtures.url(entry.file).path), "missing \(entry.file)")
            for folder in [entry.folder].compactMap({ $0 }) + (entry.acceptable ?? []) {
                #expect(folders.contains(folder), "\(entry.file) expects unknown folder \(folder)")
            }
        }
    }

    @Test func oracleScoresPerfectly() async throws {
        let entries = try Fixtures.loadExpected()
        let report = await evaluate(entries) { $0.shouldQueue ? .queue : .file(folder: $0.folder ?? "") }
        #expect(report.wrong == 0 && report.queuedUnnecessarily == 0)
        #expect(report.correct + report.queuedCorrectly == 50)
        #expect(report.correctRate == 1)
    }

    @Test func randomClassifierScoresNearZero() async throws {
        let entries = try Fixtures.loadExpected()
        let folders = try Fixtures.treeFolders()
        // Stable pick (String.hashValue is seeded per process): sum of the name bytes.
        let report = await evaluate(entries) { .file(folder: folders[$0.file.utf8.reduce(0) { $0 &+ Int($1) } % folders.count]) }
        #expect(report.correctRate < 0.25)
        #expect(report.queuedCorrectly == 0)
    }
}

struct MdSamplesTests {
    @Test func manifestMatchesDisk() throws {
        let samples = try Fixtures.loadMdSamples()
        #expect(samples.count >= 50)
        for sample in samples {
            var isDir: ObjCBool = false
            #expect(FileManager.default.fileExists(atPath: sample.url.path, isDirectory: &isDir), "missing \(sample.path)")
            #expect(isDir.boolValue == (sample.kind == "directory"), "\(sample.path) directory mismatch")
        }
    }
}
