import Foundation

public enum YMCoverSize: String, Sendable {
    case small = "100x100"      // Tables and track rows
    case medium = "200x200"     // Cards and playlists
    case artwork = "300x300"    // System NowPlaying / RemoteCommand
    case large = "400x400"      // Now Playing view and Player bar
}

public enum YMCoverURLBuilder {
    /// Converts avatars.yandex.net template URL into a full concrete HTTPS image URL.
    /// Replaces `%%` with the target size, e.g. "100x100" or "400x400".
    public static func buildURL(from coverUri: String?, size: YMCoverSize = .medium) -> URL? {
        guard let coverUri = coverUri else { return nil }
        let trimmed = coverUri.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Relative path without host (e.g. "/get-music-user-playlist/...") is not a valid absolute URL
        if trimmed.hasPrefix("/") && !trimmed.hasPrefix("//") {
            return nil
        }

        var uri = trimmed.replacingOccurrences(of: "%%", with: size.rawValue)
        if uri.hasPrefix("http://") {
            uri = "https://" + uri.dropFirst("http://".count)
        } else if uri.hasPrefix("//") {
            uri = "https:" + uri
        } else if !uri.hasPrefix("https://") {
            uri = "https://" + uri
        }

        if let url = URL(string: uri) {
            guard let host = url.host, !host.isEmpty else { return nil }
            return url
        }

        let allowed = CharacterSet.urlQueryAllowed
            .union(.urlPathAllowed)
            .union(CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;="))
        if let encoded = uri.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: encoded) {
            guard let host = url.host, !host.isEmpty else { return nil }
            return url
        }

        return nil
    }
}

/// Helper for decoding String, Int or UInt values safely as String.
public enum FlexibleIDDecoder {
    public static func decodeString(from decoder: Decoder) throws -> String {
        let container = try decoder.singleValueContainer()
        if let stringVal = try? container.decode(String.self) {
            return stringVal
        }
        if let intVal = try? container.decode(Int64.self) {
            return String(intVal)
        }
        if let uintVal = try? container.decode(UInt64.self) {
            return String(uintVal)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected String or Int for ID"
            )
        )
    }

    public static func decodeStringIfPresent<Key: CodingKey>(from container: KeyedDecodingContainer<Key>, forKey key: Key) -> String? {
        if let str = try? container.decodeIfPresent(String.self, forKey: key) {
            return str
        }
        if let int = try? container.decodeIfPresent(Int64.self, forKey: key) {
            return String(int)
        }
        if let uint = try? container.decodeIfPresent(UInt64.self, forKey: key) {
            return String(uint)
        }
        return nil
    }
}

// MARK: - Flexible Array Lossy Decoder

public struct LossySkipElement: Decodable, Sendable {
    public init(from decoder: Decoder) throws {
        if (try? decoder.singleValueContainer()) != nil { return }
        if (try? decoder.container(keyedBy: AnyKey.self)) != nil { return }
        var unkeyed = try? decoder.unkeyedContainer()
        while unkeyed != nil && !(unkeyed!.isAtEnd) {
            _ = try? unkeyed?.decode(LossySkipElement.self)
        }
    }

    private struct AnyKey: CodingKey {
        var stringValue: String
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int?
        init?(intValue: Int) { self.intValue = intValue; self.stringValue = "\(intValue)" }
    }
}

public enum FlexibleArrayDecoder {
    public static func decodeLossy<T: Decodable, Key: CodingKey>(
        _ type: T.Type,
        from container: KeyedDecodingContainer<Key>,
        forKey key: Key
    ) -> [T] {
        if let direct = try? container.decodeIfPresent([T].self, forKey: key) {
            return direct
        }
        guard var arrayContainer = try? container.nestedUnkeyedContainer(forKey: key) else {
            return []
        }
        var items: [T] = []
        while !arrayContainer.isAtEnd {
            if let item = try? arrayContainer.decode(T.self) {
                items.append(item)
            } else {
                _ = try? arrayContainer.decode(LossySkipElement.self)
            }
        }
        return items
    }
}
