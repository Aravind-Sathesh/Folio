import Foundation

/// `folders.json` in Folio's support folder: watched and excluded folders. Read from any thread, so it is lock-protected.
final class FolderConfigStore: @unchecked Sendable {
    private let lock = NSLock()
    private let url: URL
    private var value: FolderConfig

    init(paths: FolioPaths) {
        url = paths.support.appendingPathComponent("folders.json")
        value = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(FolderConfig.self, from: $0) } ?? .defaults(paths)
    }

    var current: FolderConfig {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func update(_ change: (inout FolderConfig) -> Void) {
        lock.lock()
        change(&value)
        let snapshot = value
        lock.unlock()
        try? JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
    }
}
