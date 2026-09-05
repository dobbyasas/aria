import SwiftUI
import UIKit
import PhotosUI

struct LibraryView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedSection: LibrarySection = .songs
    @State private var songSearchText = ""
    @State private var albumSearchText = ""
    @State private var playlistSearchText = ""
    @State private var albumSortMode: AlbumSortMode = .title
    @State private var isDownloadSheetPresented = false
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollToTopScrollView(bottomClearance: scrollButtonBottomClearance) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    sectionPicker
                    librarySearchField
                    sectionContent

                    if !usesTabletLayout {
                        versionFooter
                    }
                }
                .padding(.horizontal, usesTabletLayout ? 36 : 20)
                .padding(.top, usesTabletLayout ? 34 : 24)
                .padding(.bottom, 24)
                .frame(maxWidth: usesTabletLayout ? 1060 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .background(Color.ariaBackground.ignoresSafeArea())
            .scrollDismissesKeyboard(.interactively)
            .navigationDestination(for: LibraryRoute.self) { route in
                destination(for: route)
            }
            .navigationDestination(item: $player.presentedArtist) { artist in
                ArtistPageView(artistName: artist.name)
            }
        }
        .background(Color.ariaBackground.ignoresSafeArea())
        .sheet(isPresented: $isDownloadSheetPresented) {
            MobileDownloadMusicSheet()
                .environmentObject(player)
        }
    }

    private var usesTabletLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var scrollButtonBottomClearance: CGFloat {
        usesTabletLayout || player.currentTrack == nil ? 0 : 72
    }

    private var versionFooter: some View {
        Text(AriaRelease.displayText)
            .font(.caption2.monospacedDigit().weight(.medium))
            .foregroundStyle(.ariaTextSecondary.opacity(0.72))
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
            .accessibilityLabel("Aria \(AriaRelease.displayText)")
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Your Library")
                .font(.system(size: usesTabletLayout ? 40 : 30, weight: .bold))
                .foregroundStyle(.ariaTextPrimary)

            Spacer()

            Button {
                isSearchFocused = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.ariaTextPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(AriaPressButtonStyle())
            .accessibilityLabel("Search your library")

            Button {
                isDownloadSheetPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.ariaTextPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(AriaPressButtonStyle())
            .disabled(player.isDownloadStarting || player.downloadJob?.isActive == true)
            .opacity(player.isDownloadStarting || player.downloadJob?.isActive == true ? 0.55 : 1)
            .accessibilityLabel("Download music")
        }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LibrarySection.allCases) { section in
                    Button {
                        guard selectedSection != section else { return }
                        withAnimation(AriaMotion.fast) {
                            selectedSection = section
                        }
                    } label: {
                        Text(section.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(selectedSection == section ? Color.black : Color.ariaTextPrimary)
                            .padding(.horizontal, 16)
                            .frame(height: 36)
                            .background(
                                selectedSection == section ? Color.ariaAccent : Color.ariaSurfaceRaised,
                                in: Capsule()
                            )
                            .contentShape(Capsule())
                    }
                    .buttonStyle(AriaPressButtonStyle(pressedScale: 0.97))
                    .accessibilityAddTraits(selectedSection == section ? .isSelected : [])
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selectedSection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library sections")
    }

    private var librarySearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ariaTextSecondary)

            TextField(selectedSection.searchPrompt, text: activeSearchText)
                .font(.subheadline)
                .foregroundStyle(.ariaTextPrimary)
                .focused($isSearchFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !activeSearchText.wrappedValue.isEmpty {
                Button {
                    withAnimation(AriaMotion.fast) {
                        activeSearchText.wrappedValue = ""
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                }
                .buttonStyle(AriaPressButtonStyle(pressedScale: 0.9))
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(.ariaSurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(AriaMotion.fast, value: activeSearchText.wrappedValue.isEmpty)
    }

    private var activeSearchText: Binding<String> {
        switch selectedSection {
        case .songs:
            $songSearchText
        case .albums:
            $albumSearchText
        case .playlists:
            $playlistSearchText
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .songs:
            songsSection
        case .albums:
            albumsSection
        case .playlists:
            playlistsSection
        }
    }

    private var songsSection: some View {
        let songs = filteredSongs

        return LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Songs")

            catalogStatus

            if player.catalog.isEmpty, !player.isCatalogLoading {
                Text("No songs loaded yet. Start the Fedora server and tap Retry.")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if songs.isEmpty, !songSearchText.isEmpty {
                SearchEmptyState(itemName: "songs", query: songSearchText)
            } else {
                ForEach(songs) { track in
                    TrackRow(track: track, source: songs)
                }
            }
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if player.isCatalogLoading {
            AriaLoadingIndicator()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
        } else if let catalogErrorMessage = player.catalogErrorMessage {
            VStack(alignment: .leading, spacing: 10) {
                Text("Could not reach the song server.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariaTextPrimary)

                Text(catalogErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.ariaTextSecondary)

                Button {
                    Task {
                        await player.refreshCatalog()
                    }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.bold))
                }
                .buttonStyle(.borderedProminent)
                .tint(.ariaAccent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    @ViewBuilder
    private var albumsSection: some View {
        let albums = filteredAlbums

        LazyVStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Text("Albums")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.ariaTextPrimary)

                Text(albums.count.formatted())
                    .font(.caption.monospacedDigit().weight(.bold))
                    .foregroundStyle(.ariaTextSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(.white.opacity(0.07), in: Capsule())

                Spacer()

                Menu {
                    Picker("Sort albums", selection: $albumSortMode) {
                        ForEach(AlbumSortMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(albumSortMode.shortTitle)
                            .font(.caption.weight(.semibold))
                        Image(systemName: "arrow.up.arrow.down")
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("Sort albums, currently \(albumSortMode.title)")
            }

            if albums.isEmpty, !albumSearchText.isEmpty {
                SearchEmptyState(itemName: "albums", query: albumSearchText)
            } else if albums.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "opticaldisc")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.ariaAccent)

                    Text("No albums yet")
                        .font(.headline)
                        .foregroundStyle(.ariaTextPrimary)

                    Text("Add music and your collection will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
            } else {
                LazyVGrid(columns: albumGridColumns, alignment: .leading, spacing: usesTabletLayout ? 28 : 24) {
                    ForEach(albums) { album in
                        AlbumGridCard(album: album, isExpanded: usesTabletLayout)
                    }
                }
            }
        }
    }

    private var albumGridColumns: [GridItem] {
        [
            GridItem(
                .adaptive(
                    minimum: usesTabletLayout ? 198 : 150,
                    maximum: usesTabletLayout ? 228 : 184
                ),
                spacing: usesTabletLayout ? 22 : 14,
                alignment: .top
            )
        ]
    }

    private var playlistsSection: some View {
        let playlists = filteredPlaylists

        return LazyVStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Playlists", actionTitle: "New") {
                _ = player.createPlaylist()
            }

            if playlists.isEmpty, !playlistSearchText.isEmpty {
                SearchEmptyState(itemName: "playlists", query: playlistSearchText)
            } else if usesTabletLayout {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 176, maximum: 218), spacing: 20, alignment: .top)],
                    alignment: .leading,
                    spacing: 24
                ) {
                    ForEach(playlists) { playlist in
                        TabletPlaylistCard(playlist: playlist)
                    }
                }
            } else {
                ForEach(playlists) { playlist in
                    PlaylistRow(playlist: playlist)
                }
            }
        }
    }

    private var filteredSongs: [Track] {
        let query = songSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return player.catalog }

        return player.catalog.filter { track in
            track.title.localizedStandardContains(query)
                || track.artist.localizedStandardContains(query)
                || track.album.localizedStandardContains(query)
        }
    }

    private var filteredAlbums: [AriaAlbum] {
        let query = albumSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingAlbums = query.isEmpty
            ? player.albums
            : player.albums.filter { album in
                album.title.localizedStandardContains(query)
                    || album.artist.localizedStandardContains(query)
            }

        return matchingAlbums.sorted { first, second in
            switch albumSortMode {
            case .title:
                first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            case .artist:
                if first.artist.caseInsensitiveCompare(second.artist) == .orderedSame {
                    first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
                } else {
                    first.artist.localizedCaseInsensitiveCompare(second.artist) == .orderedAscending
                }
            case .newest:
                if first.year == second.year {
                    first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
                } else {
                    first.year > second.year
                }
            }
        }
    }

    private var filteredPlaylists: [AriaPlaylist] {
        let query = playlistSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return player.playlists }

        return player.playlists.filter { playlist in
            playlist.title.localizedStandardContains(query)
        }
    }

    @ViewBuilder
    private func destination(for route: LibraryRoute) -> some View {
        switch route {
        case .album(let albumID):
            if let album = player.albums.first(where: { $0.id == albumID }) {
                AlbumDetailView(album: album)
            } else {
                MissingLibraryItemView(title: "Album unavailable")
            }
        case .playlist(let playlistID):
            if let playlist = player.playlists.first(where: { $0.id == playlistID }) {
                PlaylistDetailView(playlist: playlist)
            } else {
                MissingLibraryItemView(title: "Playlist unavailable")
            }
        }
    }

}

private enum LibraryRoute: Hashable {
    case album(String)
    case playlist(UUID)
}

private enum LibrarySection: String, CaseIterable, Identifiable {
    case songs
    case albums
    case playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .songs:
            "Songs"
        case .albums:
            "Albums"
        case .playlists:
            "Playlists"
        }
    }

    var searchPrompt: String {
        switch self {
        case .songs:
            "Search songs"
        case .albums:
            "Search albums"
        case .playlists:
            "Search playlists"
        }
    }

    var systemImage: String {
        switch self {
        case .songs:
            "music.note"
        case .albums:
            "square.stack"
        case .playlists:
            "music.note.list"
        }
    }
}

private enum AlbumSortMode: String, CaseIterable, Identifiable {
    case title
    case artist
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .title:
            "Album title"
        case .artist:
            "Artist"
        case .newest:
            "Newest first"
        }
    }

    var systemImage: String {
        switch self {
        case .title:
            "textformat"
        case .artist:
            "person.fill"
        case .newest:
            "calendar"
        }
    }

    var shortTitle: String {
        switch self {
        case .title:
            "Title"
        case .artist:
            "Artist"
        case .newest:
            "Year"
        }
    }
}

struct ArtistPageView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var artistProfile: YouTubeMusicArtistResult?
    @State private var availableAlbums: [YouTubeMusicAlbumResult] = []
    @State private var isLoading = true
    @State private var showsSkeleton = false
    @State private var loadError: String?
    @State private var artistArtwork: UIImage?
    @State private var visibleAlbumCount = 16

    let artistName: String
    private let searchClient = YouTubeMusicSearchClient()

    private var downloadedSongs: [Track] {
        player.songs(byArtist: artistName)
    }

    private var downloadedAlbums: [AriaAlbum] {
        player.albums(byArtist: artistName)
    }

    private var downloadableAlbums: [YouTubeMusicAlbumResult] {
        availableAlbums.filter {
            player.albumResult($0, belongsToArtist: artistName) && !player.isAlbumDownloaded($0)
        }
    }

    var body: some View {
        ScrollToTopScrollView(bottomClearance: scrollButtonBottomClearance) {
            LazyVStack(alignment: .leading, spacing: 0) {
                artistHeader

                LazyVStack(alignment: .leading, spacing: 28) {
                    if !downloadedAlbums.isEmpty {
                        downloadedAlbumsSection
                    }

                    availableAlbumsSection

                    if !downloadedSongs.isEmpty {
                        downloadedSongsSection
                    }
                }
                .padding(.horizontal, usesTabletLayout ? 36 : 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color.ariaBackground.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: artistName) {
            await loadArtist()
        }
        .task(id: artistProfile?.artworkURL) {
            artistArtwork = nil
            guard let url = artistProfile?.artworkURL else { return }
            artistArtwork = await AriaArtworkCache.shared.image(for: url)
        }
    }

    private var artistHeader: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let artistArtwork {
                    Image(uiImage: artistArtwork)
                        .resizable()
                        .scaledToFill()
                } else if showsSkeleton || artistProfile?.artworkURL != nil {
                    Color.white.opacity(0.09)
                } else {
                    artistPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: heroHeight)
            .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.34), location: 0),
                    .init(color: .black.opacity(0.06), location: 0.24),
                    .init(color: .black.opacity(0.12), location: 0.42),
                    .init(color: Color.ariaBackground.opacity(0.76), location: 0.78),
                    .init(color: Color.ariaBackground, location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("ARTIST")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.ariaAccent)

                Text(artistProfile?.name ?? artistName)
                    .font(.system(size: usesTabletLayout ? 48 : 38, weight: .bold))
                    .foregroundStyle(.ariaTextPrimary)
                    .lineLimit(2)

                Text("\(songCountText(downloadedSongs.count)) in your library • \(downloadedAlbums.count) downloaded \(downloadedAlbums.count == 1 ? "album" : "albums")")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
            }
            .padding(.horizontal, usesTabletLayout ? 36 : 20)
            .padding(.bottom, 28)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: heroHeight)
        .background(Color.ariaSurface)
        .clipped()
    }

    private var downloadedAlbumsSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Downloaded Albums")

            ForEach(downloadedAlbums) { album in
                NavigationLink {
                    AlbumDetailView(album: album)
                } label: {
                    HStack(spacing: 14) {
                        if let track = album.artworkTrack {
                            ArtworkView(track: track, size: 72, cornerRadius: 9)
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(album.title)
                                .font(.headline)
                                .foregroundStyle(.ariaTextPrimary)
                                .lineLimit(2)
                            Text("\(album.year) • \(songCountText(album.tracks.count))")
                                .font(.subheadline)
                                .foregroundStyle(.ariaTextSecondary)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ariaTextSecondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
            }
        }
    }

    private var downloadedSongsSection: some View {
        let songs = downloadedSongs
        return LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Downloaded Songs")
            ForEach(songs) { track in
                TrackRow(track: track, source: songs)
            }
        }
    }

    @ViewBuilder
    private var availableAlbumsSection: some View {
        let albums = downloadableAlbums
        LazyVStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "More Albums")

            if isLoading {
                if showsSkeleton {
                    albumSkeleton
                } else {
                    ProgressView().tint(.ariaAccent)
                }
            } else if let loadError {
                VStack(alignment: .leading, spacing: 8) {
                    Text(loadError)
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                    Button("Try Again") {
                        Task { await loadArtist() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ariaAccent)
                }
            } else if albums.isEmpty {
                Text("No additional albums were found.")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
            } else {
                ForEach(albums.prefix(visibleAlbumCount)) { result in
                    MobileYouTubeMusicAlbumResultRow(result: result)
                }

                if visibleAlbumCount < albums.count {
                    ProgressView()
                        .tint(.ariaAccent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .onAppear {
                            visibleAlbumCount = min(visibleAlbumCount + 16, albums.count)
                        }
                }
            }
        }
    }

    private var artistPlaceholder: some View {
        ZStack {
            Color.ariaSurface
            Image(systemName: "person.fill")
                .font(.system(size: usesTabletLayout ? 100 : 76, weight: .medium))
                .foregroundStyle(.ariaTextSecondary.opacity(0.7))
        }
    }

    private var usesTabletLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var scrollButtonBottomClearance: CGFloat {
        usesTabletLayout || player.currentTrack == nil ? 0 : 72
    }

    private var heroHeight: CGFloat {
        usesTabletLayout ? 470 : 360
    }

    private var albumSkeleton: some View {
        VStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(.white.opacity(0.09))
                        .frame(width: 54, height: 54)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.1))
                            .frame(height: 13)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(.white.opacity(0.07))
                            .frame(width: 140, height: 10)
                    }
                    Spacer()
                }
                .padding(.vertical, 3)
            }
        }
        .accessibilityLabel("Loading albums")
    }

    private func loadArtist() async {
        isLoading = true
        showsSkeleton = false
        visibleAlbumCount = 16
        loadError = nil
        let skeletonTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            showsSkeleton = true
        }
        do {
            let result = try await searchClient.artistPage(named: artistName, albumLimit: 60)
            artistProfile = result.artist
            availableAlbums = result.albums
        } catch {
            loadError = error.localizedDescription
        }
        skeletonTask.cancel()
        showsSkeleton = false
        isLoading = false
    }
}

private struct SearchEmptyState: View {
    let itemName: String
    let query: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.ariaTextSecondary)

            Text("No \(itemName) found")
                .font(.headline)
                .foregroundStyle(.ariaTextPrimary)

            Text("Nothing matches \"\(query)\".")
                .font(.subheadline)
                .foregroundStyle(.ariaTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

private struct AlbumGridCard: View {
    let album: AriaAlbum
    let isExpanded: Bool

    private var artworkSize: CGFloat { isExpanded ? 176 : 138 }

    var body: some View {
        NavigationLink(value: LibraryRoute.album(album.id)) {
            VStack(alignment: .leading, spacing: 12) {
                albumObject
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    Text(album.title)
                        .font(.headline)
                        .foregroundStyle(.ariaTextPrimary)
                        .lineLimit(2)
                        .frame(minHeight: 42, alignment: .topLeading)

                    Text(album.artist)
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        if album.year > 0 {
                            Text(String(album.year))
                            Text("•")
                        }
                        Text(songCountText(album.tracks.count))
                    }
                    .font(.caption)
                    .foregroundStyle(.ariaTextSecondary.opacity(0.78))
                }
            }
            .contentShape(Rectangle())
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("Opens album")
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.97))
    }

    @ViewBuilder
    private var albumObject: some View {
        if let artworkTrack = album.artworkTrack {
            ArtworkView(track: artworkTrack, size: artworkSize, cornerRadius: 4)
                .shadow(color: .black.opacity(0.24), radius: 8, x: 0, y: 5)
            .frame(height: artworkSize)
        }
    }

    private var accessibilityDescription: String {
        let year = album.year > 0 ? String(album.year) : "year unknown"
        return "\(album.title) by \(album.artist), \(year), \(songCountText(album.tracks.count))"
    }
}

private struct AlbumVinylRecord: View {
    let track: Track
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.black,
                            Color(red: 0.12, green: 0.13, blue: 0.14),
                            Color.black,
                            Color(red: 0.08, green: 0.09, blue: 0.1)
                        ],
                        center: .center,
                        startRadius: size * 0.08,
                        endRadius: size * 0.5
                    )
                )

            ForEach([0.62, 0.76, 0.9], id: \.self) { scale in
                Circle()
                    .stroke(.white.opacity(0.06), lineWidth: 0.7)
                    .frame(width: size * scale, height: size * scale)
            }

            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: track.artwork.topHex), Color(hex: track.artwork.bottomHex)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size * 0.28, height: size * 0.28)

            Circle()
                .fill(.black)
                .frame(width: size * 0.055, height: size * 0.055)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 8)
        .accessibilityHidden(true)
    }
}

private struct PlaylistRow: View {
    let playlist: AriaPlaylist

    var body: some View {
        NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
            HStack(spacing: 14) {
                playlistArtwork

                VStack(alignment: .leading, spacing: 5) {
                    Text(playlist.title)
                        .font(.headline)
                        .foregroundStyle(.ariaTextPrimary)
                        .lineLimit(1)

                    Text(playlist.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaTextSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
        .padding(.vertical, 3)
    }

    private var playlistArtwork: some View {
        PlaylistArtwork(playlist: playlist, size: 64, cornerRadius: 4)
    }
}

private struct TabletPlaylistCard: View {
    let playlist: AriaPlaylist

    var body: some View {
        NavigationLink(value: LibraryRoute.playlist(playlist.id)) {
            VStack(alignment: .leading, spacing: 12) {
                artwork
                    .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 5) {
                    Text(playlist.title)
                        .font(.headline)
                        .foregroundStyle(.ariaTextPrimary)
                        .lineLimit(2)

                    Text(playlist.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                        .lineLimit(1)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.045))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
    }

    private var artwork: some View {
        PlaylistArtwork(playlist: playlist, size: 152, cornerRadius: 10)
    }
}

private struct AlbumDetailView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var confirmsAlbumDeletion = false
    @State private var isDeletingAlbum = false
    @State private var albumDeletionError: String?

    let album: AriaAlbum

    var body: some View {
        ScrollToTopScrollView(bottomClearance: scrollButtonBottomClearance) {
            LazyVStack(alignment: .leading, spacing: 24) {
                albumHeader

                LazyVStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Tracks")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.ariaTextPrimary)

                        Spacer()

                        Text("\(album.tracks.count) • \(albumDurationText)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.ariaTextSecondary)
                    }

                    ForEach(album.tracks) { track in
                        TrackRow(track: track, source: album.tracks, showAlbum: false)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(.white.opacity(0.055))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .padding(.horizontal, usesTabletLayout ? 36 : 20)
            .padding(.top, usesTabletLayout ? 30 : 18)
            .padding(.bottom, 32)
            .frame(maxWidth: usesTabletLayout ? 920 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(Color.ariaBackground.ignoresSafeArea())
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Delete \(album.title)?", isPresented: $confirmsAlbumDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Album", role: .destructive) { deleteAlbum() }
        } message: {
            Text("This permanently removes all \(album.tracks.count) song files in this album from the Aria server and shared playlists.")
        }
        .alert(
            "Couldn’t Delete Album",
            isPresented: Binding(
                get: { albumDeletionError != nil },
                set: { if !$0 { albumDeletionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(albumDeletionError ?? "Unknown error")
        }
    }

    @ViewBuilder
    private var albumHeader: some View {
        Group {
            if usesTabletLayout {
                HStack(alignment: .center, spacing: 46) {
                    albumObject(size: 260)
                    albumIdentity(isCentered: false)
                }
            } else {
                VStack(spacing: 24) {
                    ViewThatFits(in: .horizontal) {
                        albumObject(size: 218)
                        albumObject(size: 188)
                    }
                    .frame(maxWidth: .infinity)

                    albumIdentity(isCentered: true)
                }
            }
        }
        .padding(usesTabletLayout ? 34 : 24)
        .frame(maxWidth: .infinity)
        .background(albumHeroBackground)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func albumObject(size: CGFloat) -> some View {
        if let artworkTrack = album.artworkTrack {
            ArtworkView(track: artworkTrack, size: size, cornerRadius: 5)
                .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 16)
        }
    }

    private func albumIdentity(isCentered: Bool) -> some View {
        VStack(alignment: isCentered ? .center : .leading, spacing: 10) {
            Text(album.title)
                .font(.system(size: usesTabletLayout ? 40 : 30, weight: .semibold))
                .foregroundStyle(.ariaTextPrimary)
                .multilineTextAlignment(isCentered ? .center : .leading)
                .lineLimit(3)

            ArtistNameLink(name: album.artist)
                .font(.title3)
                .foregroundStyle(.ariaTextSecondary)

            HStack(spacing: 6) {
                Text(albumMetadataText)
                Text("•")
                Text(albumDurationText)
            }
            .font(.subheadline)
            .foregroundStyle(.ariaTextSecondary)

            albumActions
                .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: isCentered ? .center : .leading)
    }

    private var albumActions: some View {
        HStack(spacing: 10) {
            Button(action: playAlbum) {
                Label("Play", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(.black.opacity(0.88))
                    .padding(.horizontal, 22)
                    .frame(height: 50)
                    .background(.ariaAccent, in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.95))
            .disabled(album.tracks.isEmpty)

            Button(action: shuffleAlbum) {
                Image(systemName: "shuffle")
                    .font(.headline)
                    .foregroundStyle(.ariaTextPrimary)
                    .frame(width: 50, height: 50)
                    .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.92))
            .disabled(album.tracks.isEmpty)
            .accessibilityLabel("Shuffle album")

            Menu {
                Button(role: .destructive) {
                    confirmsAlbumDeletion = true
                } label: {
                    Label("Delete album", systemImage: "trash")
                }
            } label: {
                Group {
                    if isDeletingAlbum {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(.ariaTextPrimary)
                    }
                }
                .frame(width: 50, height: 50)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isDeletingAlbum)
            .accessibilityLabel("More album actions")
        }
    }

    private var albumHeroBackground: some View {
        let artwork = album.artworkTrack?.artwork
        return ZStack {
            LinearGradient(
                colors: [
                    artwork.map { Color(hex: $0.topHex).opacity(0.38) } ?? Color.ariaSurfaceRaised,
                    Color.ariaSurface.opacity(0.98),
                    artwork.map { Color(hex: $0.bottomHex).opacity(0.18) } ?? Color.ariaSurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            LinearGradient(
                colors: [.white.opacity(0.05), .clear, .black.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var albumMetadataText: String {
        let year = album.year > 0 ? "\(album.year) • " : ""
        return "\(year)\(songCountText(album.tracks.count))"
    }

    private var albumDurationText: String {
        album.tracks.reduce(0) { $0 + $1.duration }.ariaClockTime
    }

    private var usesTabletLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var scrollButtonBottomClearance: CGFloat {
        usesTabletLayout || player.currentTrack == nil ? 0 : 72
    }

    private func playAlbum() {
        guard let firstTrack = album.tracks.first else { return }
        player.play(firstTrack, from: album.tracks)

        withAnimation(AriaMotion.playerSpring) {
            player.showPlayer()
        }
    }

    private func shuffleAlbum() {
        let tracks = album.tracks.shuffled()
        guard let firstTrack = tracks.first else { return }
        player.play(firstTrack, from: tracks)

        withAnimation(AriaMotion.playerSpring) {
            player.showPlayer()
        }
    }

    private func deleteAlbum() {
        isDeletingAlbum = true
        Task {
            do {
                _ = try await player.deleteAlbum(album)
                isDeletingAlbum = false
                dismiss()
            } catch {
                isDeletingAlbum = false
                albumDeletionError = error.localizedDescription
            }
        }
    }
}

private struct PlaylistDetailView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var selectedCoverItem: PhotosPickerItem?
    @State private var isImportingCover = false
    @State private var coverImportError: String?

    let playlist: AriaPlaylist

    private var currentPlaylist: AriaPlaylist {
        player.playlists.first { $0.id == playlist.id } ?? playlist
    }

    var body: some View {
        ScrollToTopScrollView(bottomClearance: scrollButtonBottomClearance) {
            LazyVStack(alignment: .leading, spacing: 24) {
                playlistHeader

                DetailPlayButton(title: "Play playlist", isDisabled: currentPlaylist.tracks.isEmpty) {
                    playPlaylist()
                }

                LazyVStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Songs")

                    if currentPlaylist.tracks.isEmpty {
                        Text("This playlist is empty.")
                            .font(.subheadline)
                            .foregroundStyle(.ariaTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(currentPlaylist.tracks) { track in
                            TrackRow(
                                track: track,
                                source: currentPlaylist.tracks,
                                playlistForRemoval: currentPlaylist
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, usesTabletLayout ? 36 : 20)
            .padding(.top, usesTabletLayout ? 30 : 18)
            .padding(.bottom, 32)
            .frame(maxWidth: usesTabletLayout ? 920 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(Color.ariaBackground.ignoresSafeArea())
        .navigationTitle(currentPlaylist.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") {
                    beginRename()
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .alert("Rename playlist", isPresented: $isRenaming) {
            TextField("Playlist name", text: $draftTitle)

            Button("Cancel", role: .cancel) { }

            Button("Save") {
                player.rename(currentPlaylist, to: draftTitle)
            }
        } message: {
            Text("Choose a name for this playlist.")
        }
        .alert(
            "Couldn’t Update Cover",
            isPresented: Binding(
                get: { coverImportError != nil },
                set: { if !$0 { coverImportError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(coverImportError ?? "Please choose another image.")
        }
        .onChange(of: selectedCoverItem) { _, item in
            guard let item else { return }
            Task { await importCover(from: item) }
        }
    }

    private var playlistHeader: some View {
        VStack(spacing: 18) {
            playlistArtwork

            if player.canCustomize(currentPlaylist) {
                coverControls
            }

            VStack(spacing: 7) {
                Text("Playlist")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.ariaAccent)

                Text(currentPlaylist.title)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.ariaTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(songCountText(currentPlaylist.tracks.count))
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var usesTabletLayout: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && horizontalSizeClass == .regular
    }

    private var scrollButtonBottomClearance: CGFloat {
        usesTabletLayout || player.currentTrack == nil ? 0 : 72
    }

    private var playlistArtwork: some View {
        PlaylistArtwork(
            playlist: currentPlaylist,
            size: usesTabletLayout ? 280 : 196,
            cornerRadius: 10
        )
        .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 14)
    }

    private var coverControls: some View {
        HStack(spacing: 10) {
            PhotosPicker(selection: $selectedCoverItem, matching: .images) {
                HStack(spacing: 8) {
                    if isImportingCover {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.ariaTextPrimary)
                    } else {
                        Image(systemName: "photo.badge.plus")
                    }

                    Text(currentPlaylist.coverImageData == nil ? "Add cover" : "Change cover")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ariaTextPrimary)
                .padding(.horizontal, 14)
                .frame(height: 42)
                .background(.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.97))
            .disabled(isImportingCover)

            if currentPlaylist.coverImageData != nil {
                Button(role: .destructive) {
                    withAnimation(AriaMotion.quickSpring) {
                        player.setCoverImageData(nil, for: currentPlaylist)
                    }
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .background(.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(AriaPressButtonStyle(pressedScale: 0.97))
            }
        }
    }

    @MainActor
    private func importCover(from item: PhotosPickerItem) async {
        isImportingCover = true
        defer {
            isImportingCover = false
            selectedCoverItem = nil
        }

        do {
            guard let originalData = try await item.loadTransferable(type: Data.self),
                  let coverData = compressedCoverData(from: originalData) else {
                coverImportError = "The selected file could not be read as an image."
                return
            }

            withAnimation(AriaMotion.quickSpring) {
                player.setCoverImageData(coverData, for: currentPlaylist)
            }
        } catch {
            coverImportError = error.localizedDescription
        }
    }

    private func compressedCoverData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }

        let maxDimension: CGFloat = 1_200
        let longestSide = max(image.size.width, image.size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(
            width: max(1, image.size.width * scale),
            height: max(1, image.size.height * scale)
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let resizedImage = renderer.image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        return resizedImage.jpegData(compressionQuality: 0.84)
    }

    private func playPlaylist() {
        player.playPlaylist(currentPlaylist)

        withAnimation(AriaMotion.playerSpring) {
            player.showPlayer()
        }
    }

    private func beginRename() {
        draftTitle = currentPlaylist.title
        isRenaming = true
    }
}

private struct DetailPlayButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: "play.fill")
                .font(.headline)
                .foregroundStyle(.ariaBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ariaAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .animation(AriaMotion.fast, value: isDisabled)
    }
}

private struct MobileDownloadMusicSheet: View {
    @EnvironmentObject private var player: PlayerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var link = ""
    @State private var album = ""
    @State private var albumArtist = ""
    @State private var year = ""
    @State private var youtubeMusicQuery = ""
    @State private var visibleYouTubeResultCount = 3
    @State private var searchCategory: YouTubeMusicSearchCategory = .albums
    @State private var manualCategory: YouTubeMusicSearchCategory = .albums

    private var canStartDownload: Bool {
        !trimmed(link).isEmpty
        && (manualCategory != .albums || (!trimmed(album).isEmpty && !trimmed(albumArtist).isEmpty))
        && !player.isDownloadStarting
        && player.downloadJob?.isActive != true
    }

    private var canSearchYouTubeMusic: Bool {
        !trimmed(youtubeMusicQuery).isEmpty && !player.isSearchingYouTubeMusic
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Search YouTube Music") {
                    Picker("Type", selection: $searchCategory) {
                        ForEach(YouTubeMusicSearchCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack(spacing: 10) {
                        TextField(searchPlaceholder, text: $youtubeMusicQuery)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                            .onSubmit {
                                searchYouTubeMusic()
                            }

                        Button {
                            searchYouTubeMusic()
                        } label: {
                            if player.isSearchingYouTubeMusic {
                                ProgressView()
                            } else {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .disabled(!canSearchYouTubeMusic)
                        .accessibilityLabel("Search YouTube Music")
                    }

                    if let error = player.youtubeMusicSearchError {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }

                    searchResults

                    if visibleYouTubeResultCount < resultCount {
                        Button {
                            visibleYouTubeResultCount = min(
                                visibleYouTubeResultCount + 3,
                                resultCount
                            )
                        } label: {
                            HStack {
                                Text("Showing \(visibleYouTubeResultCount) of \(resultCount)")
                                    .font(.caption)
                                    .foregroundStyle(.ariaTextSecondary)

                                Spacer()

                                Label("Load More", systemImage: "chevron.down")
                                    .font(.subheadline.weight(.semibold))
                            }
                        }
                    }
                }

                Section("Add Link Manually") {
                    Picker("Download as", selection: $manualCategory) {
                        ForEach(YouTubeMusicSearchCategory.allCases) { category in
                            Text(category.rawValue).tag(category)
                        }
                    }

                    TextField("YouTube Music link", text: $link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    if manualCategory == .albums {
                        TextField("Album name", text: $album)
                        TextField("Album artist", text: $albumArtist)
                        TextField("Year", text: $year)
                            .keyboardType(.numberPad)
                    }
                }

                if let downloadJob = player.downloadJob {
                    Section("Progress") {
                        MobileDownloadProgressView(job: downloadJob)
                    }
                }

                if let error = player.downloadErrorMessage {
                    Section("Problem") {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        Task {
                            await player.startDownload(
                                link: link,
                                album: manualCategory == .albums ? album : String(manualCategory.rawValue.dropLast()),
                                albumArtist: manualCategory == .albums ? albumArtist : "YouTube Music",
                                year: year,
                                kind: manualCategory.downloadKind
                            )
                        }
                    } label: {
                        HStack {
                            Spacer()

                            if player.isDownloadStarting {
                                ProgressView()
                                    .tint(.ariaBackground)
                            } else {
                                Label("Download Link", systemImage: "arrow.down.circle.fill")
                                    .font(.headline)
                            }

                            Spacer()
                        }
                    }
                    .disabled(!canStartDownload)
                    .listRowBackground(Color.ariaAccent.opacity(canStartDownload ? 1 : 0.4))
                    .foregroundStyle(Color.ariaBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.ariaBackground)
            .navigationTitle("Download Music")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(player.downloadJob?.isFinished == true ? "Close" : "Cancel") {
                        if player.downloadJob?.isFinished == true {
                            player.clearFinishedDownload()
                        }

                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(.ariaAccent)
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func searchYouTubeMusic() {
        guard canSearchYouTubeMusic else { return }
        let query = youtubeMusicQuery
        visibleYouTubeResultCount = 3

        Task {
            await player.searchYouTubeMusic(query: query, category: searchCategory)
        }
    }

    private var resultCount: Int {
        switch searchCategory {
        case .albums: player.youtubeMusicResults.count
        case .songs: player.youtubeMusicSongResults.count
        case .playlists: player.youtubeMusicPlaylistResults.count
        }
    }

    private var searchPlaceholder: String {
        switch searchCategory {
        case .albums: "Album or artist"
        case .songs: "Song or artist"
        case .playlists: "Playlist name"
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        switch searchCategory {
        case .albums:
            ForEach(Array(player.youtubeMusicResults.prefix(visibleYouTubeResultCount))) { result in
                MobileYouTubeMusicAlbumResultRow(result: result)
            }
        case .songs:
            ForEach(Array(player.youtubeMusicSongResults.prefix(visibleYouTubeResultCount))) { result in
                MobileYouTubeMusicSongResultRow(result: result)
            }
        case .playlists:
            ForEach(Array(player.youtubeMusicPlaylistResults.prefix(visibleYouTubeResultCount))) { result in
                MobileYouTubeMusicPlaylistResultRow(result: result)
            }
        }
    }
}

private struct MobileYouTubeMusicAlbumResultRow: View {
    @EnvironmentObject private var player: PlayerViewModel

    let result: YouTubeMusicAlbumResult

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: result.artworkURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    artworkPlaceholder
                case .empty:
                    ProgressView()
                @unknown default:
                    artworkPlaceholder
                }
            }
            .frame(width: 54, height: 54)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(result.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariaTextPrimary)
                    .lineLimit(2)

                HStack(spacing: 0) {
                    ArtistNameLink(name: result.artist)
                    if !result.year.isEmpty {
                        Text(" • \(result.year)")
                    }
                }
                    .font(.caption)
                    .foregroundStyle(.ariaTextSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            resultAction
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private var resultAction: some View {
        if player.isAlbumDownloaded(result) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.ariaAccent)
                .accessibilityLabel("Downloaded")
        } else if player.isDownloading(result) {
            ProgressView()
                .tint(.ariaAccent)
                .accessibilityLabel("Downloading")
        } else {
            Button {
                Task {
                    await player.startDownload(result)
                }
            } label: {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.ariaAccent)
            .disabled(player.isDownloadStarting || player.downloadJob?.isActive == true)
            .accessibilityLabel("Download \(result.title)")
        }
    }

    private var artworkPlaceholder: some View {
        Image(systemName: "square.stack")
            .foregroundStyle(.ariaTextSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

}

private struct MobileYouTubeMusicSongResultRow: View {
    @EnvironmentObject private var player: PlayerViewModel
    let result: YouTubeMusicSongResult

    var body: some View {
        MobileYouTubeMusicDownloadResultRow(
            title: result.title,
            subtitle: result.artist,
            artistName: result.artist,
            artworkURL: result.artworkURL,
            isDownloaded: player.isSongDownloaded(result)
        ) {
            Task { await player.startDownload(result) }
        }
    }
}

private struct MobileYouTubeMusicPlaylistResultRow: View {
    @EnvironmentObject private var player: PlayerViewModel
    let result: YouTubeMusicPlaylistResult

    var body: some View {
        MobileYouTubeMusicDownloadResultRow(
            title: result.title,
            subtitle: "Playlist • \(result.curator)",
            artworkURL: result.artworkURL,
            isDownloaded: false
        ) {
            Task { await player.startDownload(result) }
        }
    }
}

private struct MobileYouTubeMusicDownloadResultRow: View {
    @EnvironmentObject private var player: PlayerViewModel
    let title: String
    let subtitle: String
    var artistName: String? = nil
    let artworkURL: URL?
    let isDownloaded: Bool
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: artworkURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else if case .empty = phase {
                    ProgressView()
                } else {
                    Image(systemName: "music.note")
                        .foregroundStyle(.ariaTextSecondary)
                }
            }
            .frame(width: 54, height: 54)
            .background(.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ariaTextPrimary)
                    .lineLimit(2)
                Group {
                    if let artistName {
                        ArtistNameLink(name: artistName)
                    } else {
                        Text(subtitle)
                    }
                }
                .font(.caption)
                .foregroundStyle(.ariaTextSecondary)
                .lineLimit(1)
            }
            Spacer(minLength: 6)
            if isDownloaded {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.ariaAccent)
                    .accessibilityLabel("Downloaded")
            } else if player.isDownloadStarting || player.downloadJob?.isActive == true {
                ProgressView().tint(.ariaAccent)
            } else {
                Button(action: onDownload) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.ariaAccent)
                .accessibilityLabel("Download \(title)")
            }
        }
        .padding(.vertical, 3)
    }
}

private struct MobileDownloadProgressView: View {
    let job: AriaDownloadJob

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(statusTitle, systemImage: statusImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusColor)

                Spacer()

                Text("\(Int(job.progressFraction * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.ariaTextSecondary)
            }

            ProgressView(value: job.progressFraction)
                .tint(.ariaAccent)

            Text(job.phase)
                .font(.caption)
                .foregroundStyle(.ariaTextSecondary)

            Text(job.message)
                .font(.caption)
                .foregroundStyle(.ariaTextSecondary)
                .lineLimit(3)

            if let newFiles = job.newFiles, job.isSuccessful {
                Text("\(newFiles) new song\(newFiles == 1 ? "" : "s") added.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaAccent)
            }

            if let reusedFiles = job.reusedFiles, reusedFiles > 0, job.isSuccessful {
                Text("\(reusedFiles) existing song\(reusedFiles == 1 ? "" : "s") reused without downloading a duplicate.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaAccent)
            }

            if let playlistTrackCount = job.playlistTrackCount, job.isSuccessful {
                Text("Aria playlist created with \(playlistTrackCount) songs.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaAccent)
            }

            if let error = job.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 4)
    }

    private var statusTitle: String {
        switch job.status {
        case "succeeded":
            "Done"
        case "failed":
            "Failed"
        default:
            "Downloading"
        }
    }

    private var statusImage: String {
        switch job.status {
        case "succeeded":
            "checkmark.circle.fill"
        case "failed":
            "exclamationmark.triangle.fill"
        default:
            "arrow.down.circle.fill"
        }
    }

    private var statusColor: Color {
        switch job.status {
        case "succeeded":
            .ariaAccent
        case "failed":
            .orange
        default:
            .ariaTextPrimary
        }
    }
}

private struct MissingLibraryItemView: View {
    let title: String

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.ariaTextPrimary)

            Text("Go back to the library and choose another item.")
                .font(.subheadline)
                .foregroundStyle(.ariaTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(Color.ariaBackground.ignoresSafeArea())
    }
}

private func songCountText(_ count: Int) -> String {
    count == 1 ? "1 song" : "\(count) songs"
}
