import Foundation

struct AriaPlaylist: Identifiable, Hashable {
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
