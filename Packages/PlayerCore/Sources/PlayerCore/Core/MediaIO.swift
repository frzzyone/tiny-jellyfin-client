import CFFmpeg
import Foundation

/// Bridges `ByteSource`s to FFmpeg. Every open — the main URL and nested HLS playlists and
/// segments — goes through `io_open`, so FFmpeg never touches the network itself.
///
/// FFmpeg's HLS demuxer only accepts URLs whose scheme it has compiled in. Our build includes
/// the `http` protocol but no TLS library, so FFmpeg is shown `http://` URLs; the real scheme
/// is restored here before the request is made.
final class MediaIO {
    let factory: ByteSourceFactory
    let interrupt = InterruptFlag()
    private let realScheme: String
    private let lock = NSLock()
    private var openSources: [ObjectIdentifier: ByteSource] = [:]

    init(factory: ByteSourceFactory, realScheme: String) {
        self.factory = factory
        self.realScheme = realScheme
    }

    /// The URL string handed to FFmpeg for `url`.
    static func ffmpegURL(for url: URL) -> String {
        guard !url.isFileURL, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = "http"
        return components.string ?? url.absoluteString
    }

    func realURL(fromFFmpeg string: String) -> URL? {
        guard var components = URLComponents(string: string) else { return nil }
        if components.scheme == "http" { components.scheme = realScheme }
        return components.url
    }

    /// Interrupts every blocked read (seek, switch, close).
    func interruptReads() {
        lock.lock()
        let sources = Array(openSources.values)
        lock.unlock()
        sources.forEach { $0.cancel() }
    }

    func closeAll() {
        lock.lock()
        let sources = Array(openSources.values)
        openSources.removeAll()
        lock.unlock()
        sources.forEach { $0.close() }
    }

    fileprivate func track(_ source: ByteSource) {
        lock.lock(); openSources[ObjectIdentifier(source)] = source; lock.unlock()
    }

    fileprivate func untrack(_ source: ByteSource) {
        lock.lock(); openSources[ObjectIdentifier(source)] = nil; lock.unlock()
    }

    /// Wraps a source in an AVIOContext. The context's opaque retains an `AVIOBox`.
    func makeContext(for source: ByteSource) -> UnsafeMutablePointer<AVIOContext>? {
        let bufferSize: Int32 = 256 * 1024
        guard let buffer = av_malloc(Int(bufferSize)) else { return nil }
        let box = AVIOBox(source: source, io: self)
        let opaque = Unmanaged.passRetained(box).toOpaque()
        guard let context = avio_alloc_context(buffer.assumingMemoryBound(to: UInt8.self), bufferSize, 0, opaque,
                                               avioRead, nil, avioSeek) else {
            Unmanaged<AVIOBox>.fromOpaque(opaque).release()
            av_free(buffer)
            return nil
        }
        context.pointee.seekable = source.size != nil ? AVIO_SEEKABLE_NORMAL : 0
        track(source)
        return context
    }

    /// Frees a context created by `makeContext` and closes its source.
    static func freeContext(_ context: UnsafeMutablePointer<AVIOContext>?) {
        guard let context else { return }
        if let opaque = context.pointee.opaque {
            let box = Unmanaged<AVIOBox>.fromOpaque(opaque).takeRetainedValue()
            box.io?.untrack(box.source)
            box.source.close()
        }
        av_freep(&context.pointee.buffer)
        var pointer: UnsafeMutablePointer<AVIOContext>? = context
        avio_context_free(&pointer)
    }

    /// Installs io_open/io_close2 and the interrupt callback on a format context.
    /// The context's `opaque` must point to this MediaIO (unretained; the owner keeps it alive).
    func install(on context: UnsafeMutablePointer<AVFormatContext>) {
        context.pointee.opaque = Unmanaged.passUnretained(self).toOpaque()
        cff_set_io_callbacks(context, ioOpen, ioClose2)
        cff_set_interrupt(context, interruptCallback, Unmanaged.passUnretained(interrupt).toOpaque())
    }
}

final class AVIOBox {
    let source: ByteSource
    weak var io: MediaIO?
    var position: Int64 = 0

    init(source: ByteSource, io: MediaIO) {
        self.source = source
        self.io = io
    }
}

private func avioRead(_ opaque: UnsafeMutableRawPointer?, _ buffer: UnsafeMutablePointer<UInt8>?, _ size: Int32) -> Int32 {
    guard let opaque, let buffer else { return cff_averror_eio() }
    let box = Unmanaged<AVIOBox>.fromOpaque(opaque).takeUnretainedValue()
    if box.io?.interrupt.isSet == true { return cff_averror_exit() }
    do {
        let data = try box.source.read(at: box.position, maxLength: Int(size))
        if data.isEmpty { return cff_averror_eof() }
        data.copyBytes(to: buffer, count: data.count)
        box.position += Int64(data.count)
        return Int32(data.count)
    } catch is ByteSourceCancelled {
        return cff_averror_exit()
    } catch {
        return cff_averror_eio()
    }
}

private func avioSeek(_ opaque: UnsafeMutableRawPointer?, _ offset: Int64, _ whence: Int32) -> Int64 {
    guard let opaque else { return -1 }
    let box = Unmanaged<AVIOBox>.fromOpaque(opaque).takeUnretainedValue()
    let mode = whence & ~cff_avseek_force()
    if mode == cff_avseek_size() { return box.source.size ?? -1 }
    let target: Int64
    switch mode {
    case SEEK_SET: target = offset
    case SEEK_CUR: target = box.position + offset
    case SEEK_END:
        guard let size = box.source.size else { return -1 }
        target = size + offset
    default: return -1
    }
    guard target >= 0 else { return -1 }
    box.position = target
    return target
}

private func ioOpen(_ s: UnsafeMutablePointer<AVFormatContext>?, _ pb: UnsafeMutablePointer<UnsafeMutablePointer<AVIOContext>?>?,
                    _ url: UnsafePointer<CChar>?, _ flags: Int32,
                    _ options: UnsafeMutablePointer<OpaquePointer?>?) -> Int32 {
    guard let s, let pb, let url, let opaque = s.pointee.opaque else { return cff_averror_eio() }
    let io = Unmanaged<MediaIO>.fromOpaque(opaque).takeUnretainedValue()
    if io.interrupt.isSet { return cff_averror_exit() }
    guard let realURL = io.realURL(fromFFmpeg: String(cString: url)) else { return cff_averror_invaliddata() }
    do {
        let source = try io.factory.open(url: realURL)
        guard let context = io.makeContext(for: source) else { return cff_averror_eio() }
        pb.pointee = context
        return 0
    } catch {
        return cff_averror_eio()
    }
}

private func ioClose2(_ s: UnsafeMutablePointer<AVFormatContext>?, _ pb: UnsafeMutablePointer<AVIOContext>?) -> Int32 {
    MediaIO.freeContext(pb)
    return 0
}

private func interruptCallback(_ opaque: UnsafeMutableRawPointer?) -> Int32 {
    guard let opaque else { return 0 }
    return Unmanaged<InterruptFlag>.fromOpaque(opaque).takeUnretainedValue().isSet ? 1 : 0
}
