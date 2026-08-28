import Foundation

struct AriaPlaylist: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var subtitle: String
    var tracks: [Track]

    init(id: UUID = UUID(), title: String, subtitle: String, tracks: [Track]) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.tracks = tracks
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
        title.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    var artworkTrack: Track? {
        tracks.first
    }
}
