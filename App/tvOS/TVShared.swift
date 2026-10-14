import Foundation

/// What the TV app shares with its Top Shelf extension: preferences (server, user, device id) in an
/// App Group. The token is shared through the Keychain group both list first in their entitlements,
/// which makes it the default group, so `KeychainTokenStore` needs no change.
enum TVShared {
    static let appGroup = "group.app.tinyjellyfin.Tinyfin"
    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }
}
