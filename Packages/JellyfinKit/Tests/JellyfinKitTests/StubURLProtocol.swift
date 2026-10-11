import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import JellyfinKit

/// Routes requests to in-test handlers. Each test gets its own session via `StubServer`.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (Int, Data)
    nonisolated(unsafe) static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) static var requests: [String: [URLRequest]] = [:]
    static let lock = NSLock()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let key = request.value(forHTTPHeaderField: "X-Stub") ?? request.url?.host ?? ""
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            captured.httpBody = Data(reading: stream)
        }
        Self.lock.lock()
        Self.requests[key, default: []].append(captured)
        let handler = Self.handlers[key]
        Self.lock.unlock()
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotConnectToHost))
            return
        }
        do {
            let (status, data) = try handler(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

extension Data {
    init(reading stream: InputStream) {
        self.init()
        stream.open()
        defer { stream.close() }
        let size = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            append(buffer, count: read)
        }
    }
}

/// A fake Jellyfin host: unique hostname per instance so tests don't share handlers.
final class StubServer {
    let host: String
    let baseURL: URL
    let session: URLSession
    private var routes: [(method: String, path: String, handler: StubURLProtocol.Handler)] = []

    init(scheme: String = "https", basePath: String = "") {
        host = "stub-\(UUID().uuidString.prefix(8).lowercased()).test"
        baseURL = URL(string: "\(scheme)://\(host)\(basePath)")!
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        session = URLSession(configuration: config)
        StubURLProtocol.lock.lock()
        StubURLProtocol.handlers[host] = { [unowned self] request in try self.handle(request) }
        StubURLProtocol.lock.unlock()
    }

    deinit {
        StubURLProtocol.lock.lock()
        StubURLProtocol.handlers[host] = nil
        StubURLProtocol.requests[host] = nil
        StubURLProtocol.lock.unlock()
    }

    func on(_ method: String, _ path: String, status: Int = 200, json: String = "{}") {
        on(method, path) { _ in (status, Data(json.utf8)) }
    }

    func on(_ method: String, _ path: String, handler: @escaping StubURLProtocol.Handler) {
        routes.insert((method, path, handler), at: 0)
    }

    var requests: [URLRequest] {
        StubURLProtocol.lock.lock(); defer { StubURLProtocol.lock.unlock() }
        return StubURLProtocol.requests[host] ?? []
    }

    func lastRequest(path: String) -> URLRequest? {
        requests.last { $0.url?.path.hasSuffix(path) == true }
    }

    private func handle(_ request: URLRequest) throws -> (Int, Data) {
        let path = request.url?.path ?? ""
        for route in routes where route.method == request.httpMethod && path.hasSuffix(route.path) {
            return try route.handler(request)
        }
        return (404, Data())
    }

    func client(token: String? = "tok", userId: String? = "user1") -> JellyfinClient {
        JellyfinClient(baseURL: baseURL, identity: .test, accessToken: token, userId: userId, session: session)
    }
}

extension ClientIdentity {
    static let test = ClientIdentity(device: "Test Mac", deviceId: "device-1", version: "0.1.0")
}

func queryValue(_ request: URLRequest?, _ name: String) -> String? {
    guard let url = request?.url else { return nil }
    return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
}

func jsonBody(_ request: URLRequest?) -> [String: Any] {
    guard let data = request?.httpBody,
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return object
}
