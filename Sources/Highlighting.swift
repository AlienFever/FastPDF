// FastPDF — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import PDFKit

enum HighlightColor: String, CaseIterable {
    case yellow, green, blue, pink, purple, orange

    var name: String { rawValue.capitalized }

    var color: NSColor {
        switch self {
        case .yellow: return NSColor(srgbRed: 1.00, green: 0.86, blue: 0.20, alpha: 1)
        case .green: return NSColor(srgbRed: 0.55, green: 0.86, blue: 0.40, alpha: 1)
        case .blue: return NSColor(srgbRed: 0.45, green: 0.72, blue: 1.00, alpha: 1)
        case .pink: return NSColor(srgbRed: 1.00, green: 0.55, blue: 0.72, alpha: 1)
        case .purple: return NSColor(srgbRed: 0.76, green: 0.58, blue: 1.00, alpha: 1)
        case .orange: return NSColor(srgbRed: 1.00, green: 0.66, blue: 0.30, alpha: 1)
        }
    }

    static var primary: HighlightColor {
        get { UserDefaults.standard.string(forKey: "PrimaryHighlight").flatMap(Self.init(rawValue:)) ?? .yellow }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "PrimaryHighlight") }
    }

    static var secondary: HighlightColor {
        get { UserDefaults.standard.string(forKey: "SecondaryHighlight").flatMap(Self.init(rawValue:)) ?? .green }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "SecondaryHighlight") }
    }

    /// Small color dot for menus.
    var swatch: NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            self.color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}

/// One change to a page's annotations, recorded so the background save can replay it onto a fresh copy of the file.
struct AnnotationChange {
    enum Kind { case add, remove }
    let kind: Kind
    let pageIndex: Int
    let type: String
    let bounds: CGRect
    let quadPoints: [CGPoint]
    let color: NSColor
    let contents: String?

    init(_ kind: Kind, _ annotation: PDFAnnotation, pageIndex: Int) {
        self.kind = kind
        self.pageIndex = pageIndex
        type = annotation.type ?? ""
        bounds = annotation.bounds
        quadPoints = annotation.quadrilateralPoints?.map(\.pointValue) ?? []
        color = annotation.color
        contents = annotation.contents
    }

    func apply(to document: PDFDocument) {
        guard let page = document.page(at: pageIndex) else { return }
        switch kind {
        case .add:
            page.addAnnotation(type == "Text"
                ? Self.makeNote(bounds: bounds, text: contents ?? "", color: color)
                : Self.makeHighlight(bounds: bounds, quadPoints: quadPoints, color: color))
        case .remove:
            if let match = page.annotations.first(where: {
                $0.type == type && $0.bounds.isClose(to: bounds) && (type != "Text" || $0.contents == contents)
            }) {
                page.removeAnnotation(match)
            }
        }
    }

    /// A sticky note: the standard PDF "Text" annotation (shown as a note icon by every PDF app).
    static func makeNote(bounds: CGRect, text: String, color: NSColor) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .text, withProperties: nil)
        annotation.iconType = .note
        annotation.contents = text
        annotation.color = color
        annotation.modificationDate = Date()
        annotation.userName = NSFullUserName()
        return annotation
    }

    static func makeHighlight(bounds: CGRect, quadPoints: [CGPoint], color: NSColor) -> PDFAnnotation {
        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.quadrilateralPoints = quadPoints.map { NSValue(point: $0) }
        annotation.color = color
        annotation.modificationDate = Date()
        annotation.userName = NSFullUserName()
        return annotation
    }
}

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 0.5) -> Bool {
        abs(minX - other.minX) < tolerance && abs(minY - other.minY) < tolerance
            && abs(width - other.width) < tolerance && abs(height - other.height) < tolerance
    }
}

extension PDFAnnotation {
    var isNote: Bool { type == "Text" }

    var isTextMarkup: Bool {
        ["Highlight", "Underline", "StrikeOut", "Squiggly"].contains(type ?? "")
    }

    /// Hit test against the marked lines, not the bounding box (a two-line highlight's box covers both full lines).
    func markedAreaContains(_ point: CGPoint) -> Bool {
        let points = quadrilateralPoints?.map(\.pointValue) ?? []
        guard points.count >= 4 else { return bounds.contains(point) }
        for start in stride(from: 0, through: points.count - 4, by: 4) {
            let quad = points[start..<start + 4]
            let xs = quad.map(\.x), ys = quad.map(\.y)
            let rect = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
            // Quad points are relative to the annotation's origin in PDFKit; some files store them in page space.
            if rect.offsetBy(dx: bounds.minX, dy: bounds.minY).contains(point) || rect.contains(point) { return true }
        }
        return false
    }
}
