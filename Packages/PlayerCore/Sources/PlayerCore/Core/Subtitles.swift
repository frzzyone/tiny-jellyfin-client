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
