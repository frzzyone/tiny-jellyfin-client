#!/bin/bash
# Renders App/Resources/AppIcon.svg into the PNGs of AppIcon.appiconset (and the Apple TV icon
# layers and Top Shelf images into TV.xcassets) with the system SVG
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
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 1024, height: 1024)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
// Opaque: fill the tile colour edge to edge, then draw the mark over it.
NSColor(srgbRed: 0x23 / 255.0, green: 0x28 / 255.0, blue: 0x2f / 255.0, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 1024, height: 1024).fill()
ios.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024), from: .zero, operation: .sourceOver, fraction: 1)
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

# Apple TV: a layered icon (graphite back, the amber mark in front, so the focus parallax moves the
# mark over the tile) and the Top Shelf images, in their own catalog for the TV target.
TV=App/Resources/TV.xcassets
BRAND="$TV/App Icon & Top Shelf Image.brandassets"
rm -rf "$TV"
for stack in "App Icon" "App Icon - App Store"; do
  for layer in Back Front; do mkdir -p "$BRAND/$stack.imagestack/$layer.imagestacklayer/Content.imageset"; done
done
mkdir -p "$BRAND/Top Shelf Image.imageset" "$BRAND/Top Shelf Image Wide.imageset"
swift - "$BRAND" <<'SWIFT'
import AppKit
let brand = CommandLine.arguments[1]
let mark = NSImage(contentsOf: URL(fileURLWithPath: "App/Resources/Assets.xcassets/Mark.imageset/Mark.svg"))!
let graphite = NSColor(srgbRed: 0x23 / 255.0, green: 0x28 / 255.0, blue: 0x2f / 255.0, alpha: 1)
/// A w×h PNG: graphite (or clear) with the mark centred at `markHeight` of the height.
func render(_ w: Int, _ h: Int, back: Bool, markHeight: Double?, to path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: w, height: h)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    if back { graphite.setFill(); NSRect(x: 0, y: 0, width: w, height: h).fill() }
    if let markHeight {
        let side = Double(h) * markHeight
        mark.draw(in: NSRect(x: (Double(w) - side) / 2, y: (Double(h) - side) / 2, width: side, height: side),
                  from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
for (stack, sizes) in [("App Icon", [(400, 240, "1x"), (800, 480, "2x")]), ("App Icon - App Store", [(1280, 768, "1x")])] {
    for (w, h, scale) in sizes {
        render(w, h, back: true, markHeight: nil, to: "\(brand)/\(stack).imagestack/Back.imagestacklayer/Content.imageset/back_\(scale).png")
        render(w, h, back: false, markHeight: 0.62, to: "\(brand)/\(stack).imagestack/Front.imagestacklayer/Content.imageset/front_\(scale).png")
    }
}
for (set, w) in [("Top Shelf Image", 1920), ("Top Shelf Image Wide", 2320)] {
    render(w, 720, back: true, markHeight: 0.3, to: "\(brand)/\(set).imageset/shelf_1x.png")
    render(w * 2, 1440, back: true, markHeight: 0.3, to: "\(brand)/\(set).imageset/shelf_2x.png")
}
SWIFT
info='"info" : { "author" : "xcode", "version" : 1 }'
echo "{ $info }" > "$TV/Contents.json"
cat > "$BRAND/Contents.json" <<JSON
{
  "assets" : [
    { "filename" : "App Icon - App Store.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "1280x768" },
    { "filename" : "App Icon.imagestack", "idiom" : "tv", "role" : "primary-app-icon", "size" : "400x240" },
    { "filename" : "Top Shelf Image Wide.imageset", "idiom" : "tv", "role" : "top-shelf-image-wide", "size" : "2320x720" },
    { "filename" : "Top Shelf Image.imageset", "idiom" : "tv", "role" : "top-shelf-image", "size" : "1920x720" }
  ],
  $info
}
JSON
for stack in "App Icon" "App Icon - App Store"; do
  echo "{ \"layers\" : [ { \"filename\" : \"Front.imagestacklayer\" }, { \"filename\" : \"Back.imagestacklayer\" } ], $info }" \
    > "$BRAND/$stack.imagestack/Contents.json"
  for layer in Back Front; do
    echo "{ $info }" > "$BRAND/$stack.imagestack/$layer.imagestacklayer/Contents.json"
    lower=$(echo $layer | tr A-Z a-z)
    if [[ "$stack" == "App Icon" ]]; then
      images="{ \"filename\" : \"${lower}_1x.png\", \"idiom\" : \"tv\", \"scale\" : \"1x\" }, { \"filename\" : \"${lower}_2x.png\", \"idiom\" : \"tv\", \"scale\" : \"2x\" }"
    else
      images="{ \"filename\" : \"${lower}_1x.png\", \"idiom\" : \"tv\", \"scale\" : \"1x\" }"
    fi
    echo "{ \"images\" : [ $images ], $info }" > "$BRAND/$stack.imagestack/$layer.imagestacklayer/Content.imageset/Contents.json"
  done
done
for set in "Top Shelf Image" "Top Shelf Image Wide"; do
  echo "{ \"images\" : [ { \"filename\" : \"shelf_1x.png\", \"idiom\" : \"tv\", \"scale\" : \"1x\" }, { \"filename\" : \"shelf_2x.png\", \"idiom\" : \"tv\", \"scale\" : \"2x\" } ], $info }" \
    > "$BRAND/$set.imageset/Contents.json"
done
echo "wrote $TV"
