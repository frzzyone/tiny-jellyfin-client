import Foundation

/// How this app identifies itself to the Jellyfin server.
public struct ClientIdentity: Sendable, Equatable {
    public var client: String
    public var device: String
    public var deviceId: String
    public var version: String

    public init(client: String = JellyfinKitInfo.clientName, device: String, deviceId: String, version: String) {
        self.client = client
        self.device = device
        self.deviceId = deviceId
        self.version = version
    }

    /// The `Authorization: MediaBrowser …` header value. The server URL-decodes each value,
    /// so values are percent-encoded to survive quotes, commas and non-ASCII device names.
    public func authorizationHeader(token: String?) -> String {
        var fields = [
            ("Client", client),
            ("Device", device),
            ("DeviceId", deviceId),
            ("Version", version),
        ]
        if let token, !token.isEmpty {
            fields.append(("Token", token))
        }
        let parts = fields.map { "\($0.0)=\"\(Self.encode($0.1))\"" }
        return "MediaBrowser " + parts.joined(separator: ", ")
    }

    private static let allowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}
