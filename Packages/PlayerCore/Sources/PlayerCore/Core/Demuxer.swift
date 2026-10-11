import CFFmpeg
import Foundation

/// Opens a container through `MediaIO` and reads packets.
/// Not thread-safe except `interrupt()`, which may be called from any thread.
final class Demuxer {
    private(set) var context: UnsafeMutablePointer<AVFormatContext>?
    let io: MediaIO
    let url: URL
    /// Added to every timestamp so positions match the item timeline.
    private(set) var timelineOffset: Double = 0
    private(set) var tracks: [MediaTrack] = []

    init(url: URL, factory: ByteSourceFactory) {
        self.url = url
        self.io = MediaIO(factory: factory, realScheme: url.scheme ?? "https")
    }

    deinit { close() }

    func open() throws {
        guard var ctx = avformat_alloc_context() else { throw FFmpegError(cff_averror_eio(), "alloc context") }
        io.install(on: ctx)
        let source: ByteSource
        do {
            source = try io.factory.open(url: url)
        } catch {
            avformat_free_context(ctx)
            throw error
        }
        guard let pb = io.makeContext(for: source) else {
            avformat_free_context(ctx)
            throw FFmpegError(cff_averror_eio(), "avio context")
        }
        ctx.pointee.pb = pb   // custom IO: FFmpeg won't free it, we do in close()
        var options: OpaquePointer?
        av_dict_set(&options, "http_persistent", "0", 0)
        av_dict_set(&options, "extension_picky", "0", 0)
        av_dict_set(&options, "seg_max_retry", "3", 0)
        // MKV/MP4 describe their streams in the header; with no video decoders in our FFmpeg
        // build, the default probing (5 MB / 5 s) mostly just downloads data before playback.
        // MPEG-TS/HLS has no header and keeps the defaults.
        let ext = url.pathExtension.lowercased()
        if !["m3u8", "ts", "m2ts", "mts"].contains(ext) {
            ctx.pointee.probesize = 2_000_000
            ctx.pointee.max_analyze_duration = 2 * Int64(AV_TIME_BASE)
        }
        var maybeCtx: UnsafeMutablePointer<AVFormatContext>? = ctx
        let result = avformat_open_input(&maybeCtx, MediaIO.ffmpegURL(for: url), nil, &options)
        av_dict_free(&options)
        guard result >= 0, let opened = maybeCtx else {
            MediaIO.freeContext(pb)
            io.closeAll()
            throw FFmpegError(result, "open \(url.lastPathComponent)")
        }
        ctx = opened
        context = ctx
        let probeStart = Date()
        try check(avformat_find_stream_info(ctx, nil), "find stream info")
        PlayerLog.engine("Probed \(url.lastPathComponent) in \(String(format: "%.2f", Date().timeIntervalSince(probeStart))) s")
        tracks = (0..<Int(ctx.pointee.nb_streams)).map { describe(stream: ctx.pointee.streams[$0]!) }
    }

    func close() {
        guard let ctx = context else { return }
        io.interrupt.set(true)
        let pb = ctx.pointee.pb
        var maybe: UnsafeMutablePointer<AVFormatContext>? = ctx
        avformat_close_input(&maybe)
        MediaIO.freeContext(pb)
        io.closeAll()
        context = nil
    }

    /// Interrupts a blocking read or seek from another thread.
    func interrupt() {
        io.interrupt.set(true)
        io.interruptReads()
    }

    func clearInterrupt() { io.interrupt.set(false) }

    func setTimelineOffset(_ offset: Double) { timelineOffset = offset }

    /// FFmpeg's name for the container format, e.g. "hls" or "matroska,webm".
    var formatName: String {
        guard let ctx = context, let format = ctx.pointee.iformat else { return "" }
        return String(cString: format.pointee.name)
    }

    var duration: Double? {
        guard let ctx = context, ctx.pointee.duration > 0 else { return nil }
        return Double(ctx.pointee.duration) / Double(AV_TIME_BASE)
    }

    var startTime: Double {
        guard let ctx = context, ctx.pointee.start_time != noPTS else { return 0 }
        return Double(ctx.pointee.start_time) / Double(AV_TIME_BASE)
    }

    func stream(_ index: Int) -> UnsafeMutablePointer<AVStream>? {
        guard let ctx = context, index >= 0, index < Int(ctx.pointee.nb_streams) else { return nil }
        return ctx.pointee.streams[index]
    }

    func codecParameters(_ index: Int) -> UnsafeMutablePointer<AVCodecParameters>? {
        stream(index)?.pointee.codecpar
    }

    func bestStream(_ type: AVMediaType) -> Int? {
        guard let ctx = context else { return nil }
        let index = av_find_best_stream(ctx, type, -1, -1, nil, 0)
        return index >= 0 ? Int(index) : nil
    }

    /// Reads the next packet. Returns nil at end of stream; throws on error or interruption.
    func readPacket() throws -> Packet? {
        guard let ctx = context else { return nil }
        guard let packet = av_packet_alloc() else { throw FFmpegError(cff_averror_eio(), "packet alloc") }
        let result = av_read_frame(ctx, packet)
        if result < 0 {
            var p: UnsafeMutablePointer<AVPacket>? = packet
            av_packet_free(&p)
            if result == cff_averror_eof() { return nil }
            throw FFmpegError(result, "read")
        }
        let timeBase = ctx.pointee.streams[Int(packet.pointee.stream_index)]!.pointee.time_base
        return Packet(taking: packet, timeBase: timeBase, offset: timelineOffset)
    }

    /// Seeks to the keyframe at or before `time` (media timeline seconds).
    func seek(to time: Double) throws {
        guard let ctx = context else { return }
        let target = Int64(max(0, time - timelineOffset) * Double(AV_TIME_BASE))
        try check(av_seek_frame(ctx, -1, target, AVSEEK_FLAG_BACKWARD), "seek")
    }

    private func describe(stream: UnsafeMutablePointer<AVStream>) -> MediaTrack {
        let par = stream.pointee.codecpar!.pointee
        let kind: TrackKind
        switch par.codec_type {
        case AVMEDIA_TYPE_VIDEO: kind = (stream.pointee.disposition & 0x400) != 0 ? .other : .video
        case AVMEDIA_TYPE_AUDIO: kind = .audio
        case AVMEDIA_TYPE_SUBTITLE: kind = .subtitle
        default: kind = .other
        }
        let metadata = stream.pointee.metadata
        let language = dictionaryValue(metadata, "language").flatMap { $0 == "und" ? nil : $0 }
        return MediaTrack(id: Int(stream.pointee.index), kind: kind,
                          codec: string(avcodec_get_name(par.codec_id)) ?? "unknown",
                          language: language, title: dictionaryValue(metadata, "title"),
                          isDefault: (stream.pointee.disposition & 0x1) != 0,
                          isForced: (stream.pointee.disposition & 0x40) != 0)
    }
}
