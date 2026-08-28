import Foundation

struct Track: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var year: Int
    var trackNumber: Int?
    var artwork: ArtworkPalette
    var streamURL: URL?
    var artworkURL: URL?
    var isExplicit: Bool

    init(
        id: UUID = UUID(),
        title: String,
        artist: String,
        album: String,
        duration: TimeInterval,
        year: Int = 2026,
        trackNumber: Int? = nil,
        artwork: ArtworkPalette,
        streamURL: URL? = nil,
        artworkURL: URL? = nil,
        isExplicit: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.year = year
        self.trackNumber = trackNumber
        self.artwork = artwork
        self.streamURL = streamURL
        self.artworkURL = artworkURL
        self.isExplicit = isExplicit
    }
}

struct ArtworkPalette: Hashable, Codable {
    var topHex: String
    var bottomHex: String
    var symbolName: String
}

struct TrackLyrics: Decodable, Equatable {
    var trackID: String
    var available: Bool
    var instrumental: Bool
    var isSynced: Bool
    var source: String
    var plainLyrics: String?
    var syncedLines: [LyricLine]

    var plainLines: [String] {
        plainLyrics?
            .split(whereSeparator: \.isNewline)
            .map(String.init) ?? []
    }

    func activeLineID(at elapsed: TimeInterval) -> String? {
        guard isSynced else { return nil }
        return syncedLines.last { $0.startTime <= elapsed + 0.05 }?.id
    }
}

struct LyricLine: Decodable, Equatable, Identifiable {
    var id: String
    var startTime: TimeInterval
    var text: String
}

enum RepeatMode: String, CaseIterable, Identifiable {
    case off
    case one
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            "Repeat off"
        case .one:
            "Repeat one"
        case .all:
            "Repeat all"
        }
    }

    var systemImage: String {
        switch self {
        case .off, .all:
            "repeat"
        case .one:
            "repeat.1"
        }
    }
}
