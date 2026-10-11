import CFFmpeg
import Foundation

/// Decoded interleaved Float32 audio.
public struct AudioFrame: Sendable {
    public let pts: Double
    public let sampleRate: Int
    public let channels: Int
    /// WAVE-style channel mask (same bit layout as CoreAudio's AudioChannelBitmap), 0 if unknown.
    public let channelMask: UInt64
    public let frameCount: Int
    public let samples: Data

    public var duration: Double { Double(frameCount) / Double(sampleRate) }
}

/// Decodes any FFmpeg-supported audio codec to interleaved Float32, keeping the channel layout
/// (up to 8 channels).
final class AudioDecoder {
    private var codec: UnsafeMutablePointer<AVCodecContext>?
    private var resampler: OpaquePointer?
    private var frame: UnsafeMutablePointer<AVFrame>?
    private let timeBase: AVRational
    private let offset: Double
    private var outLayout = AVChannelLayout()
    private var configured: (rate: Int32, format: Int32, channels: Int32)?
    private var nextPTS: Double?

    init(parameters: UnsafePointer<AVCodecParameters>, timeBase: AVRational, timelineOffset: Double) throws {
        self.timeBase = timeBase
        self.offset = timelineOffset
        guard let decoder = avcodec_find_decoder(parameters.pointee.codec_id) else {
            throw FFmpegError(cff_averror_invaliddata(), "no audio decoder for \(parameters.pointee.codec_id)")
        }
        codec = avcodec_alloc_context3(decoder)
        try check(avcodec_parameters_to_context(codec, parameters), "audio parameters")
        codec!.pointee.pkt_timebase = timeBase
        try check(avcodec_open2(codec, decoder, nil), "open audio decoder")
        frame = av_frame_alloc()
    }

    deinit {
        avcodec_free_context(&codec)
        swr_free(&resampler)
        av_frame_free(&frame)
        av_channel_layout_uninit(&outLayout)
    }

    /// Decodes one packet into zero or more frames. Corrupt packets are skipped.
    func decode(_ packet: Packet) -> [AudioFrame] {
        guard let codec, let frame else { return [] }
        if avcodec_send_packet(codec, packet.pointer) < 0 { return [] }
        var output: [AudioFrame] = []
        while avcodec_receive_frame(codec, frame) >= 0 {
            if let converted = convert(frame) { output.append(converted) }
            av_frame_unref(frame)
        }
        return output
    }

    func flush() {
        if let codec { avcodec_flush_buffers(codec) }
        nextPTS = nil
    }

    private func convert(_ frame: UnsafeMutablePointer<AVFrame>) -> AudioFrame? {
        let rate = frame.pointee.sample_rate
        let format = frame.pointee.format
        var inLayout = frame.pointee.ch_layout
        let channels = min(Int32(8), inLayout.nb_channels)
        guard rate > 0, channels > 0 else { return nil }

        if configured == nil || configured! != (rate, format, inLayout.nb_channels) {
            swr_free(&resampler)
            av_channel_layout_uninit(&outLayout)
            if inLayout.order == AV_CHANNEL_ORDER_NATIVE && inLayout.nb_channels <= 8 {
                av_channel_layout_copy(&outLayout, &inLayout)
            } else {
                av_channel_layout_default(&outLayout, channels)
            }
            guard swr_alloc_set_opts2(&resampler, &outLayout, AV_SAMPLE_FMT_FLT, rate,
                                      &inLayout, AVSampleFormat(format), rate, 0, nil) >= 0,
                  swr_init(resampler) >= 0 else {
                swr_free(&resampler)
                return nil
            }
            configured = (rate, format, inLayout.nb_channels)
        }

        let outChannels = Int(outLayout.nb_channels)
        let capacity = Int(swr_get_out_samples(resampler, frame.pointee.nb_samples))
        guard capacity > 0 else { return nil }
        var data = Data(count: capacity * outChannels * MemoryLayout<Float>.size)
        let produced: Int32 = data.withUnsafeMutableBytes { raw in
            var out: UnsafeMutablePointer<UInt8>? = raw.baseAddress!.assumingMemoryBound(to: UInt8.self)
            return withUnsafeMutablePointer(to: &out) { outPtr in
                frame.withMemoryRebound(to: AVFrame.self, capacity: 1) { f in
                    let inputs = UnsafeMutableRawPointer(f.pointee.extended_data!)
                        .assumingMemoryBound(to: UnsafePointer<UInt8>?.self)
                    return swr_convert(resampler, outPtr, Int32(capacity), inputs, f.pointee.nb_samples)
                }
            }
        }
        guard produced > 0 else { return nil }
        data.count = Int(produced) * outChannels * MemoryLayout<Float>.size

        let pts = seconds(frame.pointee.best_effort_timestamp, timeBase).map { $0 + offset } ?? nextPTS ?? 0
        let result = AudioFrame(pts: pts, sampleRate: Int(rate), channels: outChannels,
                                channelMask: outLayout.order == AV_CHANNEL_ORDER_NATIVE ? outLayout.u.mask : 0,
                                frameCount: Int(produced), samples: data)
        nextPTS = pts + result.duration
        return result
    }
}
