import Foundation

/// A file in Folio's support folder, so a fresh `-FolioRoot` sandbox has its own first run.
enum OnboardingMarker {
    private static func url(_ paths: FolioPaths) -> URL { paths.support.appendingPathComponent("onboarded") }

    static func isDone(_ paths: FolioPaths) -> Bool { FileManager.default.fileExists(atPath: url(paths).path) }

    static func markDone(_ paths: FolioPaths) {
        try? Data("1".utf8).write(to: url(paths), options: .atomic)
    }
}
