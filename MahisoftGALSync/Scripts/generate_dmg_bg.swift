#!/usr/bin/env swift
// Scripts/generate_dmg_bg.swift
// Generates a medium-grey background PNG for the DMG installer window.
// Uses CoreGraphics only — no AppKit/NSGraphicsContext needed.
// Usage: swift Scripts/generate_dmg_bg.swift <output_path>

import CoreGraphics
import ImageIO
import Foundation

guard CommandLine.arguments.count > 1 else {
    print("Usage: generate_dmg_bg.swift <output_path>"); exit(1)
}

let outputPath = CommandLine.arguments[1]
let width  = 560
let height = 300

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { print("ERROR: CGContext"); exit(1) }

// Medium grey fill (0.55 = ~140/255)
ctx.setFillColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)  // white
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

guard let image = ctx.makeImage() else { print("ERROR: makeImage"); exit(1) }

let url = URL(fileURLWithPath: outputPath) as CFURL
guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else {
    print("ERROR: CGImageDestination"); exit(1)
}
CGImageDestinationAddImage(dest, image, nil)
guard CGImageDestinationFinalize(dest) else { print("ERROR: finalize"); exit(1) }

print("  Background PNG: \(outputPath)")
