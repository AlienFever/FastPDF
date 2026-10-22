// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

// Generates test PDFs. Usage: swift tools/make_fixtures.swift Tests/fixtures
import AppKit
import CoreText
import PDFKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Tests/fixtures")
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
let lorem = """
Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. \
Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. \
Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. \
Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.
"""

func drawText(_ text: String, in rect: CGRect, size: CGFloat, ctx: CGContext) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.black]
    let frameSetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
    let frame = CTFramesetterCreateFrame(frameSetter, CFRange(), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
}

func makePDF(_ name: String, pages: Int, body: (Int) -> String) -> URL {
    let url = outDir.appendingPathComponent(name)
    var box = pageRect
    let ctx = CGContext(url as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: name] as CFDictionary)!
    for i in 1...pages {
        ctx.beginPDFPage(nil)
        drawText("Page \(i)", in: CGRect(x: 72, y: 680, width: 468, height: 60), size: 28, ctx: ctx)
        drawText(body(i), in: CGRect(x: 72, y: 72, width: 468, height: 590), size: 12, ctx: ctx)
        ctx.endPDFPage()
    }
    ctx.closePDF()
    return url
}

_ = makePDF("small.pdf", pages: 1) { _ in lorem }
_ = makePDF("big.pdf", pages: 1500) { i in String(repeating: lorem + "\n\n", count: 6) + "Marker word: zebra\(i)" }

// Annotated: outline + highlights/underline/strikeout/note.
let annotatedURL = makePDF("annotated.pdf", pages: 30) { i in
    "Chapter \((i - 1) / 10 + 1), section \((i - 1) % 10 + 1).\n\n" + String(repeating: lorem + "\n\n", count: 4)
}
let doc = PDFDocument(url: annotatedURL)!
let root = PDFOutline()
for chapter in 0..<3 {
    let c = PDFOutline()
    c.label = "Chapter \(chapter + 1)"
    c.destination = PDFDestination(page: doc.page(at: chapter * 10)!, at: CGPoint(x: 0, y: 792))
    for section in 0..<3 {
        let s = PDFOutline()
        s.label = "Section \(chapter + 1).\(section + 1)"
        s.destination = PDFDestination(page: doc.page(at: chapter * 10 + section * 3)!, at: CGPoint(x: 0, y: 792))
        c.insertChild(s, at: section)
    }
    root.insertChild(c, at: chapter)
}
doc.outlineRoot = root

func annotateFirstMatch(_ word: String, onPage index: Int, type: PDFAnnotationSubtype, color: NSColor) {
    let page = doc.page(at: index)!
    guard let sel = doc.findString(word, withOptions: []).first(where: { $0.pages.first == page }) else { return }
    let bounds = sel.bounds(for: page)
    let annotation = PDFAnnotation(bounds: bounds, forType: type, withProperties: nil)
    annotation.color = color
    // Quad points relative to the annotation bounds, so viewers know exactly what was marked.
    annotation.quadrilateralPoints = [
        NSValue(point: CGPoint(x: 0, y: bounds.height)), NSValue(point: CGPoint(x: bounds.width, y: bounds.height)),
        NSValue(point: CGPoint(x: 0, y: 0)), NSValue(point: CGPoint(x: bounds.width, y: 0)),
    ]
    page.addAnnotation(annotation)
}
for (i, page) in [1, 4, 12, 25].enumerated() {
    annotateFirstMatch("consectetur adipiscing elit", onPage: page, type: .highlight, color: .systemYellow.withAlphaComponent(0.5))
    if i % 2 == 0 { annotateFirstMatch("magna aliqua", onPage: page, type: .underline, color: .systemRed) }
}
annotateFirstMatch("nulla pariatur", onPage: 7, type: .strikeOut, color: .systemRed)
let note = PDFAnnotation(bounds: CGRect(x: 540, y: 700, width: 20, height: 20), forType: .text, withProperties: nil)
note.contents = "Remember to check this paragraph."
note.color = .systemYellow
doc.page(at: 9)!.addAnnotation(note)
doc.write(to: annotatedURL)
print("Wrote fixtures to \(outDir.path)")
