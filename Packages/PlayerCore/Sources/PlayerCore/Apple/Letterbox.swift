#if canImport(AVFoundation)
import CoreVideo
import Foundation

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
/// rows that hold anything brighter than video black.
public enum LetterboxDetector {
    /// Luma, on an 8-bit scale, above which a sample counts as picture. Video black is 16 and
    /// compression noise in the bars stays well under this.
    static let threshold: UInt16 = 32
    /// A row is picture when at least this share of its sampled columns are above the threshold.
    static let minimumShare = 0.02
    static let columnStep = 8
    /// Frames darker than this (fade to black, a credits card) say nothing about the bars.
    static let minimumPictureShare = 0.3

    public static func bars(in buffer: CVPixelBuffer) -> PictureBars? {
        guard CVPixelBufferIsPlanar(buffer), CVPixelBufferGetPlaneCount(buffer) >= 2 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return nil }
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        guard width >= columnStep, height > 0 else { return nil }
        // 10/16-bit planes keep the significant bits at the top of each 16-bit sample.
        let wide = stride >= width * 2
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
