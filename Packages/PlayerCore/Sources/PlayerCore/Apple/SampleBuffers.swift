#if canImport(AVFoundation)
import AudioToolbox
import CoreMedia
import Foundation

enum SampleBuffers {
    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 90_000)
    }

    static func blockBuffer(_ data: Data) -> CMBlockBuffer? {
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                 blockLength: data.count, blockAllocator: kCFAllocatorDefault,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: data.count,
                                                 flags: 0, blockBufferOut: &block) == noErr,
              let block else { return nil }
        let status = data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                                          dataLength: data.count)
        }
        return status == noErr ? block : nil
    }

    /// One compressed video frame.
    static func video(_ data: Data, format: CMVideoFormatDescription, pts: Double, dts: Double?, duration: Double,
                      isKeyframe: Bool, doNotDisplay: Bool) -> CMSampleBuffer? {
        guard !data.isEmpty, let block = blockBuffer(data) else { return nil }
        var timing = CMSampleTimingInfo(duration: duration > 0 ? time(duration) : .invalid,
                                        presentationTimeStamp: time(pts),
                                        decodeTimeStamp: dts.map(time) ?? .invalid)
        var size = data.count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                                        sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                        sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if !isKeyframe || doNotDisplay,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            if !isKeyframe { set(dict, kCMSampleAttachmentKey_NotSync, true) }
            if doNotDisplay { set(dict, kCMSampleAttachmentKey_DoNotDisplay, true) }
        }
        return sample
    }

    private static func set(_ dict: CFMutableDictionary, _ key: CFString, _ value: Bool) {
        CFDictionarySetValue(dict, Unmanaged.passUnretained(key).toOpaque(),
                             Unmanaged.passUnretained(value ? kCFBooleanTrue : kCFBooleanFalse).toOpaque())
    }

    // MARK: Audio

    /// Format for AC-3 / E-AC-3 passthrough.
    static func dolbyFormat(eac3: Bool, sampleRate: Int, channels: Int) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate),
                                               mFormatID: eac3 ? kAudioFormatEnhancedAC3 : kAudioFormatAC3,
                                               mFormatFlags: 0, mBytesPerPacket: 0, mFramesPerPacket: 1536,
                                               mBytesPerFrame: 0, mChannelsPerFrame: UInt32(channels),
                                               mBitsPerChannel: 0, mReserved: 0)
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd, layoutSize: 0, layout: nil,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &format) == noErr else { return nil }
        return format
    }

    /// One compressed audio packet.
    static func compressedAudio(_ data: Data, format: CMAudioFormatDescription, pts: Double) -> CMSampleBuffer? {
        guard !data.isEmpty, let block = blockBuffer(data) else { return nil }
        var description = AudioStreamPacketDescription(mStartOffset: 0, mVariableFramesInPacket: 0,
                                                       mDataByteSize: UInt32(data.count))
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block,
                                                                   formatDescription: format, sampleCount: 1,
                                                                   presentationTimeStamp: time(pts),
                                                                   packetDescriptions: &description,
                                                                   sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }

    /// Format for interleaved Float32 PCM with a channel layout.
    static func pcmFormat(sampleRate: Int, channels: Int, channelMask: UInt64) -> CMAudioFormatDescription? {
        var asbd = AudioStreamBasicDescription(mSampleRate: Float64(sampleRate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: UInt32(4 * channels), mFramesPerPacket: 1,
                                               mBytesPerFrame: UInt32(4 * channels),
                                               mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var layout = AudioChannelLayout()
        switch (channels, channelMask) {
        case (1, _): layout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono
        case (2, 0), (2, 0x3): layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        case (_, 0): layout.mChannelLayoutTag = kAudioChannelLayoutTag_DiscreteInOrder | UInt32(channels)
        default:
            // FFmpeg's native channel mask uses the same bit order as AudioChannelBitmap.
            layout.mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelBitmap
            layout.mChannelBitmap = AudioChannelBitmap(rawValue: UInt32(truncatingIfNeeded: channelMask))
        }
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                                             layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
                                             magicCookieSize: 0, magicCookie: nil, extensions: nil,
                                             formatDescriptionOut: &format) == noErr else { return nil }
        return format
    }

    /// Decoded PCM, trimmed so nothing before `notBefore` is played.
    static func pcm(_ frame: AudioFrame, format: CMAudioFormatDescription, notBefore: Double?) -> CMSampleBuffer? {
        var samples = frame.samples
        var pts = frame.pts
        var frames = frame.frameCount
        if let notBefore, notBefore > pts {
            let skip = min(frames, Int(((notBefore - pts) * Double(frame.sampleRate)).rounded()))
            guard skip < frames else { return nil }
            samples = samples.subdata(in: (samples.startIndex + skip * frame.channels * 4)..<samples.endIndex)
            frames -= skip
            pts += Double(skip) / Double(frame.sampleRate)
        }
        guard frames > 0, let block = blockBuffer(samples) else { return nil }
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault, dataBuffer: block,
                                                                   formatDescription: format, sampleCount: frames,
                                                                   presentationTimeStamp: CMTime(
                                                                       value: Int64((pts * Double(frame.sampleRate)).rounded()),
                                                                       timescale: Int32(frame.sampleRate)),
                                                                   packetDescriptions: nil,
                                                                   sampleBufferOut: &sample) == noErr else { return nil }
        return sample
    }
}
#endif
