#!/usr/bin/env swift
// Scripts/generate_icon.swift
// Generates AppIcon.appiconset PNG files using AppKit + SF Symbols.
// Run from the MahisoftGALSync/ directory: swift Scripts/generate_icon.swift

import AppKit
import Foundation

// Bootstrap AppKit so SF Symbol rendering works in a CLI context
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

struct IconSize {
    let points: Int
    let scale: Int
    var pixels: Int { points * scale }
    var filename: String { "AppIcon-\(points)x\(points)@\(scale)x.png" }
}

let sizes = [
    IconSize(points: 16,  scale: 1),
    IconSize(points: 16,  scale: 2),
    IconSize(points: 32,  scale: 1),
    IconSize(points: 32,  scale: 2),
    IconSize(points: 128, scale: 1),
    IconSize(points: 128, scale: 2),
    IconSize(points: 256, scale: 1),
    IconSize(points: 256, scale: 2),
    IconSize(points: 512, scale: 1),
    IconSize(points: 512, scale: 2),
]

// Locate the appiconset directory relative to this script's location
let scriptURL = URL(fileURLWithPath: #file)
let projectRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let iconSetURL = projectRoot
    .appendingPathComponent("Sources/Resources/Assets.xcassets/AppIcon.appiconset")

func renderIcon(pixels: Int) -> NSBitmapImageRep? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    let cgCtx = ctx.cgContext

    let rect = CGRect(origin: .zero, size: CGSize(width: pixels, height: pixels))

    // macOS squircle corner radius (~22.4% of size)
    let r = CGFloat(pixels) * 0.224
    let path = CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
    cgCtx.addPath(path)
    cgCtx.clip()

    // Blue gradient background (top: bright, bottom: deeper)
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let topColor    = CGColor(colorSpace: sRGB, components: [0.24, 0.53, 0.98, 1.0])!
    let bottomColor = CGColor(colorSpace: sRGB, components: [0.09, 0.33, 0.78, 1.0])!
    let gradient = CGGradient(
        colorsSpace: sRGB,
        colors: [topColor, bottomColor] as CFArray,
        locations: [0.0, 1.0]
    )!
    cgCtx.drawLinearGradient(
        gradient,
        start: CGPoint(x: CGFloat(pixels) / 2, y: CGFloat(pixels)),
        end:   CGPoint(x: CGFloat(pixels) / 2, y: 0),
        options: []
    )

    // SF Symbol: person.2.fill in white, centered
    // pointSize ≈ 38% of pixel dimension gives good proportions
    let ptSize = CGFloat(pixels) * 0.38
    let symConfig = NSImage.SymbolConfiguration(pointSize: ptSize, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "person.2.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(symConfig) {

        // Tint the template symbol white
        let tinted = NSImage(size: symbol.size)
        tinted.lockFocus()
        NSColor.white.withAlphaComponent(0.95).set()
        CGRect(origin: .zero, size: symbol.size).fill()
        symbol.draw(in: CGRect(origin: .zero, size: symbol.size),
                    from: .zero,
                    operation: .destinationIn,
                    fraction: 1.0)
        tinted.unlockFocus()

        // Center horizontally, nudge slightly above center vertically
        let x = (CGFloat(pixels) - tinted.size.width)  / 2
        let y = (CGFloat(pixels) - tinted.size.height) / 2 - CGFloat(pixels) * 0.02
        tinted.draw(at: NSPoint(x: x, y: y),
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Generate each size
var generated: [String] = []
for iconSize in sizes {
    print("  \(iconSize.pixels)×\(iconSize.pixels)px (\(iconSize.points)pt @\(iconSize.scale)x)...", terminator: "")
    guard let rep = renderIcon(pixels: iconSize.pixels),
          let png = rep.representation(using: .png, properties: [:]) else {
        print(" FAILED")
        continue
    }
    let dest = iconSetURL.appendingPathComponent(iconSize.filename)
    do {
        try png.write(to: dest)
        generated.append(iconSize.filename)
        print(" ok")
    } catch {
        print(" ERROR: \(error.localizedDescription)")
    }
}

// Update Contents.json
let images = sizes.map { s -> [String: Any] in
    [
        "filename": s.filename,
        "idiom": "mac",
        "scale": "\(s.scale)x",
        "size": "\(s.points)x\(s.points)"
    ]
}
let contents: [String: Any] = [
    "images": images,
    "info": ["author": "xcode", "version": 1]
]

let jsonData = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
let contentsURL = iconSetURL.appendingPathComponent("Contents.json")
try jsonData.write(to: contentsURL)

print("  Contents.json updated")
print("  Generated \(generated.count)/\(sizes.count) icons")
