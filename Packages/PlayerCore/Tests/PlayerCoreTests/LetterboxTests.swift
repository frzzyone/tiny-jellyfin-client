#if canImport(AVFoundation)
import CoreVideo
import XCTest
@testable import PlayerCore

final class LetterboxTests: XCTestCase {
    /// A biplanar frame, 8-bit or 10-bit-in-16, black except for picture rows between the bars.
    /// `noise` lights one column in the bars, as a stray bright pixel would.
    private func frame(width: Int = 640, height: Int = 360, top: Int, bottom: Int, wide: Bool = false,
                       level: UInt16 = 128, noise: Bool = false) -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let format = wide ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        XCTAssertEqual(CVPixelBufferCreate(nil, width, height, format, nil, &buffer), kCVReturnSuccess)
        let frame = buffer!
        CVPixelBufferLockBaseAddress(frame, [])
        let stride = CVPixelBufferGetBytesPerRowOfPlane(frame, 0)
        let base = CVPixelBufferGetBaseAddressOfPlane(frame, 0)!
        for row in 0..<height {
            let picture = row >= top && row < height - bottom
            for x in 0..<width {
                let value: UInt16 = picture ? level : (noise && x == 8 ? 200 : 16)
                if wide {
                    base.assumingMemoryBound(to: UInt16.self)[row * stride / 2 + x] = value << 8
                } else {
                    base.assumingMemoryBound(to: UInt8.self)[row * stride + x] = UInt8(value)
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(frame, [])
        return frame
    }

    func testFindsBarsInEightBitFrames() {
        XCTAssertEqual(LetterboxDetector.bars(in: frame(top: 45, bottom: 45)), PictureBars(top: 0.125, bottom: 0.125))
        XCTAssertEqual(LetterboxDetector.bars(in: frame(top: 0, bottom: 0)), PictureBars(top: 0, bottom: 0))
        XCTAssertEqual(LetterboxDetector.bars(in: frame(top: 36, bottom: 0)), PictureBars(top: 0.1, bottom: 0))
    }

    func testFindsBarsInTenBitFrames() {
        XCTAssertEqual(LetterboxDetector.bars(in: frame(top: 45, bottom: 45, wide: true)), PictureBars(top: 0.125, bottom: 0.125))
    }

    func testDimPictureStillCounts() {
        XCTAssertEqual(LetterboxDetector.bars(in: frame(top: 45, bottom: 45, level: 40)), PictureBars(top: 0.125, bottom: 0.125))
    }

    func testStrayPixelsInTheBarsAreIgnored() {
        XCTAssertEqual(LetterboxDetector.bars(in: frame(top: 45, bottom: 45, noise: true)), PictureBars(top: 0.125, bottom: 0.125))
    }

    func testMostlyBlackFrameSaysNothing() {
        XCTAssertNil(LetterboxDetector.bars(in: frame(top: 170, bottom: 170)), "a sliver of picture is a fade, not a bar")
        XCTAssertNil(LetterboxDetector.bars(in: frame(top: 360, bottom: 0)), "all black")
    }
}
#endif
