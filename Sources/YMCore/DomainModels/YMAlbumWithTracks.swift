import Foundation

/// Full album data including tracklist returned by `GET /albums/{albumId}/with-tracks`.
public struct YMAlbumWithTracks: Codable, Sendable, Identifiable {
    public let id: String
    public let title: String
    public let year: Int?
    public let releaseDate: String?
    public let coverUri: String?
    public let genre: String?
    public let trackCount: Int?
    public let likesCount: Int?
    public let artists: [YMArtist]
    public let volumes: [[YMTrack]]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case year
        case releaseDate
        case coverUri
        case ogImage
        case genre
        case trackCount
        case likesCount
        case artists
        case volumes
    }

    public init(
        id: String,
        title: String,
        year: Int? = nil,
        releaseDate: String? = nil,
        coverUri: String? = nil,
        genre: String? = nil,
        trackCount: Int? = nil,
        likesCount: Int? = nil,
        artists: [YMArtist] = [],
        volumes: [[YMTrack]] = []
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.releaseDate = releaseDate
        self.coverUri = coverUri
        self.genre = genre
        self.trackCount = trackCount
        self.likesCount = likesCount
        self.artists = artists
        self.volumes = volumes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let idString = FlexibleIDDecoder.decodeStringIfPresent(from: container, forKey: .id) {
            self.id = idString
        } else {
            self.id = UUID().uuidString
        }
        self.title = (try? container.decodeIfPresent(String.self, forKey: .title)) ?? "Unknown Album"
        self.year = try? container.decodeIfPresent(Int.self, forKey: .year)
        self.releaseDate = try? container.decodeIfPresent(String.self, forKey: .releaseDate)
        self.coverUri = (try? container.decodeIfPresent(String.self, forKey: .coverUri))
            ?? (try? container.decodeIfPresent(String.self, forKey: .ogImage))
        self.genre = try? container.decodeIfPresent(String.self, forKey: .genre)
        self.trackCount = try? container.decodeIfPresent(Int.self, forKey: .trackCount)
        self.likesCount = try? container.decodeIfPresent(Int.self, forKey: .likesCount)
        self.artists = FlexibleArrayDecoder.decodeLossy(YMArtist.self, from: container, forKey: .artists)

        // Lossy decoding for nested volumes [[YMTrack]]
        if let direct = try? container.decodeIfPresent([[YMTrack]].self, forKey: .volumes) {
            self.volumes = direct
        } else if var volumesContainer = try? container.nestedUnkeyedContainer(forKey: .volumes) {
            var decodedVolumes: [[YMTrack]] = []
            while !volumesContainer.isAtEnd {
                if let directVol = try? volumesContainer.decode([YMTrack].self) {
                    decodedVolumes.append(directVol)
                } else if var trackContainer = try? volumesContainer.nestedUnkeyedContainer() {
                    var volTracks: [YMTrack] = []
                    while !trackContainer.isAtEnd {
                        if let track = try? trackContainer.decode(YMTrack.self) {
                            volTracks.append(track)
                        } else {
                            _ = try? trackContainer.decode(LossySkipElement.self)
                        }
                    }
                    decodedVolumes.append(volTracks)
                } else {
                    _ = try? volumesContainer.decode(LossySkipElement.self)
                }
            }
            self.volumes = decodedVolumes
        } else {
            self.volumes = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(releaseDate, forKey: .releaseDate)
        try container.encodeIfPresent(coverUri, forKey: .coverUri)
        try container.encodeIfPresent(genre, forKey: .genre)
        try container.encodeIfPresent(trackCount, forKey: .trackCount)
        try container.encodeIfPresent(likesCount, forKey: .likesCount)
        try container.encode(artists, forKey: .artists)
        try container.encode(volumes, forKey: .volumes)
    }

    /// Flattened list of tracks from all volumes/discs
    public var allTracks: [YMTrack] {
        volumes.flatMap { $0 }
    }

    public var artistsString: String {
        if artists.isEmpty {
            return "Неизвестный исполнитель"
        }
        return artists.map(\.name).joined(separator: ", ")
    }

    public var formattedInfo: String {
        var parts: [String] = []
        if let year = year {
            parts.append(String(year))
        }
        if let genre = genre, !genre.isEmpty {
            parts.append(genre.capitalized)
        }
        let count = trackCount ?? allTracks.count
        if count > 0 {
            parts.append("\(count) трек\(tracksSuffix(count))")
        }
        return parts.joined(separator: " · ")
    }

    private func tracksSuffix(_ count: Int) -> String {
        let mod10 = count % 10
        let mod100 = count % 100
        if mod100 >= 11 && mod100 <= 19 { return "ов" }
        if mod10 == 1 { return "" }
        if mod10 >= 2 && mod10 <= 4 { return "а" }
        return "ов"
    }

    public func coverURL(size: YMCoverSize = .large) -> URL? {
        YMCoverURLBuilder.buildURL(from: coverUri, size: size)
    }
}
