import Foundation
import Testing
@testable import Folio

struct ContextTextTests {
    @Test func normaliseCollapsesStripsAndCaps() {
        #expect(capAndNormalise("  a \n\n\t b\u{1B}[0m \u{0}c  ") == "a b [0m c")
        #expect(capAndNormalise("x", limit: 5) == "x")
        #expect(capAndNormalise(String(repeating: "ab ", count: 3000)).count <= extractionCharLimit)
        #expect(capAndNormalise("abcdefghij", limit: 4) == "abcd")
        #expect(capAndNormalise("   \n\t ") == "")
        #expect(capAndNormalise("e\u{301}\u{202E}x") == "é x")
    }

    @Test(arguments: [
        ("https://shop.example.com/files/invoice.pdf?token=SECRET&id=3#frag", "https://shop.example.com/files/invoice.pdf"),
        ("HTTPS://User:Pass@Example.COM:8443/a/b", "https://example.com/a/b"),
        ("http://example.com", "http://example.com"),
        ("https://example.com/a%20b.pdf", "https://example.com/a%20b.pdf"),
    ])
    func urlKeepsOnlySchemeHostPath(raw: String, expected: String) {
        #expect(sanitiseURL(raw) == expected)
    }

    @Test(arguments: ["file:///Users/x/secret.pdf", "mailto:a@b.com", "data:text/plain,hi", "not a url", "", "https://"])
    func urlRejectsNonWeb(raw: String) {
        #expect(sanitiseURL(raw) == nil)
    }

    @Test func decodeTextHandlesEncodingsAndBinary() {
        #expect(decodeText(Data("héllo".utf8)) == "héllo")
        #expect(decodeText(Data([0xEF, 0xBB, 0xBF]) + Data("bom".utf8)) == "bom")
        #expect(decodeText(Data([0xFF, 0xFE]) + "wide".data(using: .utf16LittleEndian)!) == "wide")
        #expect(decodeText(Data([0xFE, 0xFF]) + "wide".data(using: .utf16BigEndian)!) == "wide")
        #expect(decodeText(Data([0x43, 0x61, 0x66, 0xE9])) == "Café")
        #expect(decodeText(Data([0x89, 0x50, 0x00, 0x01])) == nil)
        // A prefix cut in the middle of a multibyte character still decodes.
        #expect(decodeText(Data("ab会".utf8).dropLast(1), truncated: true) == "ab")
        #expect(decodeText(Data()) == "")
    }
}

struct ExtractionTests {
    private let textExts: Set<String> = ["txt", "md", "markdown", "csv", "json"]

    @Test func everyMarkdownSampleBehavesAsItsManifestSays() throws {
        for sample in try Fixtures.loadMdSamples() where !sample.path.contains("/") && sample.kind != "directory" && sample.kind != "ignored" {
            let ext = sample.url.pathExtension.lowercased()
            let context = Extractor.extractSync(sample.url)
            #expect(context.text.count <= extractionCharLimit, "\(sample.path)")
            #expect(!context.text.unicodeScalars.contains { $0.value < 0x20 }, "\(sample.path) has control characters")
            switch sample.kind {
            case "text" where textExts.contains(ext): #expect(context.hadText, "\(sample.path) should have text")
            case "text": #expect(!context.hadText, "\(sample.path) has no text extension, so metadata only")
            default: #expect(!context.hadText, "\(sample.path) should have no text")
            }
        }
    }

    @Test func specificMarkdownEdgeCases() {
        func text(_ name: String) -> String { Extractor.extractSync(Fixtures.mdSamples.appendingPathComponent(name)).text }
        #expect(text("bom.md").hasPrefix("# Notes with BOM"))
        #expect(text("utf16.md").contains("UTF-16 note"))
        #expect(text("latin1.md").contains("Café"))
        #expect(text("crlf.md") == "# Todo - call the bank - renew passport")
        #expect(text("nul_bytes.md") == "Before after the nul bytes.")
        #expect(text("huge.md").count == extractionCharLimit)
        #expect(text("long_line.md").count == extractionCharLimit)
        #expect(text("multilingual.md").contains("会议记录"))
        #expect(text("injection_instructions.md").contains("Ignore all previous instructions")) // kept as data; the prompt fences it
    }

    @Test func fixtureCorpusYieldsTextWhereExpected() throws {
        let started = Date()
        var timings: [String: TimeInterval] = [:]
        for entry in try Fixtures.loadExpected() {
            let t = Date()
            let context = Extractor.extractSync(Fixtures.url(entry.file))
            timings[entry.file] = Date().timeIntervalSince(t)
            let ext = (entry.file as NSString).pathExtension
            if entry.shouldQueue { #expect(context.text.count < 10, "\(entry.file) should be empty or near-empty") }
            if ext == "pdf" || ext == "png", !entry.file.hasPrefix("photo") { #expect(context.hadText, "\(entry.file) should yield text") }
            if entry.file.hasPrefix("photo") { #expect(!context.hadText, "\(entry.file) is text-free") }
        }
        let pdf = timings["INV-2026-0412.pdf"] ?? 0
        let scan = timings["scan0003.pdf"] ?? 0
        let shot = timings["Screenshot 2026-10-02 at 10.14.33.png"] ?? 0
        print("EXTRACTION TIMING total \(Date().timeIntervalSince(started))s, text PDF \(pdf)s, scanned PDF (OCR) \(scan)s, screenshot (OCR) \(shot)s")
    }

    @Test func specificCorpusContent() {
        #expect(Extractor.extractSync(Fixtures.url("INV-2026-0412.pdf")).text.contains("Cobalt Cloud Hosting"))
        #expect(Extractor.extractSync(Fixtures.url("scan0003.pdf")).text.localizedCaseInsensitiveContains("LAKEVIEW"))
        #expect(Extractor.extractSync(Fixtures.url("error_dialog.png")).text.contains("Connection refused"))
        #expect(!Extractor.extractSync(Fixtures.url("notes.txt")).hadText)
        #expect(!Extractor.extractSync(Fixtures.url("data.bin")).hadText)
    }

    @Test func missingUnreadableAndMetadataOnlyFilesNeverThrow() throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        #expect(!Extractor.extractSync(sb.paths.downloads.appendingPathComponent("gone.pdf")).hadText)
        #expect(!Extractor.extractSync(sb.paths.downloads).hadText) // a directory
        let locked = try sb.makeFile("locked.md", contents: "secret words here")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        #expect(!Extractor.extractSync(locked).hadText)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path)
        let broken = try sb.makeFile("broken.pdf", contents: "%PDF-1.4 not really")
        #expect(!Extractor.extractSync(broken).hadText)
        let zeroImage = try sb.makeFile("zero.png", contents: "")
        #expect(!Extractor.extractSync(zeroImage).hadText)
        let other = try sb.makeFile("archive.zip", contents: "PK")
        let ctx = Extractor.extractSync(other)
        #expect(!ctx.hadText && ctx.contentType != nil && ctx.created != nil)
    }

    @Test func whereFromComesFromQuarantineMetadataAndIsSanitised() throws {
        let sb = try Sandbox()
        defer { sb.cleanUp() }
        let file = try sb.makeFile("download.txt", contents: "hello there")
        let plist = try PropertyListSerialization.data(fromPropertyList: ["https://u:p@files.example.com/a/report.pdf?sig=SECRET", "https://example.com/page"], format: .binary, options: 0)
        let status = plist.withUnsafeBytes { setxattr(file.path, "com.apple.metadata:kMDItemWhereFroms", $0.baseAddress, plist.count, 0, 0) }
        #expect(status == 0)
        #expect(Extractor.extractSync(file).whereFrom == "https://files.example.com/a/report.pdf")
    }
}
