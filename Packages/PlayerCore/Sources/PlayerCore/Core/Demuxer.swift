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

    /// Opens the container and reads its stream info.
    ///
    /// - Parameter seekBeforeProbe: position the input here before `find_stream_info`, so probing
    ///   reads the target instead of the start of the stream. For segmented formats (HLS) that is
    ///   the difference between making the server transcode the start of the item as well as the
    ///   part we want. Probing consumes packets, so unsegmented inputs are repositioned afterwards
    ///   (a cheap range request); segmented ones are not, and begin at the first packet probing
    ///   left behind.
    func open(seekBeforeProbe: Double? = nil) throws {
        do {
            try openInput(seekBeforeProbe: seekBeforeProbe)
        } catch {
            // Report what the server said rather than FFmpeg's "interrupted" or "I/O error".
            throw io.ioFailure ?? error
        }
    }

    private func openInput(seekBeforeProbe: Double?) throws {
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
        // MPEG-TS has no header, so it keeps the defaults unless we have already positioned the
        // input (`seekBeforeProbe`), in which case probing reads the segment we are about to play.
        let ext = url.pathExtension.lowercased()
        let container = ["ts", "m2ts", "mts"].contains(ext)
        let segmented = ext == "m3u8"
        if !container && (!segmented || (seekBeforeProbe ?? 0) > 0.5) {
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
        if let target = seekBeforeProbe, target > 0.5 {
            let seekStart = Date()
            try? seek(to: target)
            PlayerLog.engine(String(format: "Pre-probe seek to %.1f s in %.2f s", target,
                                    Date().timeIntervalSince(seekStart)))
        }
        let probeStart = Date()
        try check(avformat_find_stream_info(ctx, nil), "find stream info")
        PlayerLog.engine("Probed \(url.lastPathComponent) in \(String(format: "%.2f", Date().timeIntervalSince(probeStart))) s")
        if let target = seekBeforeProbe, target > 0.5, !isSegmented {
            try? seek(to: target)
        }
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

    func clearInterrupt() {
        io.clearFailure()
        io.interrupt.set(false)
    }

    func setTimelineOffset(_ offset: Double) { timelineOffset = offset }

    /// True for formats served as separate segments, where seeking costs a new fetch (and, with a
    /// transcoding server, new encoding work) rather than a range request.
    var isSegmented: Bool { formatName == "hls" }

    /// Whether FFmpeg may seek the main input directly.
    var isSeekable: Bool {
        guard let pb = context?.pointee.pb else { return false }
        return pb.pointee.seekable & AVIO_SEEKABLE_NORMAL != 0
    }

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
            if let failure = io.ioFailure { throw failure }
            throw FFmpegError(result, "read")
        }
        let timeBase = ctx.pointee.streams[Int(packet.pointee.stream_index)]!.pointee.time_base
        return Packet(taking: packet, timeBase: timeBase, offset: timelineOffset)
    }

    /// Seeks to the keyframe at or before `time` (item timeline seconds).
    ///
    /// Segmented inputs seek in playlist time, not packet time: FFmpeg's HLS demuxer picks the
    /// segment by adding up the playlist's durations from 0 (item time) and only afterwards compares
    /// packet timestamps, so `timelineOffset` must not be applied to the target. When the packets
    /// are stamped later than the playlist says (Jellyfin's are, by 10 s) the whole segment is
    /// returned, including the part before the target; the engine hides that lead-in.
    func seek(to time: Double) throws {
        guard let ctx = context else { return }
        let streamTime = isSegmented ? time : time - timelineOffset
        let target = Int64(max(0, streamTime) * Double(AV_TIME_BASE))
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
