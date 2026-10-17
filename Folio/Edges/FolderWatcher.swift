import CoreServices
import Foundation

/// FSEvents on the watched folders (and their subfolders when chosen). Emits candidate file paths; deciding what to do with them is the queue's job.
enum FolderWatcher {
    private final class Box: @unchecked Sendable {
        let continuation: AsyncStream<URL>.Continuation
        let config: FolderConfig
        init(_ continuation: AsyncStream<URL>.Continuation, config: FolderConfig) {
            self.continuation = continuation
            self.config = config
        }

        func handle(path: String, flags: UInt32) {
            let url = URL(fileURLWithPath: path)
            guard shouldWatch(path, config: config) else { return }
            guard flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0 else { return }
            let changed = UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified
                | kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemInodeMetaMod)
            if flags & changed != 0 { continuation.yield(url) }
        }
    }

    private struct StreamRef: @unchecked Sendable { let stream: FSEventStreamRef }

    /// Events from now on (G2): files already there when Folio starts are not reported.
    static func events(config: FolderConfig, latency: TimeInterval = 0.5) -> AsyncStream<URL> {
        let roots = config.watchedURLs
        return AsyncStream { continuation in
            let box = Box(continuation, config: config)
            var context = FSEventStreamContext(
                version: 0, info: Unmanaged.passRetained(box).toOpaque(), retain: nil,
                release: { info in if let info { Unmanaged<Box>.fromOpaque(info).release() } }, copyDescription: nil)
            let callback: FSEventStreamCallback = { _, info, count, eventPaths, eventFlags, _ in
                guard let info, let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] else { return }
                let box = Unmanaged<Box>.fromOpaque(info).takeUnretainedValue()
                for i in 0..<count { box.handle(path: paths[i], flags: eventFlags[i]) }
            }
            let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagNoDefer)
            guard let stream = FSEventStreamCreate(nil, callback, &context, roots.map(\.path) as CFArray,
                                                   FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else {
                Unmanaged.passUnretained(box).release() // balance passRetained: the stream never took ownership
                continuation.finish()
                return
            }
            let ref = StreamRef(stream: stream)
            FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "folio.fsevents", qos: .utility))
            FSEventStreamStart(stream)
            continuation.onTermination = { _ in
                FSEventStreamStop(ref.stream)
                FSEventStreamInvalidate(ref.stream)
                FSEventStreamRelease(ref.stream) // also releases `box` through the context's release callback
            }
        }
    }
}
