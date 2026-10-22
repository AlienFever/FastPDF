// FastPDF for Mac — Copyright (C) 2026 Alienfever
// SPDX-License-Identifier: GPL-3.0-or-later

// Draws the app icon and writes Resources/AppIcon.icns. Usage: swift tools/make_icon.swift
import AppKit

func render(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.scaleBy(x: s, y: s)

    // macOS squircle tile on the standard 1024 grid (824pt body, 100pt margins): yellow → orange.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 24
    shadow.shadowOffset = NSSize(width: 0, height: -10)
    shadow.set()
    NSColor(red: 1.0, green: 0.62, blue: 0.10, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 1.00, green: 0.84, blue: 0.20, alpha: 1),
                        NSColor(red: 1.00, green: 0.50, blue: 0.08, alpha: 1)])!
        .draw(in: tile, angle: -90)

    // Document outline with folded corner, in white.
    let page = NSRect(x: 297, y: 222, width: 430, height: 580)
    let fold: CGFloat = 130
    let sheet = NSBezierPath()
    sheet.move(to: NSPoint(x: page.minX, y: page.minY))
    sheet.line(to: NSPoint(x: page.maxX, y: page.minY))
    sheet.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    sheet.line(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    sheet.line(to: NSPoint(x: page.minX, y: page.maxY))
    sheet.close()
    sheet.lineJoinStyle = .round
    sheet.lineWidth = 34
    NSColor.white.withAlphaComponent(0.22).setFill()
    sheet.fill()
    NSColor.white.setStroke()
    sheet.stroke()
    let corner = NSBezierPath()
    corner.move(to: NSPoint(x: page.maxX - fold, y: page.maxY))
    corner.line(to: NSPoint(x: page.maxX - fold, y: page.maxY - fold))
    corner.line(to: NSPoint(x: page.maxX, y: page.maxY - fold))
    corner.lineJoinStyle = .round
    corner.lineCapStyle = .round
    corner.lineWidth = 34
    corner.stroke()

    // White lightning bolt in the middle.
    let bolt = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [(560, 680), (400, 470), (500, 470), (455, 300), (625, 530), (522, 530)]
    bolt.move(to: NSPoint(x: pts[0].0, y: pts[0].1))
    pts.dropFirst().forEach { bolt.line(to: NSPoint(x: $0.0, y: $0.1)) }
    bolt.close()
    bolt.lineJoinStyle = .round
    bolt.lineWidth = 16
    NSGraphicsContext.saveGraphicsState()
    let boltShadow = NSShadow()
    boltShadow.shadowColor = NSColor(red: 0.75, green: 0.30, blue: 0.0, alpha: 0.45)
    boltShadow.shadowBlurRadius = 14
    boltShadow.shadowOffset = NSSize(width: 0, height: -6)
    boltShadow.set()
    NSColor.white.setFill()
    bolt.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.setStroke()
    bolt.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@2x.png"
        try render(size * scale).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
    }
}
let out = URL(fileURLWithPath: "Resources/AppIcon.icns")
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try task.run()
task.waitUntilExit()
try render(512).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("icon-preview.png"))
print("Wrote \(out.path)")
