import Foundation

struct AriaPlaylist: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var subtitle: String
    var tracks: [Track]
    var coverImageData: Data?
    var revision: Int?

    init(
        id: UUID = UUID(),
        title: String,
        subtitle: String,
        tracks: [Track],
        coverImageData: Data? = nil,
        revision: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tracks = tracks
        self.coverImageData = coverImageData
        self.revision = revision
    }
}

struct AriaServerPlaylist: Codable {
    var id: UUID
    var title: String
    var trackIDs: [UUID]
    var coverImageData: Data?
    var revision: Int

    init(playlist: AriaPlaylist) {
        id = playlist.id
        title = playlist.title
        trackIDs = playlist.tracks.map(\.id)
        coverImageData = playlist.coverImageData
        revision = playlist.revision ?? 0
    }

    func playlist(using tracksByID: [UUID: Track]) -> AriaPlaylist {
        let tracks = trackIDs.compactMap { tracksByID[$0] }
        return AriaPlaylist(
            id: id,
            title: title,
            subtitle: tracks.count == 1 ? "1 song" : "\(tracks.count) songs",
            tracks: tracks,
            coverImageData: coverImageData,
            revision: revision
        )
    }
}

struct PlaylistStore {
    private struct Library: Codable {
        var version: Int
        var playlists: [AriaPlaylist]
    }

    let fileURL: URL

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
    }

    func load() -> [AriaPlaylist] {
        do {
            let data = try Data(contentsOf: fileURL)
            let library = try JSONDecoder().decode(Library.self, from: data)
            guard library.version == 1 else { return [] }
            return library.playlists
        } catch {
            return []
        }
    }

    func save(_ playlists: [AriaPlaylist]) {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Library(version: 1, playlists: playlists))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            return
        }
    }

    private static var defaultFileURL: URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory

        return baseURL
            .appendingPathComponent("Aria", isDirectory: true)
            .appendingPathComponent("playlists.json", isDirectory: false)
    }
}

struct AriaAlbum: Identifiable, Hashable {
    var title: String
    var artist: String
    var year: Int
    var tracks: [Track]

    var id: String {
        serverID ?? title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    var serverID: String? {
        tracks.compactMap(\.serverAlbumID).first
    }

    var artworkTrack: Track? {
        tracks.first
    }
}
