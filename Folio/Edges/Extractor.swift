import AppKit
import Foundation
import PDFKit
import Vision

struct ExtractedContext: Sendable, Equatable {
    var text = ""
    var whereFrom: String?
    var contentType: String?
    var created: Date?
    var hadText: Bool { !text.isEmpty }
}

private let maxExtractBytes: Int64 = 200_000_000
private let textReadBytes = 64 * 1024
private let ocrFallbackMinChars = 50
private let textExtensions: Set<String> = ["txt", "md", "markdown", "csv", "json"]
private let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp", "webp"]

/// Reads a file's text and Spotlight metadata. Read-only; failures become "no text", never an error. Nothing is logged.
struct Extractor: Sendable {
    func extract(_ url: URL) async -> ExtractedContext {
        // Vision and PDFKit block, so keep them off the caller's actor.
        await Task.detached(priority: .utility) { Self.extractSync(url) }.value
    }

    static func extractSync(_ url: URL) -> ExtractedContext {
        var context = metadata(of: url)
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true, Int64(values?.fileSize ?? 0) <= maxExtractBytes else { return context }
        let ext = url.pathExtension.lowercased()
        let raw: String
        if ext == "pdf" { raw = pdfText(url) }
        else if ext == "rtf" { raw = rtfText(url) }
        else if textExtensions.contains(ext) { raw = plainText(url) }
        else if imageExtensions.contains(ext) { raw = loadImage(url).map(ocr) ?? "" }
        else { raw = "" }
        context.text = capAndNormalise(raw)
        return context
    }

    // MARK: metadata

    private static func metadata(of url: URL) -> ExtractedContext {
        var context = ExtractedContext()
        let values = try? url.resourceValues(forKeys: [.contentTypeKey, .creationDateKey])
        context.contentType = values?.contentType?.identifier
        context.created = values?.creationDate
        context.whereFrom = whereFroms(of: url).lazy.compactMap(sanitiseURL).first
        return context
    }

    // The xattr is what Spotlight's kMDItemWhereFroms reads, but it works before the file is indexed (MDItem returns nil then).
    private static func whereFroms(of url: URL) -> [String] {
        let name = "com.apple.metadata:kMDItemWhereFroms"
        let size = getxattr(url.path, name, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard getxattr(url.path, name, &buffer, size, 0, 0) == size,
              let list = try? PropertyListSerialization.propertyList(from: Data(buffer), format: nil) as? [String] else { return [] }
        return list
    }

    // MARK: text sources

    private static func plainText(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: textReadBytes) else { return "" }
        return decodeText(data, truncated: data.count == textReadBytes) ?? ""
    }

    private static func rtfText(_ url: URL) -> String {
        guard (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 < 5_000_000,
              let text = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        else { return "" }
        return text.string
    }

    private static func pdfText(_ url: URL) -> String {
        guard let doc = PDFDocument(url: url), !doc.isLocked, doc.pageCount > 0 else { return "" }
        var text = ""
        for i in 0..<min(doc.pageCount, 5) {
            text += " " + (doc.page(at: i)?.string ?? "")
            if capAndNormalise(text).count >= extractionCharLimit { break }
        }
        if capAndNormalise(text).count >= ocrFallbackMinChars { return text }
        // Scanned PDF: no text layer, so read what the first pages look like.
        return (0..<min(doc.pageCount, 2)).compactMap { doc.page(at: $0).flatMap(render) }.map(ocr).joined(separator: " ")
    }

    // MARK: images and OCR

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 3000]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func render(_ page: PDFPage) -> CGImage? {
        guard let ref = page.pageRef else { return nil }
        let box = ref.getBoxRect(.mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = min(2.0, 2400 / max(box.width, box.height))
        let size = CGSize(width: box.width * scale, height: box.height * scale)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.concatenate(ref.getDrawingTransform(.mediaBox, rect: CGRect(origin: .zero, size: size), rotate: 0, preserveAspectRatio: true))
        ctx.drawPDFPage(ref)
        return ctx.makeImage()
    }

    private static func ocr(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return "" }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
}
