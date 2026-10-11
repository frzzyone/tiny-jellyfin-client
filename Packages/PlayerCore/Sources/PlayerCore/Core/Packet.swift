import CFFmpeg
import Foundation

/// An owned demuxed packet with timing in seconds on the media timeline.
final class Packet: @unchecked Sendable {
    let pointer: UnsafeMutablePointer<AVPacket>
    let streamIndex: Int
    /// Presentation/decode time in seconds, already shifted onto the media timeline.
    let pts: Double?
    let dts: Double?
    let duration: Double
    let isKeyframe: Bool

    init(taking pointer: UnsafeMutablePointer<AVPacket>, timeBase: AVRational, offset: Double) {
        self.pointer = pointer
        streamIndex = Int(pointer.pointee.stream_index)
        pts = seconds(pointer.pointee.pts, timeBase).map { $0 + offset }
        dts = seconds(pointer.pointee.dts, timeBase).map { $0 + offset }
        duration = Double(max(0, pointer.pointee.duration)) * timeBase.seconds
        isKeyframe = (pointer.pointee.flags & AV_PKT_FLAG_KEY) != 0
    }

    deinit {
        var p: UnsafeMutablePointer<AVPacket>? = pointer
        av_packet_free(&p)
    }

    var data: UnsafeBufferPointer<UInt8> {
        UnsafeBufferPointer(start: pointer.pointee.data, count: Int(pointer.pointee.size))
    }

    var size: Int { Int(pointer.pointee.size) }

    /// Best-known time for ordering: pts, else dts.
    var time: Double { pts ?? dts ?? 0 }

    var hasTimestamp: Bool { pts != nil || dts != nil }
}
