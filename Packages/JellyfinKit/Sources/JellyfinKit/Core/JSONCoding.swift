import Foundation

/// Jellyfin uses PascalCase JSON keys; Swift models use camelCase.
enum JSONCoding {
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int?
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue); self.intValue = intValue }
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .custom { path in
            let key = path.last!
            if key.intValue != nil { return key }
            return Key(stringValue: key.stringValue.prefix(1).lowercased() + key.stringValue.dropFirst())
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .custom { path in
            let key = path.last!
            if key.intValue != nil { return key }
            return Key(stringValue: key.stringValue.prefix(1).uppercased() + key.stringValue.dropFirst())
        }
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}
