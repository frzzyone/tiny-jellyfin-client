import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Random-access byte reader that backs an FFmpeg AVIOContext.
/// `read` may block; `cancel` must make a blocked `read` return promptly (throwing).
public protocol ByteSource: AnyObject {
    /// Total size if known.
    var size: Int64? { get }
    /// Reads up to `maxLength` bytes at `offset`. Returns empty data at end of stream.
    func read(at offset: Int64, maxLength: Int) throws -> Data
    func cancel()
    func close()
}

public struct ByteSourceCancelled: Error {}

public final class DataByteSource: ByteSource {
    private let data: Data
    public init(_ data: Data) { self.data = data }
    public var size: Int64? { Int64(data.count) }

    public func read(at offset: Int64, maxLength: Int) throws -> Data {
        guard offset < Int64(data.count) else { return Data() }
        let start = data.startIndex + Int(offset)
        let end = min(data.endIndex, start + maxLength)
        return data.subdata(in: start..<end)
    }

    public func cancel() {}
    public func close() {}
}

public final class FileByteSource: ByteSource {
    private let handle: FileHandle
    public let size: Int64?

    public init(url: URL) throws {
        handle = try FileHandle(forReadingFrom: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        size = (attributes[.size] as? NSNumber)?.int64Value
    }

    public func read(at offset: Int64, maxLength: Int) throws -> Data {
        try handle.seek(toOffset: UInt64(offset))
        return try handle.read(upToCount: maxLength) ?? Data()
    }

    public func cancel() {}
    public func close() { try? handle.close() }
}

/// Opens byte sources for URLs: the main media URL and nested HLS playlist/segment URLs.
public protocol ByteSourceFactory: AnyObject {
    func open(url: URL) throws -> ByteSource
}

/// Default factory: file URLs from disk, http(s) URLs through `HTTPByteSource`.
public final class DefaultByteSourceFactory: ByteSourceFactory {
    public let headers: [String: String]
    let session: URLSession

    public init(headers: [String: String] = [:], session: URLSession? = nil) {
        self.headers = headers
        self.session = session ?? HTTPByteSource.sharedSession
    }

    public func open(url: URL) throws -> ByteSource {
        if url.isFileURL { return try FileByteSource(url: url) }
        return HTTPByteSource(url: url, headers: headers, session: session)
    }
}
