import Foundation

extension URL {
    /// Symlinks resolved with realpath(3). Unlike `resolvingSymlinksInPath`, it keeps `/private/var`
    /// as is, which is the form FSEvents reports. Missing tail components are kept as given.
    var realPath: URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        if realpath(path, &buffer) != nil { return URL(fileURLWithPath: String(cString: buffer), isDirectory: hasDirectoryPath) }
        let parent = deletingLastPathComponent()
        guard parent.path != path, path != "/" else { return self }
        return parent.realPath.appendingPathComponent(lastPathComponent)
    }
}
