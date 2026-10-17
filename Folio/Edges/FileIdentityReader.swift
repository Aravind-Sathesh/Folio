import Foundation

/// Reads the (resource id, size, mtime) triple used to recognise a file Folio has already handled.
func fileIdentity(of url: URL) -> FileIdentity? {
    let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .fileSizeKey, .contentModificationDateKey]
    guard let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: keys), // fresh URL: no cached values
          let identifier = values.fileResourceIdentifier, let size = values.fileSize, let mtime = values.contentModificationDate,
          let archived = try? NSKeyedArchiver.archivedData(withRootObject: identifier, requiringSecureCoding: true) else { return nil }
    return FileIdentity(resourceID: archived.base64EncodedString(), size: Int64(size), mtime: mtime)
}
