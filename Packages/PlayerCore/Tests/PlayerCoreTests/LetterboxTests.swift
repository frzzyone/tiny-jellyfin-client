#if canImport(AVFoundation)
import CoreVideo
import XCTest
@testable import PlayerCore

final class LetterboxTests: XCTestCase {
    let detector = LetterboxDetector()

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
        XCTAssertEqual(detector.bars(in: frame(top: 45, bottom: 45)), PictureBars(top: 0.125, bottom: 0.125))
        XCTAssertEqual(detector.bars(in: frame(top: 0, bottom: 0)), PictureBars(top: 0, bottom: 0))
        XCTAssertEqual(detector.bars(in: frame(top: 36, bottom: 0)), PictureBars(top: 0.1, bottom: 0))
    }

    func testFindsBarsInTenBitFrames() {
        XCTAssertEqual(detector.bars(in: frame(top: 45, bottom: 45, wide: true)), PictureBars(top: 0.125, bottom: 0.125))
    }

    func testDimPictureStillCounts() {
        XCTAssertEqual(detector.bars(in: frame(top: 45, bottom: 45, level: 40)), PictureBars(top: 0.125, bottom: 0.125))
    }

    func testStrayPixelsInTheBarsAreIgnored() {
        XCTAssertEqual(detector.bars(in: frame(top: 45, bottom: 45, noise: true)), PictureBars(top: 0.125, bottom: 0.125))
    }

    func testOnlyKnownRowLayoutsAreReadDirectly() {
        var threePlane: CVPixelBuffer?
        CVPixelBufferCreate(nil, 64, 64, kCVPixelFormatType_420YpCbCr8Planar, nil, &threePlane)
        XCTAssertFalse(LetterboxDetector.canRead(threePlane!), "not in the list, not read as rows")
        var compressed: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        if CVPixelBufferCreate(nil, 640, 360, kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarVideoRange, attributes, &compressed) == kCVReturnSuccess {
            XCTAssertFalse(LetterboxDetector.canRead(compressed!), "the layout that crashed the app is never read as rows")
            _ = detector.bars(in: compressed!) // undefined content; must not crash
        }
        XCTAssertTrue(LetterboxDetector.canRead(frame(top: 0, bottom: 0)))
        XCTAssertTrue(LetterboxDetector.canRead(frame(top: 0, bottom: 0, wide: true)))
    }

    private func bgraFrame(top: Int, bottom: Int) -> CVPixelBuffer {
        var packed: CVPixelBuffer?
        CVPixelBufferCreate(nil, 1280, 720, kCVPixelFormatType_32BGRA, nil, &packed)
        let frame = packed!
        CVPixelBufferLockBaseAddress(frame, [])
        let stride = CVPixelBufferGetBytesPerRow(frame)
        let base = CVPixelBufferGetBaseAddress(frame)!.assumingMemoryBound(to: UInt8.self)
        for row in 0..<720 {
            let value: UInt8 = row >= top && row < 720 - bottom ? 128 : 0
            for x in 0..<1280 {
                base[row * stride + x * 4] = value; base[row * stride + x * 4 + 1] = value
                base[row * stride + x * 4 + 2] = value; base[row * stride + x * 4 + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(frame, [])
        return frame
    }

    /// A packed BGRA frame is not readable as luma rows, so it goes through VideoToolbox's copy.
    func testOtherLayoutsAreCopiedBeforeScanning() {
        let frame = bgraFrame(top: 90, bottom: 90)
        XCTAssertFalse(LetterboxDetector.canRead(frame))
        let copy = detector.readableCopy(of: frame)
        XCTAssertEqual(copy.map { CVPixelBufferGetWidth($0) }, 320)
        XCTAssertEqual(copy.map { CVPixelBufferGetHeight($0) }, 180)
        guard let bars = detector.bars(in: frame) else { return XCTFail("no bars") }
        XCTAssertEqual(bars.top, 0.125, accuracy: 0.01)
        XCTAssertEqual(bars.bottom, 0.125, accuracy: 0.01)
        XCTAssertEqual(detector.bars(in: bgraFrame(top: 0, bottom: 0)), PictureBars(top: 0, bottom: 0),
                       "scaling the copy must not darken its edge rows")
    }

    func testMostlyBlackFrameSaysNothing() {
        XCTAssertNil(detector.bars(in: frame(top: 170, bottom: 170)), "a sliver of picture is a fade, not a bar")
        XCTAssertNil(detector.bars(in: frame(top: 360, bottom: 0)), "all black")
    }
}
#endif
