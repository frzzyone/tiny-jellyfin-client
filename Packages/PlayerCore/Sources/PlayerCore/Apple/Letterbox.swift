#if canImport(AVFoundation)
import CoreVideo
import Foundation
import VideoToolbox

/// Black bars encoded into the video frames, as fractions of the frame height.
public struct PictureBars: Equatable, Sendable {
    public var top: Double
    public var bottom: Double

    public init(top: Double, bottom: Double) {
        self.top = top
        self.bottom = bottom
    }

    /// The smaller bar on each edge: a dark scene can only make bars look bigger, never smaller.
    public func narrowed(by other: PictureBars) -> PictureBars {
        PictureBars(top: min(top, other.top), bottom: min(bottom, other.bottom))
    }
}

/// Finds letterbox bars in a decoded frame by scanning its luma plane for the first and last
/// rows that hold anything brighter than video black. Frames in a layout that cannot be read as
/// rows (VideoToolbox's compressed buffers, packed RGB) are first copied, small, into a plain
/// 4:2:0 buffer by VideoToolbox.
public final class LetterboxDetector {
    /// Luma, on an 8-bit scale, above which a sample counts as picture. Video black is 16 and
    /// compression noise in the bars stays well under this.
    static let threshold: UInt16 = 32
    /// A row is picture when at least this share of its sampled columns are above the threshold.
    static let minimumShare = 0.02
    static let columnStep = 8
    /// Frames darker than this (fade to black, a credits card) say nothing about the bars.
    static let minimumPictureShare = 0.3
    /// Width of the readable copy; its rows give the bars to better than 1% of the height.
    static let copyWidth = 320

    private var transfer: VTPixelTransferSession?

    public init() {}

    /// Bi-planar formats whose first plane is plain rows of 8-bit luma.
    static let eightBitFormats: Set<OSType> = [
        kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_422YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_422YpCbCr8BiPlanarFullRange,
        kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_444YpCbCr8BiPlanarFullRange,
    ]
    /// Bi-planar formats whose first plane is rows of 16-bit samples with the significant bits at the top.
    static let wideFormats: Set<OSType> = [
        kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_422YpCbCr10BiPlanarFullRange,
        kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_444YpCbCr10BiPlanarFullRange,
    ]

    /// Whether the frame's memory can be read as rows. Only the formats above are: the lossless
    /// and lossy compressed layouts VideoToolbox also produces are smaller than rows × stride, and
    /// reading them as rows walks off the end of the mapping.
    public static func canRead(_ buffer: CVPixelBuffer) -> Bool {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        return (eightBitFormats.contains(format) || wideFormats.contains(format)) && CVPixelBufferGetPlaneCount(buffer) >= 2
    }

    public func bars(in buffer: CVPixelBuffer) -> PictureBars? {
        if Self.canRead(buffer) { return Self.scan(buffer) }
        guard let copy = readableCopy(of: buffer) else { return nil }
        return Self.scan(copy)
    }

    /// A small plain 4:2:0 copy of a frame in any other layout, made by VideoToolbox.
    func readableCopy(of buffer: CVPixelBuffer) -> CVPixelBuffer? {
        if transfer == nil { VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer) }
        guard let transfer else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        let w = min(Self.copyWidth, width)
        let h = max(2, (height * w / width) / 2 * 2)
        var copy: CVPixelBuffer?
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, attributes, &copy) == kCVReturnSuccess,
              let copy, VTPixelTransferSessionTransferImage(transfer, from: buffer, to: copy) == noErr else { return nil }
        return copy
    }

    static func scan(_ buffer: CVPixelBuffer) -> PictureBars? {
        guard canRead(buffer) else { return nil }
        let wide = wideFormats.contains(CVPixelBufferGetPixelFormatType(buffer))
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width >= columnStep, height > 0, stride >= width * (wide ? 2 : 1) else { return nil }
        let columns = stride / (wide ? 2 : 1)
        let needed = max(2, Int(Double(width / columnStep) * minimumShare))

        func isPicture(row: Int) -> Bool {
            var lit = 0
            if wide {
                let samples = base.assumingMemoryBound(to: UInt16.self).advanced(by: row * columns)
                for x in Swift.stride(from: 0, to: width, by: columnStep) where samples[x] >> 8 > threshold {
                    lit += 1
                    if lit >= needed { return true }
                }
            } else {
                let samples = base.assumingMemoryBound(to: UInt8.self).advanced(by: row * stride)
                for x in Swift.stride(from: 0, to: width, by: columnStep) where UInt16(samples[x]) > threshold {
                    lit += 1
                    if lit >= needed { return true }
                }
            }
            return false
        }

        guard let first = (0..<height).first(where: isPicture), let last = (0..<height).last(where: isPicture) else { return nil }
        guard Double(last - first + 1) >= Double(height) * minimumPictureShare else { return nil }
        return PictureBars(top: Double(first) / Double(height), bottom: Double(height - 1 - last) / Double(height))
    }
}
#endif
