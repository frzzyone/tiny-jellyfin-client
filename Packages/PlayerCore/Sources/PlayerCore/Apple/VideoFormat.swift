#if canImport(AVFoundation)
import CoreMedia
import Foundation

/// Builds the CoreMedia description of a video stream, including HDR and Dolby Vision signalling.
struct VideoFormat {
    let description: CMVideoFormatDescription
    /// Packets arrive as Annex B and must be converted to 4-byte length prefixes.
    let convertAnnexB: Bool
    /// Dolby Vision Profile 7: drop enhancement-layer NAL units, play the HDR10 base layer.
    let stripEnhancementLayer: Bool
    let codec: NALUnits.Codec?
    let usesDolbyVision: Bool

    enum Failure: Error { case unsupportedCodec(String), missingParameterSets, coreMedia(OSStatus) }

    /// - Parameters:
    ///   - firstKeyframe: needed when the stream has no configuration record (MPEG-TS).
    ///   - allowDolbyVision: false to fall back to the HDR10/SDR base layer.
    static func make(_ info: VideoStreamInfo, firstKeyframe: UnsafeBufferPointer<UInt8>?,
                     allowDolbyVision: Bool) throws -> VideoFormat {
        let nalCodec: NALUnits.Codec?
        switch info.codec {
        case .h264: nalCodec = .h264
        case .hevc: nalCodec = .hevc
        case .av1: nalCodec = nil
        case .other(let name): throw Failure.unsupportedCodec(name)
        }

        let dv = info.dolbyVision
        let profile = dv?.profile ?? 0
        let useDV = allowDolbyVision && info.codec == .hevc && (profile == 5 || profile == 8)
        let stripEL = info.codec == .hevc && profile == 7

        var extensions = colorExtensions(info.color)
        if abs(info.sampleAspectRatio - 1) > 0.001 {
            // Anamorphic content: the renderer stretches to the right shape instead of the UI.
            let (h, v) = pixelAspectRatio(info.sampleAspectRatio)
            extensions[kCMFormatDescriptionExtension_PixelAspectRatio as String] = [
                kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing as String: h,
                kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing as String: v,
            ]
        }
        if info.hasConfigurationRecord, let nalCodec {
            // Containers often omit colour info; CoreMedia reads it from the SPS VUI.
            for (key, value) in inferredColorExtensions(info.extradata, codec: nalCodec) where extensions[key] == nil {
                extensions[key] = value
            }
        }
        if info.hasConfigurationRecord {
            var atoms: [String: Any] = [:]
            switch info.codec {
            case .h264: atoms["avcC"] = info.extradata
            case .hevc: atoms["hvcC"] = info.extradata
            case .av1: atoms["av1C"] = info.extradata
            case .other: break
            }
            if useDV, let dv { atoms[dv.boxType] = dv.boxPayload }
            extensions[kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms as String] = atoms
            let codecType: CMVideoCodecType
            switch info.codec {
            case .h264: codecType = kCMVideoCodecType_H264
            case .hevc: codecType = useDV ? kCMVideoCodecType_DolbyVisionHEVC : kCMVideoCodecType_HEVC
            case .av1: codecType = kCMVideoCodecType_AV1
            case .other(let name): throw Failure.unsupportedCodec(name)
            }
            var description: CMVideoFormatDescription?
            let status = CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault, codecType: codecType,
                                                        width: Int32(info.width), height: Int32(info.height),
                                                        extensions: extensions as CFDictionary,
                                                        formatDescriptionOut: &description)
            guard status == noErr, let description else { throw Failure.coreMedia(status) }
            return VideoFormat(description: description, convertAnnexB: false, stripEnhancementLayer: stripEL,
                               codec: nalCodec, usesDolbyVision: useDV)
        }

        // Annex B (MPEG-TS): parameter sets come from extradata or the first keyframe.
        guard let nalCodec else { throw Failure.missingParameterSets }
        var units: [ArraySlice<UInt8>] = []
        info.extradata.withUnsafeBytes { raw in
            let buffer = raw.bindMemory(to: UInt8.self)
            if NALUnits.isAnnexB(buffer) { units += NALUnits.splitAnnexB(buffer) }
        }
        if let firstKeyframe, NALUnits.isAnnexB(firstKeyframe) { units += NALUnits.splitAnnexB(firstKeyframe) }
        let sets = NALUnits.parameterSets(units, codec: nalCodec)
        guard sets.count == (nalCodec == .h264 ? 2 : 3) else { throw Failure.missingParameterSets }
        let arrays = sets.map { Array($0) }
        var description: CMFormatDescription?
        let status: OSStatus = withPointers(arrays) { pointers, sizes in
            switch nalCodec {
            case .h264:
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: arrays.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            case .hevc:
                return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: arrays.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: extensions as CFDictionary,
                    formatDescriptionOut: &description)
            }
        }
        guard status == noErr, let description else { throw Failure.coreMedia(status) }
        return VideoFormat(description: description, convertAnnexB: true, stripEnhancementLayer: stripEL,
                           codec: nalCodec, usesDolbyVision: false)
    }

    /// Converts a packet payload to what the decoder expects.
    func payload(_ data: UnsafeBufferPointer<UInt8>) -> Data {
        guard let codec, convertAnnexB || stripEnhancementLayer else { return Data(buffer: data) }
        var units = convertAnnexB && NALUnits.isAnnexB(data)
            ? NALUnits.splitAnnexB(data) : NALUnits.splitLengthPrefixed(data)
        if stripEnhancementLayer { units = NALUnits.stripDolbyVisionEL(units, dropRPU: true) }
        _ = codec
        return NALUnits.joinLengthPrefixed(units)
    }

    static let colorKeys: [CFString] = [
        kCMFormatDescriptionExtension_ColorPrimaries, kCMFormatDescriptionExtension_TransferFunction,
        kCMFormatDescriptionExtension_YCbCrMatrix, kCMFormatDescriptionExtension_FullRangeVideo,
    ]

    /// Colour extensions CoreMedia derives from the parameter sets in an avcC/hvcC record.
    static func inferredColorExtensions(_ record: Data, codec: NALUnits.Codec) -> [String: Any] {
        let arrays = NALUnits.parameterSets(fromConfigurationRecord: record, codec: codec).map { Array($0) }
        guard arrays.count == (codec == .h264 ? 2 : 3) else { return [:] }
        var description: CMFormatDescription?
        let status: OSStatus = withPointers(arrays) { pointers, sizes in
            switch codec {
            case .h264:
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: arrays.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &description)
            case .hevc:
                return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                    allocator: kCFAllocatorDefault, parameterSetCount: arrays.count, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, extensions: nil,
                    formatDescriptionOut: &description)
            }
        }
        guard status == noErr, let description else { return [:] }
        var result: [String: Any] = [:]
        for key in colorKeys {
            if let value = CMFormatDescriptionGetExtension(description, extensionKey: key) {
                result[key as String] = value
            }
        }
        return result
    }

    /// Integer horizontal/vertical spacing for a pixel aspect ratio.
    static func pixelAspectRatio(_ ratio: Double) -> (Int, Int) {
        for (h, v) in [(4, 3), (16, 11), (40, 33), (12, 11), (10, 11), (64, 45), (32, 27)]
        where abs(Double(h) / Double(v) - ratio) < 0.01 { return (h, v) }
        return (Int((ratio * 1000).rounded()), 1000)
    }

    static func colorExtensions(_ color: VideoColorInfo) -> [String: Any] {
        var ext: [String: Any] = [:]
        switch color.primaries {
        case 1: ext[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_ITU_R_709_2
        case 9: ext[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_ITU_R_2020
        case 5: ext[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_EBU_3213
        case 6, 7: ext[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_SMPTE_C
        case 12: ext[kCMFormatDescriptionExtension_ColorPrimaries as String] = kCMFormatDescriptionColorPrimaries_P3_D65
        default: break
        }
        switch color.transfer {
        case 1, 6, 14, 15: ext[kCMFormatDescriptionExtension_TransferFunction as String] = kCMFormatDescriptionTransferFunction_ITU_R_709_2
        case 16: ext[kCMFormatDescriptionExtension_TransferFunction as String] = kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ
        case 18: ext[kCMFormatDescriptionExtension_TransferFunction as String] = kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG
        default: break
        }
        switch color.matrix {
        case 1: ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] = kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2
        case 9, 10: ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] = kCMFormatDescriptionYCbCrMatrix_ITU_R_2020
        case 5, 6: ext[kCMFormatDescriptionExtension_YCbCrMatrix as String] = kCMFormatDescriptionYCbCrMatrix_ITU_R_601_4
        default: break
        }
        if color.fullRange { ext[kCMFormatDescriptionExtension_FullRangeVideo as String] = true }
        if let mdcv = color.masteringDisplay {
            ext[kCMFormatDescriptionExtension_MasteringDisplayColorVolume as String] = mdcv
        }
        if let clli = color.contentLightLevel {
            ext[kCMFormatDescriptionExtension_ContentLightLevelInfo as String] = clli
        }
        return ext
    }

    private static func withPointers<R>(_ arrays: [[UInt8]],
                                        _ body: (UnsafePointer<UnsafePointer<UInt8>>, UnsafePointer<Int>) -> R) -> R {
        let buffers = arrays.map { array -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: array.count)
            p.initialize(from: array, count: array.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = arrays.map(\.count)
        return pointers.withUnsafeBufferPointer { p in
            sizes.withUnsafeBufferPointer { s in body(p.baseAddress!, s.baseAddress!) }
        }
    }
}
#endif
