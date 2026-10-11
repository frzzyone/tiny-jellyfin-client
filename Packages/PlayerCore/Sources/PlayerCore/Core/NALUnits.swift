import Foundation

/// H.264/HEVC bitstream helpers: Annex B detection and conversion to 4-byte length prefixes,
/// parameter-set extraction, and Dolby Vision enhancement-layer stripping.
public enum NALUnits {
    public enum Codec { case h264, hevc }

    /// True when the buffer starts with an Annex B start code.
    public static func isAnnexB(_ data: UnsafeBufferPointer<UInt8>) -> Bool {
        guard data.count >= 4 else { return false }
        return (data[0] == 0 && data[1] == 0 && data[2] == 1)
            || (data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1)
    }

    /// Splits an Annex B stream into NAL unit payloads (without start codes).
    public static func splitAnnexB(_ data: UnsafeBufferPointer<UInt8>) -> [ArraySlice<UInt8>] {
        let bytes = Array(data)
        var units: [ArraySlice<UInt8>] = []
        var i = 0, start = -1
        while i + 2 < bytes.count {
            if bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1 {
                if start >= 0 {
                    var end = i
                    while end > start && bytes[end - 1] == 0 { end -= 1 }
                    if end > start { units.append(bytes[start..<end]) }
                }
                i += 3
                start = i
            } else {
                i += 1
            }
        }
        if start >= 0 && start < bytes.count { units.append(bytes[start..<bytes.count]) }
        return units
    }

    /// Splits a length-prefixed buffer into NAL unit payloads.
    public static func splitLengthPrefixed(_ data: UnsafeBufferPointer<UInt8>, lengthSize: Int = 4) -> [ArraySlice<UInt8>] {
        let bytes = Array(data)
        var units: [ArraySlice<UInt8>] = []
        var i = 0
        while i + lengthSize <= bytes.count {
            var length = 0
            for k in 0..<lengthSize { length = (length << 8) | Int(bytes[i + k]) }
            i += lengthSize
            guard length > 0, i + length <= bytes.count else { break }
            units.append(bytes[i..<(i + length)])
            i += length
        }
        return units
    }

    public static func joinLengthPrefixed(_ units: [ArraySlice<UInt8>]) -> Data {
        var out = Data(capacity: units.reduce(0) { $0 + $1.count + 4 })
        for unit in units {
            let n = UInt32(unit.count)
            out.append(contentsOf: [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)])
            out.append(contentsOf: unit)
        }
        return out
    }

    public static func type(of unit: ArraySlice<UInt8>, codec: Codec) -> Int {
        guard let first = unit.first else { return -1 }
        return codec == .h264 ? Int(first & 0x1F) : Int((first >> 1) & 0x3F)
    }

    /// Parameter sets in decoding order: H.264 SPS(7), PPS(8); HEVC VPS(32), SPS(33), PPS(34).
    public static func parameterSets(_ units: [ArraySlice<UInt8>], codec: Codec) -> [ArraySlice<UInt8>] {
        let order = codec == .h264 ? [7, 8] : [32, 33, 34]
        return order.compactMap { wanted in units.first { type(of: $0, codec: codec) == wanted } }
    }

    /// Parameter-set NAL units stored in an avcC or hvcC configuration record.
    public static func parameterSets(fromConfigurationRecord record: Data, codec: Codec) -> [ArraySlice<UInt8>] {
        let b = [UInt8](record)
        var units: [ArraySlice<UInt8>] = []
        func u16(_ i: Int) -> Int { Int(b[i]) << 8 | Int(b[i + 1]) }
        switch codec {
        case .h264:
            guard b.count >= 7, b[0] == 1 else { return [] }
            var i = 6
            for _ in 0..<Int(b[5] & 0x1F) {
                guard i + 2 <= b.count else { return units }
                let n = u16(i); i += 2
                guard i + n <= b.count else { return units }
                units.append(b[i..<(i + n)]); i += n
            }
            guard i < b.count else { return units }
            let ppsCount = Int(b[i]); i += 1
            for _ in 0..<ppsCount {
                guard i + 2 <= b.count else { return units }
                let n = u16(i); i += 2
                guard i + n <= b.count else { return units }
                units.append(b[i..<(i + n)]); i += n
            }
        case .hevc:
            guard b.count >= 23, b[0] == 1 else { return [] }
            var i = 23
            for _ in 0..<Int(b[22]) {
                guard i + 3 <= b.count else { return units }
                let count = u16(i + 1); i += 3
                for _ in 0..<count {
                    guard i + 2 <= b.count else { return units }
                    let n = u16(i); i += 2
                    guard i + n <= b.count else { return units }
                    units.append(b[i..<(i + n)]); i += n
                }
            }
        }
        return parameterSets(units, codec: codec)
    }

    /// Luma bit depth recorded in an hvcC record.
    public static func hevcBitDepth(fromConfigurationRecord record: Data) -> Int? {
        let b = [UInt8](record)
        guard b.count >= 23, b[0] == 1 else { return nil }
        return Int(b[17] & 0x07) + 8
    }

    /// Removes Dolby Vision Profile 7 enhancement-layer NAL units (HEVC types 63) so the
    /// HDR10 base layer decodes as plain HEVC. RPU units (type 62) are dropped too when `dropRPU`.
    public static func stripDolbyVisionEL(_ units: [ArraySlice<UInt8>], dropRPU: Bool) -> [ArraySlice<UInt8>] {
        units.filter {
            let t = type(of: $0, codec: .hevc)
            return t != 63 && !(dropRPU && t == 62)
        }
    }
}
