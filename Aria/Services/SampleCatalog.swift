import Foundation

enum SampleCatalog {
    static let tracks: [Track] = [
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A001")!,
            title: "Low Light Signal",
            artist: "Nora Vale",
            album: "Afterimage",
            duration: 214,
            year: 2026,
            artwork: ArtworkPalette(topHex: "#45D6C7", bottomHex: "#26324A", symbolName: "waveform")
        ),
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A002")!,
            title: "Glass Harbor",
            artist: "Mika Sol",
            album: "Coastline Static",
            duration: 186,
            year: 2025,
            artwork: ArtworkPalette(topHex: "#F28482", bottomHex: "#2E1E32", symbolName: "sparkles")
        ),
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A003")!,
            title: "Night Pilot",
            artist: "The Kites",
            album: "Orbit Room",
            duration: 242,
            year: 2024,
            artwork: ArtworkPalette(topHex: "#A7C957", bottomHex: "#1A2C2A", symbolName: "moon.stars.fill")
        ),
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A004")!,
            title: "Velvet Metro",
            artist: "June Theory",
            album: "Turnstile",
            duration: 199,
            year: 2022,
            artwork: ArtworkPalette(topHex: "#F4D35E", bottomHex: "#23395B", symbolName: "tram.fill")
        ),
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A005")!,
            title: "Tide Memory",
            artist: "Oli Ren",
            album: "Soft Machines",
            duration: 271,
            year: 2023,
            artwork: ArtworkPalette(topHex: "#8ECAE6", bottomHex: "#1D3557", symbolName: "drop.fill")
        ),
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A006")!,
            title: "Small Hours",
            artist: "Amara Fox",
            album: "Kitchen Light",
            duration: 228,
            year: 2021,
            artwork: ArtworkPalette(topHex: "#B8F2E6", bottomHex: "#21455A", symbolName: "clock.fill")
        ),
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A007")!,
            title: "Static Bloom",
            artist: "Owen North",
            album: "Warm Circuits",
            duration: 203,
            year: 2025,
            artwork: ArtworkPalette(topHex: "#C77DFF", bottomHex: "#2B235A", symbolName: "antenna.radiowaves.left.and.right")
        ),
        Track(
            id: UUID(uuidString: "9A85E850-2B62-4DA1-8B7F-9D0B49B5A008")!,
            title: "Window Seat",
            artist: "Sia Lane",
            album: "Maps We Fold",
            duration: 253,
            year: 2020,
            artwork: ArtworkPalette(topHex: "#90BE6D", bottomHex: "#22332C", symbolName: "airplane")
        )
    ]

    static var playlists: [AriaPlaylist] {
        [
            AriaPlaylist(
                title: "Late Drive",
                subtitle: "Airy tracks for moving through the city.",
                tracks: [tracks[0], tracks[2], tracks[4], tracks[7]]
            ),
            AriaPlaylist(
                title: "Focus Pulse",
                subtitle: "Clean momentum without getting loud.",
                tracks: [tracks[1], tracks[3], tracks[6], tracks[0]]
            ),
            AriaPlaylist(
                title: "Quiet Sparks",
                subtitle: "Soft, bright songs for low-volume listening.",
                tracks: [tracks[5], tracks[4], tracks[1], tracks[7]]
            )
        ]
    }
}
