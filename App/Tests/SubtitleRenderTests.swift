import AppKit
import PlayerCore
import SwiftUI
import XCTest
@testable import TinyJellyfin

@MainActor
final class SubtitleRenderTests: XCTestCase {
    /// Renders the overlay offscreen and returns the rows (from the top) that contain white text.
    private func textRows(video: CGSize?, bars: PictureBars? = nil, canvas: CGSize) -> ClosedRange<Int>? {
        let renderer = ImageRenderer(content: SubtitleOverlay(text: "Hello", videoSize: video, bars: bars)
            .frame(width: canvas.width, height: canvas.height).background(Color.black))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { XCTFail("no image"); return nil }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var rows: [Int] = []
        for y in 0..<h {
            for x in 0..<w where pixels[(y * w + x) * 4] > 200 { rows.append(y); break }
        }
        return rows.isEmpty ? nil : rows.min()!...rows.max()!
    }

    private func assertText(_ rows: ClosedRange<Int>?, insideBottomOf picture: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        guard let rows else { return XCTFail("no text drawn", file: file, line: line) }
        XCTAssertLessThan(Double(rows.upperBound), picture.maxY - picture.height * 0.05,
                          "text ends above the picture's bottom edge (rows \(rows))", file: file, line: line)
        XCTAssertGreaterThan(Double(rows.lowerBound), picture.maxY - picture.height * 0.2,
                             "but not far above it (rows \(rows))", file: file, line: line)
    }

    func testTextSitsInsideALetterboxedPicture() {
        let canvas = CGSize(width: 1920, height: 1080), video = CGSize(width: 2390, height: 1000)
        assertText(textRows(video: video, canvas: canvas), insideBottomOf: SubtitleLayout.pictureRect(video: video, in: canvas))
    }

    func testTextSitsAboveBarsEncodedInTheFrame() {
        let canvas = CGSize(width: 1920, height: 1080), video = CGSize(width: 1920, height: 1080)
        let bars = PictureBars(top: 0.128, bottom: 0.128)
        let rows = textRows(video: video, bars: bars, canvas: canvas)
        assertText(rows, insideBottomOf: SubtitleLayout.pictureRect(video: video, in: canvas, bars: bars))
        XCTAssertLessThan(Double(rows!.upperBound), 1080 * (1 - 0.128), "no text in the bar")
    }

    func testTextSitsAboveTheBottomOfAFittingWindow() {
        let canvas = CGSize(width: 1280, height: 720)
        assertText(textRows(video: CGSize(width: 1920, height: 1080), canvas: canvas), insideBottomOf: CGRect(x: 0, y: 0, width: 1280, height: 720))
    }
}
