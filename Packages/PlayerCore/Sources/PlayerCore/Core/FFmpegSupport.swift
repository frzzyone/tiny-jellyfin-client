import CFFmpeg
import Foundation

public struct FFmpegError: LocalizedError, CustomStringConvertible, Equatable {
    public let code: Int32
    public let context: String

    init(_ code: Int32, _ context: String) {
        self.code = code
        self.context = context
    }

    public var description: String { "\(context): \(Self.message(code)) (\(code))" }
    public var errorDescription: String? { "\(context): \(Self.message(code))" }

    static func message(_ code: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        av_strerror(code, &buffer, buffer.count)
        return String(cString: buffer)
    }

    var isEOF: Bool { code == cff_averror_eof() }
    var isExit: Bool { code == cff_averror_exit() }
    var isAgain: Bool { code == cff_averror_eagain() }
}

@discardableResult
func check(_ code: Int32, _ context: @autoclosure () -> String) throws -> Int32 {
    if code < 0 { throw FFmpegError(code, context()) }
    return code
}

let noPTS = cff_nopts_value()

extension AVRational {
    var seconds: Double { den == 0 ? 0 : Double(num) / Double(den) }
}

/// Converts a stream timestamp to seconds, nil when unset.
func seconds(_ ts: Int64, _ timeBase: AVRational) -> Double? {
    ts == noPTS ? nil : Double(ts) * timeBase.seconds
}

func string(_ pointer: UnsafePointer<CChar>?) -> String? {
    pointer.map { String(cString: $0) }
}

func dictionaryValue(_ dict: OpaquePointer?, _ key: String) -> String? {
    guard let dict, let entry = av_dict_get(dict, key, nil, 0) else { return nil }
    return string(entry.pointee.value)
}

/// Thread-safe flag shared between a reader and whoever wants to interrupt it.
final class InterruptFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ newValue: Bool) { lock.lock(); value = newValue; lock.unlock() }
}

/// Quiet FFmpeg's console logging unless debugging.
public enum FFmpegLog {
    public static func configure(verbose: Bool = false) {
        av_log_set_level(verbose ? AV_LOG_INFO : AV_LOG_ERROR)
    }
}
