import CFFmpeg
import Foundation

/// Everything needed to describe a video stream to the platform decoder.
public struct VideoStreamInfo: Sendable, Equatable {
    public enum Codec: Sendable, Equatable { case h264, hevc, av1, other(String) }

    public var codec: Codec
    public var width: Int
    public var height: Int
    /// avcC / hvcC / av1C payload as stored in MP4/MKV (empty for Annex B streams).
    public var extradata: Data
    public var color: VideoColorInfo
    public var dolbyVision: DolbyVisionConfig?
    public var bitDepth: Int
    /// Pixel aspect ratio (width/height of one pixel); 1 for square pixels, ≠ 1 for anamorphic.
    public var sampleAspectRatio: Double = 1
    /// Frames per second from the container (see `frameRate(average:real:)`), nil if it doesn't say.
    public var frameRate: Double?

    /// The size the picture should be shown at, with non-square pixels accounted for.
    public var presentationSize: CGSize {
        CGSize(width: Double(width) * sampleAspectRatio, height: Double(height))
    }

    /// True when extradata is a configuration record rather than Annex B parameter sets.
    public var hasConfigurationRecord: Bool {
        guard let first = extradata.first else { return false }
        switch codec {
        case .h264, .hevc: return first == 1
        case .av1: return first & 0x80 != 0
        case .other: return false
        }
    }
}

extension VideoStreamInfo {
    init(parameters par: UnsafePointer<AVCodecParameters>) {
        let p = par.pointee
        switch p.codec_id {
        case AV_CODEC_ID_H264: codec = .h264
        case AV_CODEC_ID_HEVC: codec = .hevc
        case AV_CODEC_ID_AV1: codec = .av1
        default: codec = .other(string(avcodec_get_name(p.codec_id)) ?? "unknown")
        }
        width = Int(p.width)
        height = Int(p.height)
        let sar = p.sample_aspect_ratio
        sampleAspectRatio = sar.num > 0 && sar.den > 0 ? Double(sar.num) / Double(sar.den) : 1
        extradata = p.extradata.map { Data(bytes: $0, count: Int(p.extradata_size)) } ?? Data()
        // Without a video decoder in the FFmpeg build the pixel format may be unknown;
        // fall back to the hvcC record.
        if let descriptor = av_pix_fmt_desc_get(AVPixelFormat(p.format)) {
            bitDepth = Int(descriptor.pointee.comp.0.depth)
        } else if p.codec_id == AV_CODEC_ID_HEVC, let depth = NALUnits.hevcBitDepth(fromConfigurationRecord: extradata) {
            bitDepth = depth
        } else {
            bitDepth = 8
        }

        var color = VideoColorInfo()
        color.primaries = Int32(p.color_primaries.rawValue)
        color.transfer = Int32(p.color_trc.rawValue)
        color.matrix = Int32(p.color_space.rawValue)
        color.fullRange = p.color_range == AVCOL_RANGE_JPEG
        let sideData = p.coded_side_data
        let count = p.nb_coded_side_data
        if let sd = av_packet_side_data_get(sideData, count, AV_PKT_DATA_MASTERING_DISPLAY_METADATA) {
            let mdm = UnsafeRawPointer(sd.pointee.data).assumingMemoryBound(to: AVMasteringDisplayMetadata.self).pointee
            if mdm.has_primaries != 0 && mdm.has_luminance != 0 {
                color.masteringDisplay = Self.mdcv(mdm)
            }
        }
        if let sd = av_packet_side_data_get(sideData, count, AV_PKT_DATA_CONTENT_LIGHT_LEVEL) {
            let cll = UnsafeRawPointer(sd.pointee.data).assumingMemoryBound(to: AVContentLightMetadata.self).pointee
            color.contentLightLevel = Self.clli(maxCLL: cll.MaxCLL, maxFALL: cll.MaxFALL)
        }
        self.color = color

        if let sd = av_packet_side_data_get(sideData, count, AV_PKT_DATA_DOVI_CONF) {
            let r = UnsafeRawPointer(sd.pointee.data).assumingMemoryBound(to: AVDOVIDecoderConfigurationRecord.self).pointee
            dolbyVision = DolbyVisionConfig(versionMajor: r.dv_version_major, versionMinor: r.dv_version_minor,
                                            profile: r.dv_profile, level: r.dv_level,
                                            rpuPresent: r.rpu_present_flag != 0, elPresent: r.el_present_flag != 0,
                                            blPresent: r.bl_present_flag != 0,
                                            blSignalCompatibilityId: r.dv_bl_signal_compatibility_id)
        } else {
            dolbyVision = nil
        }
    }

    /// The stream's frame rate: the average rate, else FFmpeg's guess at the real one. Values no
    /// display could show (a 1/90000 time base read as a rate) mean "unknown".
    static func frameRate(average: AVRational, real: AVRational) -> Double? {
        for rate in [average, real] where rate.num > 0 && rate.den > 0 {
            let fps = Double(rate.num) / Double(rate.den)
            if fps >= 1 && fps <= 240 { return fps }
        }
        return nil
    }

    /// 24-byte mastering display colour volume in SEI order (G, B, R, white point, max, min).
    static func mdcv(_ m: AVMasteringDisplayMetadata) -> Data {
        func chroma(_ r: AVRational) -> UInt16 { UInt16(clamping: Int((r.seconds * 50_000).rounded())) }
        func luma(_ r: AVRational) -> UInt32 { UInt32(clamping: Int((r.seconds * 10_000).rounded())) }
        var out = Data()
        func put16(_ v: UInt16) { out.append(contentsOf: [UInt8(v >> 8), UInt8(v & 0xFF)]) }
        func put32(_ v: UInt32) { out.append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]) }
        // FFmpeg stores primaries as R, G, B; the SEI payload wants G, B, R.
        let primaries = m.display_primaries
        for p in [primaries.1, primaries.2, primaries.0] {
            put16(chroma(p.0))
            put16(chroma(p.1))
        }
        put16(chroma(m.white_point.0))
        put16(chroma(m.white_point.1))
        put32(luma(m.max_luminance))
        put32(luma(m.min_luminance))
        return out
    }

    static func clli(maxCLL: UInt32, maxFALL: UInt32) -> Data {
        let a = UInt16(clamping: maxCLL), b = UInt16(clamping: maxFALL)
        return Data([UInt8(a >> 8), UInt8(a & 0xFF), UInt8(b >> 8), UInt8(b & 0xFF)])
    }
}
