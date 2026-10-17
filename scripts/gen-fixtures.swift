// Regenerates Tests/Fixtures/{corpus,documents-tree,expected.json}. All content is invented.
// Run from the Folio directory: swift scripts/gen-fixtures.swift
// Text, images and binaries are deterministic; PDFs embed a creation date from CoreGraphics.
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum Kind {
    case pdf([String])
    case scannedPDF([String])
    case text(String)
    case image([String])
    case chart(title: String, bars: [(String, Double)])
    case photo(circles: Bool)
    case binary(seed: UInt64)
}

struct Spec {
    let name: String
    let folder: String?
    var acceptable: [String] = []
    let kind: Kind
}

let tree = """
Finance
Finance/Invoices
Finance/Invoices/Work
Finance/Invoices/Personal
Finance/Banking
Finance/Taxes
Finance/Receipts
Housing
Housing/Lease
Housing/Utilities
Housing/Insurance
College
College/Computer Networks
College/Databases
College/Admin
Work
Work/Meeting Notes
Work/Contracts
Work/Proposals
Career
Career/Resume
Career/Cover Letters
Personal
Personal/Recipes
Personal/Letters
Screenshots
Screenshots/Errors
Reference
Reference/Slides
Reference/Charts
""".split(separator: "\n").map(String.init)

let specs: [Spec] = [
    // PDFs with a text layer
    Spec(name: "INV-2026-0412.pdf", folder: "Finance/Invoices/Work", kind: .pdf([
        "Cobalt Cloud Hosting", "INVOICE INV-2026-0412", "Date: 2026-09-30", "Bill to: Marlow Studio LLC",
        "Business plan, 3 servers (September)   $87.00", "Backup add-on                          $12.00",
        "Total due: $99.00", "Pay by 2026-10-14"])),
    Spec(name: "statement_sep.pdf", folder: "Finance/Banking", kind: .pdf([
        "Lakeview Credit Union", "Checking account statement", "Period: 2026-09-01 to 2026-09-30",
        "Opening balance  $3,204.18", "Deposits  $2,450.00", "Withdrawals  $1,987.62", "Closing balance  $3,666.56"])),
    Spec(name: "lease_agreement_signed.pdf", folder: "Housing/Lease", kind: .pdf([
        "RESIDENTIAL LEASE AGREEMENT", "Landlord: Maple Court Properties", "Tenant: Sam Rivera",
        "Premises: 14 Maple Court, Apt 4B", "Term: 12 months beginning 2026-08-01", "Monthly rent: $1,450.00",
        "Security deposit: $1,450.00"])),
    Spec(name: "tax_form_1099.pdf", folder: "Finance/Taxes", kind: .pdf([
        "Form 1099-NEC", "Nonemployee Compensation", "Tax year 2025", "Payer: Orbit Labs Inc.",
        "Recipient: Sam Rivera", "Box 1 Nonemployee compensation: $18,400.00"])),
    Spec(name: "CN_lecture_07.pdf", folder: "College/Computer Networks", kind: .pdf([
        "CS 3510 Computer Networks", "Lecture 7: Routing", "Link state routing and Dijkstra's algorithm",
        "Distance vector routing and the count-to-infinity problem", "OSPF and RIP compared",
        "Reading: chapter 5, sections 5.1 to 5.3"])),
    Spec(name: "CN_assignment2.pdf", folder: "College/Computer Networks", kind: .pdf([
        "CS 3510 Computer Networks", "Assignment 2: TCP congestion control", "Due: 2026-10-20",
        "1. Plot the congestion window for TCP Reno over 40 round trips.",
        "2. Explain slow start and congestion avoidance.", "3. What happens after three duplicate ACKs?"])),
    Spec(name: "DB_lecture_04.pdf", folder: "College/Databases", kind: .pdf([
        "CS 4400 Database Systems", "Lecture 4: Normalization", "Functional dependencies",
        "First, second and third normal form", "Boyce-Codd normal form and lossless decomposition"])),
    Spec(name: "DB_syllabus.pdf", folder: "College/Databases", acceptable: ["College/Admin"], kind: .pdf([
        "CS 4400 Database Systems", "Syllabus, Fall 2026", "Instructor: Dr. Okafor", "Grading: midterm 30%, final 40%, project 30%",
        "Topics: relational model, SQL, normalization, transactions, indexing"])),
    Spec(name: "resume_2026_final.pdf", folder: "Career/Resume", kind: .pdf([
        "Sam Rivera", "Software Engineer", "Experience", "Marlow Studio LLC, Freelance developer, 2024 to present",
        "Orbit Labs, Contract engineer, 2025", "Education", "B.S. Computer Science, Eastfield University, 2027",
        "Skills: Swift, Python, SQL"])),
    Spec(name: "electric_bill_oct.pdf", folder: "Housing/Utilities", kind: .pdf([
        "Greenline Electric", "Monthly statement, October 2026", "Account 55-20431", "Service address: 14 Maple Court, Apt 4B",
        "Usage: 312 kWh", "Amount due: $58.40", "Due date: 2026-11-05"])),
    Spec(name: "enrollment_verification.pdf", folder: "College/Admin", kind: .pdf([
        "Eastfield University Office of the Registrar", "Enrollment verification", "Student: Sam Rivera",
        "Status: full-time, Fall 2026", "Expected graduation: May 2027"])),
    Spec(name: "service_agreement.pdf", folder: "Work/Contracts", kind: .pdf([
        "FREELANCE SERVICE AGREEMENT", "Between Marlow Studio LLC and Birchwood Bakery", "Scope: website redesign and online ordering",
        "Fee: $6,500 payable in two instalments", "Term: 2026-10-01 to 2026-12-15", "Governing law: State of Oregon"])),

    // Images
    Spec(name: "receipt_cafe.png", folder: "Finance/Receipts", kind: .image([
        "CORNER CAFE", "2026-10-03  08:12", "Flat white        4.50", "Croissant         3.75", "TOTAL             8.25", "Paid by card"])),
    Spec(name: "error_dialog.png", folder: "Screenshots/Errors", kind: .image([
        "Connection refused", "Could not connect to the server at", "127.0.0.1 port 5432.", "Is the database running?", "[ Retry ]   [ Cancel ]"])),
    Spec(name: "slide_routing.png", folder: "Reference/Slides", acceptable: ["College/Computer Networks"], kind: .image([
        "Link State Routing", "Every router floods its links", "Each router runs Dijkstra", "Shortest path tree to all nodes"])),
    Spec(name: "chart_q3_revenue.png", folder: "Reference/Charts", acceptable: ["Finance"], kind: .chart(
        title: "Q3 Revenue by Month", bars: [("Jul", 4.2), ("Aug", 5.1), ("Sep", 6.3)])),
    Spec(name: "grocery_receipt.png", folder: "Finance/Receipts", kind: .image([
        "FRESH BASKET MARKET", "2026-09-28", "Oats 1kg        3.20", "Milk 2L          2.40", "Apples           4.15", "TOTAL           9.75"])),
    Spec(name: "terminal_error.png", folder: "Screenshots/Errors", kind: .image([
        "Traceback (most recent call last):", "File \"main.py\", line 12, in <module>", "ModuleNotFoundError:", "No module named 'requests'"])),
    Spec(name: "photo_gradient.png", folder: nil, kind: .photo(circles: false)),
    Spec(name: "photo_shapes.png", folder: nil, kind: .photo(circles: true)),

    // Plain text and Markdown
    Spec(name: "meeting notes 10-12.md", folder: "Work/Meeting Notes", kind: .text("""
        # Weekly sync with Orbit Labs
        Date: 2026-10-12
        Attendees: Sam, Dana, Priya
        - Dana to send the API spec by Friday
        - Priya reviews the sync client
        - Next sync Oct 19
        """)),
    Spec(name: "standup.txt", folder: "Work/Meeting Notes", kind: .text("""
        Standup 2026-10-14
        Yesterday: finished the export screen
        Today: fix the login bug, review Priya's PR
        Blockers: waiting on API keys
        """)),
    Spec(name: "client_kickoff_notes.txt", folder: "Work/Meeting Notes", kind: .text("""
        Kickoff call with Birchwood Bakery
        They want online ordering for pickup only.
        Launch target: first week of December.
        Open question: who writes the menu copy?
        """)),
    Spec(name: "pancakes.txt", folder: "Personal/Recipes", kind: .text("""
        Pancakes
        1 cup flour, 1 tbsp sugar, 2 tsp baking powder, pinch of salt
        1 cup milk, 1 egg, 2 tbsp melted butter
        Whisk, rest 5 minutes, cook on medium heat until bubbles form.
        """)),
    Spec(name: "lentil_soup.md", folder: "Personal/Recipes", kind: .text("""
        # Lentil soup
        Serves 4
        - 1 cup red lentils
        - 1 onion, 2 carrots, 3 cloves garlic
        - 1 tsp cumin, 1 litre stock
        Simmer for 25 minutes, blend half, add lemon juice.
        """)),
    Spec(name: "cover_letter_draft.txt", folder: "Career/Cover Letters", kind: .text("""
        Dear Hiring Manager,
        I am writing to apply for the iOS Engineer role at Orbit Labs.
        Over the past two years I have built and shipped three apps as a freelancer.
        I would welcome the chance to talk about how I can help your team.
        Sincerely, Sam Rivera
        """)),
    Spec(name: "cover_letter_v2.md", folder: "Career/Cover Letters", kind: .text("""
        Dear Ms. Alvarez,
        I am applying for the junior developer position at Tidewater Software.
        My coursework in databases and networks, plus my freelance work, prepared me for production code.
        Thank you for your time. Sam Rivera
        """)),
    Spec(name: "deductions_2025.txt", folder: "Finance/Taxes", kind: .text("""
        2025 deductions to claim
        Home office: 12 percent of rent and utilities
        Software subscriptions: $480
        Laptop (bought March): $1,250
        Mileage to client sites: 310 miles
        """)),
    Spec(name: "notes_cn.txt", folder: "College/Computer Networks", kind: .text("""
        TCP three-way handshake: SYN, SYN-ACK, ACK.
        Flow control uses the receive window.
        Congestion control uses the congestion window. Slow start doubles it every round trip.
        """)),
    Spec(name: "sql_practice.md", folder: "College/Databases", kind: .text("""
        # SQL practice
        SELECT name FROM students JOIN enrollments USING (student_id);
        LEFT JOIN keeps rows with no match.
        GROUP BY course_id HAVING COUNT(*) > 20;
        """)),
    Spec(name: "rent_note.txt", folder: "Housing/Lease", acceptable: ["Finance/Receipts"], kind: .text("""
        Rent paid for October 2026
        Maple Court Properties, Apt 4B
        Amount: $1,450.00 by check number 212
        Landlord confirmed receipt on 2026-10-01.
        """)),
    Spec(name: "transfer_confirmation.txt", folder: "Finance/Banking", kind: .text("""
        Lakeview Credit Union
        Transfer confirmation
        From checking to savings: $500.00
        Date: 2026-10-05
        Reference: TRX-88213
        """)),

    // Awkwardly named
    Spec(name: "invoice (3).pdf", folder: "Finance/Invoices/Personal", kind: .pdf([
        "Quillnote", "Receipt and invoice 7731", "Quillnote Pro, personal plan, annual", "Billed to: Sam Rivera (personal)",
        "Amount: $48.00", "Paid 2026-09-18"])),
    Spec(name: "Untitled.pdf", folder: "College/Databases", kind: .pdf([
        "CS 4400 Database Systems", "Lecture 9: Transactions", "ACID properties", "Atomicity, consistency, isolation, durability",
        "Serializability and two-phase locking"])),
    Spec(name: "IMG_4821.png", folder: "Finance/Receipts", kind: .image([
        "IRONWOOD HARDWARE", "2026-09-21", "Drill bits set     14.99", "Wall anchors        6.50", "Painter's tape      5.25", "TOTAL             26.74"])),
    Spec(name: "Screenshot 2026-10-02 at 10.14.33.png", folder: "Screenshots/Errors", kind: .image([
        "Build Failed", "3 errors in MainView.swift", "Cannot find 'viewModel' in scope", "Missing return in a function"])),
    Spec(name: "download.pdf", folder: "Housing/Lease", kind: .pdf([
        "PARKING ADDENDUM", "To the lease for 14 Maple Court, Apt 4B", "Landlord: Maple Court Properties",
        "One covered space, number 17", "Monthly fee: $60.00", "Effective 2026-09-01"])),
    Spec(name: "scan0003.pdf", folder: "Finance/Banking", kind: .scannedPDF([
        "LAKEVIEW CREDIT UNION", "Notice of fee schedule change", "Effective 2026-11-01 the monthly", "maintenance fee is $5.00.",
        "Waived with a $1,000 balance."])),

    // Empty and near-empty: should be queued
    Spec(name: "notes.txt", folder: nil, kind: .text("")),
    Spec(name: "new.txt", folder: nil, kind: .text("x")),
    Spec(name: "todo.md", folder: nil, kind: .text("- \n")),
    Spec(name: "temp.txt", folder: nil, kind: .text("asdf")),

    // Unreadable binaries: should be queued
    Spec(name: "data.bin", folder: nil, kind: .binary(seed: 11)),
    Spec(name: "export.dat", folder: nil, kind: .binary(seed: 29)),

    // Near-duplicates of different categories
    Spec(name: "lumen_invoice_oct.pdf", folder: "Finance/Invoices/Work", kind: .pdf([
        "Lumen Fiber", "Invoice LF-20261012", "Bill to: Marlow Studio LLC", "Business Fiber 1 Gbps, October",
        "Static IP add-on", "Total: $119.00"])),
    Spec(name: "lumen_invoice_home.pdf", folder: "Finance/Invoices/Personal", acceptable: ["Housing/Utilities"], kind: .pdf([
        "Lumen Fiber", "Invoice LF-20261077", "Bill to: Sam Rivera, 14 Maple Court, Apt 4B", "Residential Fiber 500 Mbps, October",
        "Total: $65.00"])),
    Spec(name: "orbit_labs_invoice_0933.pdf", folder: "Finance/Invoices/Work", kind: .pdf([
        "Marlow Studio LLC", "Invoice 0933", "Bill to: Orbit Labs Inc.", "Sync client development, 40 hours at $85",
        "Total due: $3,400.00", "Terms: net 30"])),
    Spec(name: "orbit_labs_contract.pdf", folder: "Work/Contracts", kind: .pdf([
        "CONTRACTOR AGREEMENT", "Between Orbit Labs Inc. and Marlow Studio LLC", "Scope: sync client for the Orbit mobile app",
        "Rate: $85 per hour", "Term: 2026-09-01 to 2026-12-31", "Confidentiality and IP assignment apply."])),
    Spec(name: "lakeview_cc_statement.pdf", folder: "Finance/Banking", kind: .pdf([
        "Lakeview Credit Union", "Credit card statement, September 2026", "Previous balance  $412.30", "Purchases  $268.14",
        "Payment received  $412.30", "New balance  $268.14"])),
    Spec(name: "lakeview_1099_int.pdf", folder: "Finance/Taxes", kind: .pdf([
        "Lakeview Credit Union", "Form 1099-INT", "Interest income, tax year 2025", "Recipient: Sam Rivera",
        "Box 1 Interest income: $38.20"])),
]

// MARK: drawing

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent("Tests/Fixtures", isDirectory: true)
let corpus = root.appendingPathComponent("corpus", isDirectory: true)
let treeDir = root.appendingPathComponent("documents-tree", isDirectory: true)

func attributed(_ text: String, size: CGFloat) -> NSAttributedString {
    let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
    return NSAttributedString(string: text, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
    ])
}

func drawLines(_ lines: [String], size: CGFloat, in ctx: CGContext, origin: CGPoint, lineHeight: CGFloat) {
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    var y = origin.y
    for line in lines {
        let ctLine = CTLineCreateWithAttributedString(attributed(line, size: size))
        ctx.textPosition = CGPoint(x: origin.x, y: y)
        CTLineDraw(ctLine, ctx)
        y -= lineHeight
    }
}

func bitmap(width: Int, height: Int, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func textImage(_ lines: [String]) -> CGImage {
    let lineHeight: CGFloat = 56
    let height = Int(lineHeight) * lines.count + 120
    return bitmap(width: 1200, height: height) { ctx in
        drawLines(lines, size: 38, in: ctx, origin: CGPoint(x: 60, y: CGFloat(height) - 90), lineHeight: lineHeight)
    }
}

func writePDF(_ lines: [String], to url: URL) {
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    drawLines(lines, size: 14, in: ctx, origin: CGPoint(x: 54, y: 720), lineHeight: 26)
    ctx.endPDFPage()
    ctx.closePDF()
}

// Image-only PDF: no text layer, so extraction must fall back to OCR.
func writeScannedPDF(_ lines: [String], to url: URL) {
    let image = textImage(lines)
    var box = CGRect(x: 0, y: 0, width: 612, height: 792)
    let ctx = CGContext(url as CFURL, mediaBox: &box, nil)!
    ctx.beginPDFPage(nil)
    let h = 612.0 * CGFloat(image.height) / CGFloat(image.width)
    ctx.draw(image, in: CGRect(x: 0, y: 792 - h, width: 612, height: h))
    ctx.endPDFPage()
    ctx.closePDF()
}

func chartImage(title: String, bars: [(String, Double)]) -> CGImage {
    bitmap(width: 1200, height: 800) { ctx in
        drawLines([title], size: 48, in: ctx, origin: CGPoint(x: 80, y: 720), lineHeight: 0)
        let maxV = bars.map(\.1).max() ?? 1
        for (i, bar) in bars.enumerated() {
            let x = 160 + CGFloat(i) * 300
            let h = CGFloat(bar.1 / maxV) * 480
            ctx.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1))
            ctx.fill(CGRect(x: x, y: 120, width: 200, height: h))
            drawLines([bar.0], size: 40, in: ctx, origin: CGPoint(x: x + 60, y: 60), lineHeight: 0)
        }
    }
}

func photoImage(circles: Bool) -> CGImage {
    bitmap(width: 800, height: 600) { ctx in
        if circles {
            for i in 0..<6 {
                ctx.setFillColor(CGColor(red: CGFloat(i) / 6, green: 0.5, blue: 1 - CGFloat(i) / 6, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: 60 + i * 110, y: 100 + (i % 3) * 120, width: 140, height: 140))
            }
        } else {
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                      colors: [CGColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 1), CGColor(red: 0.2, green: 0.3, blue: 0.7, alpha: 1)] as CFArray,
                                      locations: [0, 1])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 800, y: 600), options: [])
        }
    }
}

func binaryData(seed: UInt64) -> Data {
    var state = seed &* 6364136223846793005 &+ 1442695040888963407
    return Data((0..<4096).map { _ in
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return UInt8(truncatingIfNeeded: state >> 33)
    })
}

// MARK: generate

try? fm.removeItem(at: corpus)
try? fm.removeItem(at: treeDir)
try fm.createDirectory(at: corpus, withIntermediateDirectories: true)

for spec in specs {
    let url = corpus.appendingPathComponent(spec.name)
    switch spec.kind {
    case .pdf(let lines): writePDF(lines, to: url)
    case .scannedPDF(let lines): writeScannedPDF(lines, to: url)
    case .text(let body): try body.write(to: url, atomically: true, encoding: .utf8)
    case .image(let lines): writePNG(textImage(lines), to: url)
    case .chart(let title, let bars): writePNG(chartImage(title: title, bars: bars), to: url)
    case .photo(let circles): writePNG(photoImage(circles: circles), to: url)
    case .binary(let seed): try binaryData(seed: seed).write(to: url)
    }
}

// .gitkeep so the empty tree survives version control; hidden files are ignored by FolderTree.
for folder in tree {
    let dir = treeDir.appendingPathComponent(folder, isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    fm.createFile(atPath: dir.appendingPathComponent(".gitkeep").path, contents: Data())
}

let expected: [[String: Any]] = specs.map { spec in
    var entry: [String: Any] = ["file": spec.name, "shouldQueue": spec.folder == nil]
    if let folder = spec.folder { entry["folder"] = folder }
    if !spec.acceptable.isEmpty { entry["acceptable"] = spec.acceptable }
    return entry
}
let json = try JSONSerialization.data(withJSONObject: expected, options: [.prettyPrinted, .sortedKeys])
try json.write(to: root.appendingPathComponent("expected.json"))
print("wrote \(specs.count) files, \(tree.count) folders")
