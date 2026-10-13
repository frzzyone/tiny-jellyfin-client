import CFFmpeg
import Foundation

public struct SubtitleCue: Sendable, Equatable {
    public let start: Double
    public let end: Double
    public let text: String

    public init(start: Double, end: Double, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

/// Cues of one track, kept sorted by start time; thread-safe.
public final class SubtitleTrackStore: @unchecked Sendable {
    private let lock = NSLock()
    private var cues: [SubtitleCue] = []

    public init(cues: [SubtitleCue] = []) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    func add(_ cue: SubtitleCue) {
        lock.lock(); defer { lock.unlock() }
        // Packets usually arrive in order; insert keeping the array sorted.
        if let last = cues.last, last.start <= cue.start {
            if last == cue { return }
            cues.append(cue)
        } else {
            let index = cues.firstIndex { $0.start > cue.start } ?? cues.count
            if index > 0 && cues[index - 1] == cue { return }
            cues.insert(cue, at: index)
        }
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return cues.count }

    /// Text of every cue visible at `time`, joined top to bottom.
    public func text(at time: Double) -> String? {
        lock.lock(); defer { lock.unlock() }
        // Binary search for the first cue starting after `time`, then scan back over overlaps.
        var low = 0, high = cues.count
        while low < high {
            let mid = (low + high) / 2
            if cues[mid].start <= time { low = mid + 1 } else { high = mid }
        }
        var visible: [SubtitleCue] = []
        var index = low - 1
        while index >= 0 && visible.count < 4 {
            let cue = cues[index]
            if cue.end > time { visible.append(cue) }
            if time - cue.start > 30 { break }
            index -= 1
        }
        guard !visible.isEmpty else { return nil }
        return visible.reversed().map(\.text).joined(separator: "\n")
    }
}

/// A picture subtitle (Blu-ray PGS, DVD, DVB): palette images placed on the video frame.
public struct SubtitleBitmap: Sendable, Equatable {
    public struct Piece: Sendable, Equatable {
        public let x: Int, y: Int, width: Int, height: Int
        /// One palette index per pixel, `width` per row. Kept indexed: a quarter of the memory of RGBA.
        let indices: [UInt8]
        /// 0xAARRGGBB, not premultiplied.
        let palette: [UInt32]

        public init(x: Int, y: Int, width: Int, height: Int, indices: [UInt8], palette: [UInt32]) {
            (self.x, self.y, self.width, self.height) = (x, y, width, height)
            self.indices = indices
            self.palette = palette
        }

        /// Pixels as 0xAARRGGBB words (BGRA bytes in memory on little-endian machines).
        public func argb() -> [UInt32] {
            indices.map { Int($0) < palette.count ? palette[Int($0)] : 0 }
        }
    }

    public let start: Double
    /// `.infinity` until the next event (or a clear) says when it ends: PGS gives no end time.
    public internal(set) var end: Double
    /// The frame the pieces are placed on, the subtitle stream's own size (usually 1920×1080).
    public let canvasWidth: Int, canvasHeight: Int
    public let pieces: [Piece]

    public init(start: Double, end: Double, canvasWidth: Int, canvasHeight: Int, pieces: [Piece]) {
        self.start = start
        self.end = end
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.pieces = pieces
    }
}

/// Picture subtitles of one track, sorted by start; thread-safe. Holds the most recently
/// decoded events only (they are re-decoded after a seek back), so a film doesn't pile up.
public final class BitmapSubtitleStore: @unchecked Sendable {
    static let capacity = 80
    private let lock = NSLock()
    private var events: [SubtitleBitmap] = []
    private var added: [Double] = []

    public init() {}

    /// An event, or a clear (`nil`) at `time`. Either ends the open event before it.
    func add(_ bitmap: SubtitleBitmap?, at time: Double) {
        lock.lock(); defer { lock.unlock() }
        if let open = events.lastIndex(where: { $0.start < time }), events[open].end > time {
            events[open].end = time
        }
        guard var bitmap else { return }
        if let next = events.first(where: { $0.start > bitmap.start }), bitmap.end > next.start { bitmap.end = next.start }
        events.removeAll { $0.start == bitmap.start }
        added.removeAll { $0 == bitmap.start }
        let index = events.firstIndex { $0.start > bitmap.start } ?? events.count
        events.insert(bitmap, at: index)
        added.append(bitmap.start)
        if added.count > Self.capacity {
            let oldest = added.removeFirst()
            events.removeAll { $0.start == oldest }
        }
    }

    public var count: Int { lock.lock(); defer { lock.unlock() }; return events.count }

    public func bitmap(at time: Double) -> SubtitleBitmap? {
        lock.lock(); defer { lock.unlock() }
        guard let index = events.lastIndex(where: { $0.start <= time }) else { return nil }
        return events[index].end > time ? events[index] : nil
    }
}

/// Converts decoded ASS event lines into plain text.
public enum ASSText {
    /// `ass` is either a full "Dialogue:" line or FFmpeg's decoded event
    /// "ReadOrder,Layer,Style,Name,MarginL,MarginR,MarginV,Effect,Text".
    public static func plainText(fromEvent ass: String) -> String {
        var line = ass
        if line.hasPrefix("Dialogue:") {
            line = String(line.dropFirst("Dialogue:".count))
            // Dialogue: Layer,Start,End,Style,Name,MarginL,MarginR,MarginV,Effect,Text
            line = field(line, after: 9)
        } else {
            line = field(line, after: 8)
        }
        return plainText(fromText: line)
    }

    /// Strips override blocks and drawings, converts \N, \n and \h.
    public static func plainText(fromText text: String) -> String {
        var result = ""
        var drawing = false
        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]
            if ch == "{", let close = text[index...].firstIndex(of: "}") {
                let block = text[text.index(after: index)..<close]
                if let range = block.range(of: #"\\p(\d+)"#, options: .regularExpression) {
                    let level = Int(block[range].dropFirst(2)) ?? 0
                    drawing = level > 0
                }
                index = text.index(after: close)
                continue
            }
            if ch == "\\", text.index(after: index) < text.endIndex {
                let next = text[text.index(after: index)]
                if next == "N" || next == "n" {
                    if !drawing { result.append("\n") }
                    index = text.index(index, offsetBy: 2)
                    continue
                }
                if next == "h" {
                    if !drawing { result.append(" ") }
                    index = text.index(index, offsetBy: 2)
                    continue
                }
            }
            if !drawing { result.append(ch) }
            index = text.index(after: index)
        }
        return result.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private static func field(_ line: String, after commas: Int) -> String {
        var seen = 0
        for index in line.indices where line[index] == "," {
            seen += 1
            if seen == commas { return String(line[line.index(after: index)...]) }
        }
        return line
    }
}

/// Decodes text subtitle packets (SRT, ASS/SSA, WebVTT, mov_text) into plain-text cues.
final class SubtitleDecoder {
    private var codec: UnsafeMutablePointer<AVCodecContext>?
    private let timeBase: AVRational
    private let offset: Double

    init(parameters: UnsafePointer<AVCodecParameters>, timeBase: AVRational, timelineOffset: Double) throws {
        self.timeBase = timeBase
        self.offset = timelineOffset
        guard let decoder = avcodec_find_decoder(parameters.pointee.codec_id) else {
            throw FFmpegError(cff_averror_invaliddata(), "no subtitle decoder")
        }
        codec = avcodec_alloc_context3(decoder)
        try check(avcodec_parameters_to_context(codec, parameters), "subtitle parameters")
        codec!.pointee.pkt_timebase = timeBase
        try check(avcodec_open2(codec, decoder, nil), "open subtitle decoder")
    }

    deinit { avcodec_free_context(&codec) }

    /// Picture subtitles: the event the packet completes, or a clear. nil when it completes none.
    func decodePicture(_ packet: Packet) -> (time: Double, bitmap: SubtitleBitmap?)? {
        guard let codec else { return nil }
        var subtitle = AVSubtitle()
        var got: Int32 = 0
        guard avcodec_decode_subtitle2(codec, &subtitle, &got, packet.pointer) >= 0, got != 0 else { return nil }
        defer { avsubtitle_free(&subtitle) }
        let start = (packet.pts ?? 0) + Double(subtitle.start_display_time) / 1000
        let end = subtitle.end_display_time > 0 && subtitle.end_display_time != UInt32.max
            ? (packet.pts ?? 0) + Double(subtitle.end_display_time) / 1000
            : .infinity
        var pieces: [SubtitleBitmap.Piece] = []
        for i in 0..<Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee, rect.type == SUBTITLE_BITMAP, rect.w > 0, rect.h > 0,
                  let data = rect.data.0, let paletteData = rect.data.1 else { continue }
            let width = Int(rect.w), height = Int(rect.h), stride = Int(rect.linesize.0)
            var indices = [UInt8](repeating: 0, count: width * height)
            for row in 0..<height {
                for column in 0..<width { indices[row * width + column] = data[row * stride + column] }
            }
            let colors = max(0, min(256, Int(rect.nb_colors)))
            let palette = paletteData.withMemoryRebound(to: UInt32.self, capacity: colors) { Array(UnsafeBufferPointer(start: $0, count: colors)) }
            pieces.append(.init(x: Int(rect.x), y: Int(rect.y), width: width, height: height, indices: indices, palette: palette))
        }
        guard !pieces.isEmpty else { return (start, nil) }
        let canvasWidth = codec.pointee.width > 0 ? Int(codec.pointee.width) : 1920
        let canvasHeight = codec.pointee.height > 0 ? Int(codec.pointee.height) : 1080
        return (start, SubtitleBitmap(start: start, end: end, canvasWidth: canvasWidth, canvasHeight: canvasHeight,
                                      pieces: pieces))
    }

    func decode(_ packet: Packet) -> [SubtitleCue] {
        guard let codec else { return [] }
        var subtitle = AVSubtitle()
        var got: Int32 = 0
        guard avcodec_decode_subtitle2(codec, &subtitle, &got, packet.pointer) >= 0, got != 0 else { return [] }
        defer { avsubtitle_free(&subtitle) }
        let start = (packet.pts ?? 0) + Double(subtitle.start_display_time) / 1000
        var end = subtitle.end_display_time > 0 && subtitle.end_display_time != UInt32.max
            ? (packet.pts ?? 0) + Double(subtitle.end_display_time) / 1000
            : start + packet.duration
        if end <= start { end = start + 4 }
        var lines: [String] = []
        for i in 0..<Int(subtitle.num_rects) {
            guard let rect = subtitle.rects[i]?.pointee else { continue }
            if let ass = rect.ass {
                lines.append(ASSText.plainText(fromEvent: String(cString: ass)))
            } else if let text = rect.text {
                lines.append(String(cString: text))
            }
        }
        let text = lines.filter { !$0.isEmpty }.joined(separator: "\n")
        return text.isEmpty ? [] : [SubtitleCue(start: start, end: end, text: text)]
    }
}

public enum ExternalSubtitles {
    /// Parses a subtitle file (SRT, ASS, WebVTT…) into cues using FFmpeg's demuxers and decoders.
    public static func parse(_ data: Data, fileExtension: String = "srt") throws -> [SubtitleCue] {
        let factory = SingleSourceFactory(source: DataByteSource(data))
        let demuxer = Demuxer(url: URL(string: "memory://subtitle.\(fileExtension)")!, factory: factory)
        try demuxer.open()
        defer { demuxer.close() }
        guard let track = demuxer.tracks.first(where: { $0.kind == .subtitle }),
              let stream = demuxer.stream(track.id) else { return [] }
        let decoder = try SubtitleDecoder(parameters: stream.pointee.codecpar, timeBase: stream.pointee.time_base,
                                          timelineOffset: 0)
        var cues: [SubtitleCue] = []
        while let packet = try demuxer.readPacket() {
            if packet.streamIndex == track.id { cues += decoder.decode(packet) }
        }
        return cues.sorted { $0.start < $1.start }
    }
}

/// Factory that serves one in-memory source for the main URL.
final class SingleSourceFactory: ByteSourceFactory {
    let source: ByteSource
    init(source: ByteSource) { self.source = source }
    func open(url: URL) throws -> ByteSource { source }
}
