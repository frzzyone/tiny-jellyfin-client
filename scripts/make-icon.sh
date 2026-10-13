#!/bin/bash
# Renders App/Resources/AppIcon.svg into the PNGs of AppIcon.appiconset with the system SVG
# renderer (no third-party tools). Run after editing the SVG; the PNGs are checked in.
set -euo pipefail
cd "$(dirname "$0")/.."
SET=App/Resources/Assets.xcassets/AppIcon.appiconset
swift - <<'SWIFT'
import AppKit
let svg = URL(fileURLWithPath: "App/Resources/AppIcon.svg")
guard let image = NSImage(contentsOf: svg) else { fatalError("cannot read AppIcon.svg") }
for px in [16, 32, 64, 128, 256, 512, 1024] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: px, height: px)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    let png = rep.representation(using: .png, properties: [:])!
    try! png.write(to: URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset/icon_\(px).png"))
}
// iOS masks the icon itself: a square, opaque, full-bleed 1024 without our rounded tile.
let square = try! String(contentsOf: svg, encoding: .utf8).replacingOccurrences(of: "rx=\"230\"", with: "")
let squareURL = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-ios.svg")
try! square.write(to: squareURL, atomically: true, encoding: .utf8)
let ios = NSImage(contentsOf: squareURL)!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 1024, height: 1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
ios.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero, operation: .copy, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: "App/Resources/Assets.xcassets/AppIcon.appiconset/icon_ios_1024.png"))
SWIFT
cat > "$SET/Contents.json" <<'JSON'
{
  "images" : [
    { "filename" : "icon_ios_1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
    { "filename" : "icon_16.png",   "idiom" : "mac", "scale" : "1x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "2x", "size" : "16x16" },
    { "filename" : "icon_32.png",   "idiom" : "mac", "scale" : "1x", "size" : "32x32" },
    { "filename" : "icon_64.png",   "idiom" : "mac", "scale" : "2x", "size" : "32x32" },
    { "filename" : "icon_128.png",  "idiom" : "mac", "scale" : "1x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "2x", "size" : "128x128" },
    { "filename" : "icon_256.png",  "idiom" : "mac", "scale" : "1x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "2x", "size" : "256x256" },
    { "filename" : "icon_512.png",  "idiom" : "mac", "scale" : "1x", "size" : "512x512" },
    { "filename" : "icon_1024.png", "idiom" : "mac", "scale" : "2x", "size" : "512x512" }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
JSON
cat > App/Resources/Assets.xcassets/Contents.json <<'JSON'
{ "info" : { "author" : "xcode", "version" : 1 } }
JSON
echo "wrote $(ls "$SET" | wc -l | tr -d ' ') files to $SET"
