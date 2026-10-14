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

    /// A PGS box at (100,120)–(140,140) on a 320×180 canvas, drawn on a 4:3 view showing 16:9
    /// video: it lands at that spot of the letterboxed picture, scaled with it.
    func testPictureSubtitleIsPlacedOnTheFrame() {
        let (xs, ys) = pictureSubtitlePixels(bars: nil)
        // Picture: 640×360 at y 60. Scale 2: the box spans x 200–280, y 60+240–60+280.
        XCTAssertEqual(Double(xs.min() ?? -1), 200, accuracy: 2)
        XCTAssertEqual(Double(xs.max() ?? -1), 279, accuracy: 2)
        XCTAssertEqual(Double(ys.min() ?? -1), 300, accuracy: 2)
        XCTAssertEqual(Double(ys.max() ?? -1), 339, accuracy: 2)
        XCTAssertEqual(pictureSubtitlePixels(bars: PictureBars(top: 0.1, bottom: 0.1)).ys, ys, "clear of the bars: where the disc put it")
    }

    /// The same box inside a bottom bar of a quarter of the frame (canvas rows 135–180) rises to end
    /// 3% of the frame above it: canvas row 129.6, view row 60 + 259.
    func testPictureSubtitleSitsAboveBarsEncodedInTheFrame() {
        let (xs, ys) = pictureSubtitlePixels(bars: PictureBars(top: 0.25, bottom: 0.25))
        XCTAssertEqual(Double(ys.max() ?? -1), 318, accuracy: 2)
        XCTAssertEqual(Double(ys.min() ?? -1), 279, accuracy: 2)
        XCTAssertEqual(Double(xs.min() ?? -1), 200, accuracy: 2, "only raised")
    }

    /// White pixels of a 40×20 PGS box at (100,120) on a 320×180 canvas, drawn on a 4:3 view
    /// showing 16:9 video.
    private func pictureSubtitlePixels(bars: PictureBars?) -> (xs: [Int], ys: [Int]) {
        let white: UInt32 = 0xFFFF_FFFF
        let piece = SubtitleBitmap.Piece(x: 100, y: 120, width: 40, height: 20,
                                         indices: [UInt8](repeating: 1, count: 800), palette: [0, white])
        let bitmap = SubtitleBitmap(start: 0, end: 5, canvasWidth: 320, canvasHeight: 180, pieces: [piece])
        let renderer = ImageRenderer(content: SubtitleOverlay(text: nil, bitmap: bitmap, videoSize: CGSize(width: 1920, height: 1080), bars: bars)
            .frame(width: 640, height: 480).background(Color.black))
        renderer.scale = 1
        guard let cg = renderer.cgImage else { XCTFail("no image"); return ([], []) }
        let w = cg.width, h = cg.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var xs: [Int] = [], ys: [Int] = []
        for y in 0..<h { for x in 0..<w where pixels[(y * w + x) * 4] > 200 { xs.append(x); ys.append(y) } }
        return (xs, ys)
    }

    func testTextSitsAboveTheBottomOfAFittingWindow() {
        let canvas = CGSize(width: 1280, height: 720)
        assertText(textRows(video: CGSize(width: 1920, height: 1080), canvas: canvas), insideBottomOf: CGRect(x: 0, y: 0, width: 1280, height: 720))
    }
}
