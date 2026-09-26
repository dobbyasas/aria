import Foundation

struct SongRadioPage {
    var songs: [YouTubeMusicSongResult]
    var continuation: String?
}

protocol SongRadioProviding {
    func searchSongs(query: String, limit: Int) async throws -> [YouTubeMusicSongResult]
    func radio(seedVideoID: String, continuation: String?) async throws -> SongRadioPage
}

enum SongRadioError: LocalizedError {
    case seedNotFound
    case noMoreSongs
    case downloadFailed(String)
    case downloadedSongMissing
    case playbackUnavailable

    var errorDescription: String? {
        switch self {
        case .seedNotFound: "Could not find this song on YouTube Music. Try starting radio from a song search result."
        case .noMoreSongs: "YouTube Music has no more new songs for this radio. Try again to refresh it."
        case .downloadFailed(let message): "Could not download the next radio song: \(message)"
        case .downloadedSongMissing: "The download finished, but the song is not in the library yet. Try again."
        case .playbackUnavailable: "Could not start playback on this device. Check the song server connection and try again."
        }
    }
}

enum SongIdentity {
    static func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    static func key(title: String, artist: String) -> String {
        let artist = normalized(artist)
        let creator = artist.hasSuffix(" topic") ? String(artist.dropLast(6)) : artist
        return "song:\(normalized(title))|\(creator)"
    }
}

extension Track {
    // The existing downloader includes YouTube's video ID in the saved filename.
    var youtubeVideoID: String? {
        guard let filename = streamURL?.lastPathComponent,
              let range = filename.range(of: #"\[([A-Za-z0-9_-]{11})\]\.[^.]+$"#, options: .regularExpression) else {
            return nil
        }
        return String(filename[range].dropFirst().prefix(11))
    }

    var radioIdentity: String { SongIdentity.key(title: title, artist: artist) }
}

extension YouTubeMusicSongResult {
    var radioIdentity: String { SongIdentity.key(title: title, artist: artist) }

    func downloadedTrack(in catalog: [Track]) -> Track? {
        catalog.first { $0.youtubeVideoID == id }
            ?? catalog.first { $0.radioIdentity == radioIdentity }
    }
}

struct SongRadioBuffer {
    private(set) var pending: [YouTubeMusicSongResult] = []
    private var seen: Set<String> = []
    var continuation: String?

    mutating func markSeen(_ song: YouTubeMusicSongResult) {
        seen.insert("video:\(song.id)")
        seen.insert(song.radioIdentity)
    }

    mutating func append(_ page: SongRadioPage, excluding excluded: Set<String>) {
        continuation = page.continuation
        for song in page.songs {
            guard !seen.contains("video:\(song.id)"), !seen.contains(song.radioIdentity),
                  !excluded.contains("video:\(song.id)"), !excluded.contains(song.radioIdentity) else { continue }
            markSeen(song)
            pending.append(song)
        }
    }

    mutating func removeFirst() { pending.removeFirst() }

    mutating func exclude(_ keys: Set<String>) {
        pending.removeAll { keys.contains("video:\($0.id)") || keys.contains($0.radioIdentity) }
    }
}
