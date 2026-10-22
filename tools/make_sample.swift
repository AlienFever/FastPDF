// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

// Generates the sample document used for the README screenshots: a short typeset essay with a table of
// contents, highlights in two colors and a sticky note. Usage: swift tools/make_sample.swift out.pdf
import AppKit
import CoreText
import PDFKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "sample.pdf")
let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
let margin: CGFloat = 78

let chapters: [(String, [String])] = [
    ("Why Speed Matters", [
        "Every tool we use sets a rhythm. When a document opens the instant you ask for it, reading feels like turning to a page in a book you already hold. When it makes you wait, even for a second, the thought you were following slips a little further away.",
        "Most of the time we spend with documents is not spent reading them. It is spent getting to them: waiting for a window, hunting for the page we left, scrolling past the parts we have already understood. A good reader removes that friction until it disappears.",
        "Speed is not a feature you notice. It is the absence of the moments you would otherwise notice, and that absence is what lets attention stay where it belongs: on the words.",
    ]),
    ("Reading on Screens", [
        "A screen is not paper, and it should not pretend to be. It can fit a page to its width, remember exactly where you stopped, and jump to any chapter without a bookmark falling out.",
        "The best screen reading keeps the page in the center of the experience. Controls stay out of the way until they are needed, then answer immediately. Toolbars can be beautiful, but the page is the point.",
        "Layouts matter too. A single page focuses the eye; a continuous scroll suits long arguments; two pages side by side recall the spread of an open book. Moving between them should take a keystroke, not a trip through settings.",
    ]),
    ("Marking What Matters", [
        "Highlighting is a conversation with the text. A line marked in yellow says: this is the claim. A line marked in green says: this is the evidence. Two colors are often all a careful reader needs.",
        "The value of a highlight is in returning to it. A list of every marked passage, gathered in one place and linked back to its page, turns a long document into a short one you wrote yourself.",
        "Good highlighting is sparse. If everything is marked, nothing is. The discipline of choosing is part of understanding.",
    ]),
    ("Notes in the Margin", [
        "Some thoughts are too long for a highlight. They belong in the margin: a question for later, a disagreement, a connection to something read last week.",
        "A note that lives inside the document travels with it. Open the file anywhere, in any app, and the conversation is still there, pinned to the paragraph that started it.",
        "Reading well is slow work done with fast tools. The tools should be quick so the thinking does not have to be.",
    ]),
]

func font(_ name: String, _ size: CGFloat, fallback: NSFont) -> NSFont { NSFont(name: name, size: size) ?? fallback }
let titleFont = font("Charter-Bold", 30, fallback: .boldSystemFont(ofSize: 30))
let headingFont = font("Charter-Bold", 19, fallback: .boldSystemFont(ofSize: 19))
let bodyFont = font("Charter-Roman", 12.5, fallback: .systemFont(ofSize: 12.5))
let smallFont = font("Charter-Italic", 12, fallback: .systemFont(ofSize: 12))
let ink = NSColor(white: 0.12, alpha: 1)
let accent = NSColor(srgbRed: 0.85, green: 0.42, blue: 0.05, alpha: 1)

func style(spacingBefore: CGFloat, after: CGFloat, line: CGFloat = 1.0) -> NSParagraphStyle {
    let p = NSMutableParagraphStyle()
    p.paragraphSpacingBefore = spacingBefore
    p.paragraphSpacing = after
    p.lineHeightMultiple = line
    return p
}

// Build the text, remembering where each chapter heading starts.
let text = NSMutableAttributedString()
text.append(NSAttributedString(string: "The Quiet Art of Reading\n",
                               attributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: style(spacingBefore: 0, after: 6)]))
text.append(NSAttributedString(string: "Four short chapters on reading documents well\n",
                               attributes: [.font: smallFont, .foregroundColor: accent, .paragraphStyle: style(spacingBefore: 0, after: 18)]))
var headingOffsets: [Int] = []
for (i, chapter) in chapters.enumerated() {
    headingOffsets.append(text.length)
    text.append(NSAttributedString(string: "\(i + 1). \(chapter.0)\n",
                                   attributes: [.font: headingFont, .foregroundColor: ink, .paragraphStyle: style(spacingBefore: 16, after: 8)]))
    for paragraph in chapter.1 {
        text.append(NSAttributedString(string: paragraph + "\n",
                                       attributes: [.font: bodyFont, .foregroundColor: ink, .paragraphStyle: style(spacingBefore: 0, after: 10, line: 1.25)]))
    }
}

// Lay the text out across pages; put each chapter on a new page after the first.
var pageStarts: [Int] = []
var box = pageRect
let context = CGContext(out as CFURL, mediaBox: &box, [kCGPDFContextTitle as String: "The Quiet Art of Reading"] as CFDictionary)!
let setter = CTFramesetterCreateWithAttributedString(text)
let chapterBreaks = headingOffsets.dropFirst()   // chapter 1 follows the title on page 1
var location = 0
while location < text.length {
    pageStarts.append(location)
    context.beginPDFPage(nil)
    let end = chapterBreaks.first(where: { $0 > location }) ?? text.length
    let frameRect = pageRect.insetBy(dx: margin, dy: margin)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: location, length: end - location),
                                         CGPath(rect: frameRect, transform: nil), nil)
    CTFrameDraw(frame, context)
    // Folio
    let folio = NSAttributedString(string: "\(pageStarts.count)", attributes: [.font: smallFont, .foregroundColor: NSColor.gray])
    let line = CTLineCreateWithAttributedString(folio)
    context.textPosition = CGPoint(x: pageRect.midX - 4, y: 40)
    CTLineDraw(line, context)
    context.endPDFPage()
    let visible = CTFrameGetVisibleStringRange(frame)
    location += max(visible.length, 1)
}
context.closePDF()

// Outline, highlights and a note with PDFKit.
let doc = PDFDocument(url: out)!
let root = PDFOutline()
for (i, chapter) in chapters.enumerated() {
    let pageIndex = pageStarts.lastIndex(where: { $0 <= headingOffsets[i] }) ?? 0
    let item = PDFOutline()
    item.label = "\(i + 1). \(chapter.0)"
    item.destination = PDFDestination(page: doc.page(at: pageIndex)!, at: CGPoint(x: 0, y: pageRect.maxY))
    root.insertChild(item, at: i)
}
doc.outlineRoot = root

/// Finds a phrase in the page text even when it wraps across lines (PDFKit's findString doesn't).
func selection(of phrase: String) -> PDFSelection? {
    for i in 0..<doc.pageCount {
        guard let page = doc.page(at: i), let raw = page.string else { continue }
        let flat = raw.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") as NSString
        let range = flat.range(of: phrase)
        if range.location != NSNotFound {
            return doc.selection(from: page, atCharacterIndex: range.location, to: page, atCharacterIndex: NSMaxRange(range) - 1)
        }
    }
    return nil
}

func mark(_ phrase: String, _ color: NSColor) {
    guard let selection = selection(of: phrase), let page = selection.pages.first else { return print("not found: \(phrase)") }
    let rects = selection.selectionsByLine().map { $0.bounds(for: page) }
    let union = rects.dropFirst().reduce(rects[0]) { $0.union($1) }
    let annotation = PDFAnnotation(bounds: union, forType: .highlight, withProperties: nil)
    annotation.quadrilateralPoints = rects.flatMap { r -> [NSValue] in
        let r = r.offsetBy(dx: -union.minX, dy: -union.minY)
        return [CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY)].map { NSValue(point: $0) }
    }
    annotation.color = color
    page.addAnnotation(annotation)
}
let yellow = NSColor(srgbRed: 1.00, green: 0.86, blue: 0.20, alpha: 1)
let green = NSColor(srgbRed: 0.55, green: 0.86, blue: 0.40, alpha: 1)
mark("When it makes you wait, even for a second, the thought you were following slips a little further away.", yellow)
mark("Speed is not a feature you notice.", green)
mark("Controls stay out of the way until they are needed, then answer immediately.", yellow)
mark("Two colors are often all a careful reader needs.", green)

if let selection = selection(of: "A good reader removes that friction"), let page = selection.pages.first {
    let line = selection.bounds(for: page)
    let note = PDFAnnotation(bounds: CGRect(x: pageRect.maxX - margin + 18, y: line.minY - 4, width: 22, height: 22),
                             forType: .text, withProperties: nil)
    note.iconType = .note
    note.contents = "This is the whole idea in one sentence. Quote it in the intro."
    note.color = NSColor(srgbRed: 1.0, green: 0.84, blue: 0.25, alpha: 1)
    page.addAnnotation(note)
}
doc.write(to: out)
print("Wrote \(out.path): \(doc.pageCount) pages")
