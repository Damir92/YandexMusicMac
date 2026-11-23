import Foundation

public struct YMArtist: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public let name: String
    public let various: Bool?
    public let composer: Bool?
    public let coverUri: String?

    public init(
        id: String,
        name: String,
        various: Bool? = nil,
        composer: Bool? = nil,
        coverUri: String? = nil
    ) {
        self.id = id
        self.name = name
        self.various = various
        self.composer = composer
        self.coverUri = coverUri
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case various
        case composer
        case cover
        case coverUri
        case ogImage
    }

    enum CoverKeys: String, CodingKey {
        case uri
        case prefix
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let idString = FlexibleIDDecoder.decodeStringIfPresent(from: container, forKey: .id) {
            self.id = idString
        } else {
            self.id = UUID().uuidString
        }

        self.name = (try? container.decodeIfPresent(String.self, forKey: .name)) ?? "Unknown Artist"
        self.various = try? container.decodeIfPresent(Bool.self, forKey: .various)
        self.composer = try? container.decodeIfPresent(Bool.self, forKey: .composer)

        var resolvedCover: String? = nil
        if let coverContainer = try? container.nestedContainer(keyedBy: CoverKeys.self, forKey: .cover) {
            resolvedCover = (try? coverContainer.decodeIfPresent(String.self, forKey: .uri))
                ?? (try? coverContainer.decodeIfPresent(String.self, forKey: .prefix))
        }
        if resolvedCover == nil {
            resolvedCover = (try? container.decodeIfPresent(String.self, forKey: .coverUri))
                ?? (try? container.decodeIfPresent(String.self, forKey: .ogImage))
        }
        self.coverUri = resolvedCover
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(various, forKey: .various)
        try container.encodeIfPresent(composer, forKey: .composer)
        if let coverUri = coverUri {
            var coverContainer = container.nestedContainer(keyedBy: CoverKeys.self, forKey: .cover)
            try coverContainer.encode(coverUri, forKey: .uri)
        }
    }

    public func coverURL(size: YMCoverSize = .medium) -> URL? {
        YMCoverURLBuilder.buildURL(from: coverUri, size: size)
    }
}
