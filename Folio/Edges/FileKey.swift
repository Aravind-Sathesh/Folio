import Foundation

/// A file's volume and inode. Unlike a path it survives a rename or move on the same volume, and `fsgetpath` turns it back into a path.
struct FileKey: Codable, Sendable, Hashable {
    let fsid0: Int32
    let fsid1: Int32
    let fileID: UInt64

    init?(path: String) {
        var info = stat()
        var volume = statfs()
        guard lstat(path, &info) == 0, statfs(path, &volume) == 0 else { return nil }
        fsid0 = volume.f_fsid.val.0
        fsid1 = volume.f_fsid.val.1
        fileID = info.st_ino
    }

    /// Where the file is now, or nil if it was deleted or can't be resolved.
    var currentPath: String? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        var volume = fsid_t(val: (fsid0, fsid1))
        guard fsgetpath(&buffer, buffer.count, &volume, fileID) >= 0 else { return nil }
        return String(cString: buffer)
    }
}
