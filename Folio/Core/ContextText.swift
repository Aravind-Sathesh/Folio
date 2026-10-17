import Foundation

let extractionCharLimit = 2_000

/// Controls become spaces, whitespace runs collapse to one space, then the first `limit` characters are kept.
func capAndNormalise(_ text: String, limit: Int = extractionCharLimit) -> String {
    var out = ""
    var lastWasSpace = true // swallows leading whitespace
    for scalar in text.unicodeScalars {
        let blank = scalar.properties.isWhitespace || scalar.properties.generalCategory == .control
            || scalar.properties.generalCategory == .format || scalar == "\u{FFFD}"
        if blank {
            if !lastWasSpace { out.unicodeScalars.append(" ") }
            lastWasSpace = true
        } else {
            out.unicodeScalars.append(scalar)
            lastWasSpace = false
        }
        if out.count >= limit + 1 { break } // one past the limit so trimming below can't undershoot
    }
    return String(out.prefix(limit)).trimmingCharacters(in: .whitespaces)
}

/// Scheme, host and path only (G5): no credentials, port, query or fragment. Non-web URLs are dropped.
func sanitiseURL(_ raw: String) -> String? {
    guard let parts = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
          let host = parts.host?.lowercased(), !host.isEmpty else { return nil }
    return "\(scheme)://\(host)\(parts.percentEncodedPath)"
}

/// Text from the start of a file's bytes, or nil when it is binary. Handles BOMs, UTF-16 and Latin-1 fallback.
/// With `truncated`, `data` is a prefix of a larger file, so a UTF-8 sequence cut at the end is tolerated.
func decodeText(_ data: Data, truncated: Bool = false) -> String? {
    if data.starts(with: [0xEF, 0xBB, 0xBF]) { return decodeText(data.dropFirst(3), truncated: truncated) }
    if data.starts(with: [0xFF, 0xFE]) { return String(data: data.dropFirst(2), encoding: .utf16LittleEndian) }
    if data.starts(with: [0xFE, 0xFF]) { return String(data: data.dropFirst(2), encoding: .utf16BigEndian) }
    for trim in 0...(truncated ? 3 : 0) where data.count > trim {
        if let text = String(data: data.dropLast(trim), encoding: .utf8) { return text }
    }
    if data.contains(0) { return nil } // invalid UTF-8 with NUL bytes is binary, not an old text encoding
    return String(data: data, encoding: .isoLatin1)
}
