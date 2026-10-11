import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Thin async client for the Jellyfin REST API.
public final class JellyfinClient: @unchecked Sendable {
    public let baseURL: URL
    public let identity: ClientIdentity
    public private(set) var accessToken: String?
    public private(set) var userId: String?
    let session: URLSession
    private let lock = NSLock()

    /// Called (on an arbitrary thread) whenever any request comes back 401.
    public var onUnauthorized: (@Sendable () -> Void)?

    public init(baseURL: URL, identity: ClientIdentity, accessToken: String? = nil, userId: String? = nil,
                session: URLSession = .shared) {
        self.baseURL = baseURL
        self.identity = identity
        self.accessToken = accessToken
        self.userId = userId
        self.session = session
    }

    public func setCredentials(token: String?, userId: String?) {
        lock.lock(); defer { lock.unlock() }
        self.accessToken = token
        self.userId = userId
    }

    var authorizationHeader: String {
        lock.lock(); defer { lock.unlock() }
        return identity.authorizationHeader(token: accessToken)
    }

    func requireUserId() throws -> String {
        guard let userId else { throw JellyfinError.unauthorized }
        return userId
    }

    // MARK: URL building

    /// Joins an API path (and optional query) onto the base URL, keeping any base path
    /// such as `https://host/jellyfin`.
    public func url(_ path: String, query: [String: String?] = [:]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + (path.hasPrefix("/") ? path : "/" + path)
        let items = query.compactMap { key, value in value.map { URLQueryItem(name: key, value: $0) } }
            .sorted { $0.name < $1.name }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    /// Resolves a server-relative URL such as a `TranscodingUrl` against the base URL.
    public func resolve(serverRelative path: String) -> URL? {
        if let absolute = URL(string: path), absolute.scheme != nil { return absolute }
        guard let relative = URLComponents(string: path) else { return nil }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        components.path = basePath + (relative.path.hasPrefix("/") ? relative.path : "/" + relative.path)
        components.percentEncodedQuery = relative.percentEncodedQuery
        return components.url
    }

    // MARK: Requests

    func makeRequest(_ method: String, _ path: String, query: [String: String?] = [:], body: Data? = nil) -> URLRequest {
        var request = URLRequest(url: url(path, query: query))
        request.httpMethod = method
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.timeoutInterval = 30
        return request
    }

    func send(_ request: URLRequest) async throws -> Data {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.dataTaskAsync(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled { throw CancellationError() }
            throw JellyfinError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw JellyfinError.network("No HTTP response.")
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            onUnauthorized?()
            throw JellyfinError.unauthorized
        default:
            let message = String(data: data, encoding: .utf8).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
            throw JellyfinError.server(status: http.statusCode, message: message)
        }
    }

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:], as type: T.Type = T.self) async throws -> T {
        try decode(await send(makeRequest("GET", path, query: query)))
    }

    func post<Body: Encodable, T: Decodable>(_ path: String, query: [String: String?] = [:], body: Body,
                                             as type: T.Type = T.self) async throws -> T {
        try decode(await send(makeRequest("POST", path, query: query, body: try JSONCoding.encoder.encode(body))))
    }

    func postNoContent<Body: Encodable>(_ path: String, query: [String: String?] = [:], body: Body) async throws {
        _ = try await send(makeRequest("POST", path, query: query, body: try JSONCoding.encoder.encode(body)))
    }

    func send(_ method: String, _ path: String, query: [String: String?] = [:]) async throws {
        _ = try await send(makeRequest(method, path, query: query))
    }

    func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw JellyfinError.decoding(String(describing: error))
        }
    }
}

extension URLSession {
    /// `data(for:)` that also works on swift-corelibs-foundation and honours task cancellation.
    func dataTaskAsync(for request: URLRequest) async throws -> (Data, URLResponse) {
        final class TaskBox: @unchecked Sendable { var task: URLSessionDataTask? }
        let box = TaskBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let task = dataTask(with: request) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response {
                        continuation.resume(returning: (data ?? Data(), response))
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                box.task = task
                task.resume()
            }
        } onCancel: {
            box.task?.cancel()
        }
    }
}

/// Empty JSON body / response helper.
struct Empty: Codable {}
