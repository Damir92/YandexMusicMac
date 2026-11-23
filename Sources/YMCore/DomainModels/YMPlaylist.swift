import Foundation

public struct YMTrackShort: Codable, Sendable, Identifiable {
    public let id: String
    public let albumId: String?
    public let timestamp: String?
    public let track: YMTrack?

    enum CodingKeys: String, CodingKey {
        case id
        case albumId
        case timestamp
        case track
    }

    public init(id: String, albumId: String? = nil, timestamp: String? = nil, track: YMTrack? = nil) {
        self.id = id
        self.albumId = albumId
        self.timestamp = timestamp
        self.track = track
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTrack = try? container.decodeIfPresent(YMTrack.self, forKey: .track)
        if let idString = FlexibleIDDecoder.decodeStringIfPresent(from: container, forKey: .id) {
            self.id = idString
        } else if let nestedTrack = decodedTrack {
            self.id = nestedTrack.id
        } else {
            self.id = UUID().uuidString
        }

        if let explicitAlbumId = FlexibleIDDecoder.decodeStringIfPresent(from: container, forKey: .albumId) {
            self.albumId = explicitAlbumId
        } else {
            self.albumId = decodedTrack?.primaryAlbumId
        }
        self.timestamp = try? container.decodeIfPresent(String.self, forKey: .timestamp)
        self.track = decodedTrack
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(albumId, forKey: .albumId)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(track, forKey: .track)
    }
}

public struct YMPlaylist: Codable, Sendable, Identifiable {
    public var id: String { "\(uid)_\(kind)" }
    public let uid: String
    public let kind: Int
    public let title: String
    public let description: String?
    public let visibility: String?
    public let revision: Int?
    public let trackCount: Int?
    public let coverUri: String?
    public let ogImage: String?
    public let tracks: [YMTrackShort]?

    public var isPrivate: Bool {
        visibility?.lowercased() == "private"
    }

    enum CodingKeys: String, CodingKey {
        case uid
        case kind
        case title
        case description
        case descriptionFormatted
        case visibility
        case revision
        case trackCount
        case cover
        case coverUri
        case ogImage
        case tracks
        case owner
    }

    enum DescriptionKeys: String, CodingKey {
        case text
    }

    enum CoverKeys: String, CodingKey {
        case uri
        case dir
        case itemsUri
    }

    enum OwnerKeys: String, CodingKey {
        case uid
    }

    public init(
        uid: String,
        kind: Int,
        title: String,
        description: String? = nil,
        visibility: String? = nil,
        revision: Int? = nil,
        trackCount: Int? = nil,
        coverUri: String? = nil,
        ogImage: String? = nil,
        tracks: [YMTrackShort]? = nil
    ) {
        self.uid = uid
        self.kind = kind
        self.title = title
        self.description = description
        self.visibility = visibility
        self.revision = revision
        self.trackCount = trackCount
        self.coverUri = coverUri
        self.ogImage = ogImage
        self.tracks = tracks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let directUid = FlexibleIDDecoder.decodeStringIfPresent(from: container, forKey: .uid) {
            self.uid = directUid
        } else if let ownerContainer = try? container.nestedContainer(keyedBy: OwnerKeys.self, forKey: .owner),
                  let ownerUid = FlexibleIDDecoder.decodeStringIfPresent(from: ownerContainer, forKey: .uid) {
            self.uid = ownerUid
        } else {
            self.uid = "0"
        }

        if let intKind = try? container.decodeIfPresent(Int.self, forKey: .kind) {
            self.kind = intKind
        } else if let strKind = try? container.decodeIfPresent(String.self, forKey: .kind), let parsed = Int(strKind) {
            self.kind = parsed
        } else {
            self.kind = 0
        }
        self.title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Плейлист"

        if let descStr = try? container.decodeIfPresent(String.self, forKey: .description), !descStr.isEmpty {
            self.description = descStr
        } else if let descObj = try? container.nestedContainer(keyedBy: DescriptionKeys.self, forKey: .description),
                  let descText = try? descObj.decodeIfPresent(String.self, forKey: .text), !descText.isEmpty {
            self.description = descText
        } else if let descFmt = try? container.decodeIfPresent(String.self, forKey: .descriptionFormatted), !descFmt.isEmpty {
            self.description = descFmt
        } else {
            self.description = nil
        }

        self.visibility = try? container.decodeIfPresent(String.self, forKey: .visibility)
        self.revision = try? container.decodeIfPresent(Int.self, forKey: .revision)
        self.trackCount = try? container.decodeIfPresent(Int.self, forKey: .trackCount)
        self.ogImage = try? container.decodeIfPresent(String.self, forKey: .ogImage)

        // Cover resolution with fallback to itemsUri.first, coverUri, ogImage, and dir last
        var coverUriFromContainer: String? = nil
        var coverItemsUriFirst: String? = nil
        var coverDir: String? = nil

        if let coverContainer = try? container.nestedContainer(keyedBy: CoverKeys.self, forKey: .cover) {
            coverUriFromContainer = try? coverContainer.decodeIfPresent(String.self, forKey: .uri)
            coverItemsUriFirst = (try? coverContainer.decodeIfPresent([String].self, forKey: .itemsUri))?.first
            coverDir = try? coverContainer.decodeIfPresent(String.self, forKey: .dir)
        }

        let fallbackCoverUri = try? container.decodeIfPresent(String.self, forKey: .coverUri)
        let ogImageVal = try? container.decodeIfPresent(String.self, forKey: .ogImage)

        var resolvedCover: String? = coverUriFromContainer ?? coverItemsUriFirst ?? fallbackCoverUri ?? ogImageVal
        if resolvedCover == nil, let dir = coverDir, YMCoverURLBuilder.buildURL(from: dir) != nil {
            resolvedCover = dir
        }

        self.coverUri = resolvedCover
        if container.contains(.tracks) && (try? container.decodeNil(forKey: .tracks)) == false {
            self.tracks = FlexibleArrayDecoder.decodeLossy(YMTrackShort.self, from: container, forKey: .tracks)
        } else {
            self.tracks = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uid, forKey: .uid)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(visibility, forKey: .visibility)
        try container.encodeIfPresent(revision, forKey: .revision)
        try container.encodeIfPresent(trackCount, forKey: .trackCount)
        try container.encodeIfPresent(coverUri, forKey: .coverUri)
        try container.encodeIfPresent(ogImage, forKey: .ogImage)
        try container.encodeIfPresent(tracks, forKey: .tracks)
    }

    public func coverURL(size: YMCoverSize = .medium) -> URL? {
        YMCoverURLBuilder.buildURL(from: coverUri, size: size)
    }
}
