import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @GestureState private var sectionSwipeDistance: CGFloat = 0
    @State private var selectedSection: LibrarySection = .songs
    @State private var isDownloadSheetPresented = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    header
                    sectionPicker
                    sectionContent
                        .id(selectedSection)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .offset(x: clampedSectionSwipeOffset)
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 24)
                .animation(AriaMotion.quickSpring, value: selectedSection)
            }
            .background(Color.ariaBackground.ignoresSafeArea())
            .simultaneousGesture(sectionSwipeGesture)
            .navigationDestination(for: LibraryRoute.self) { route in
                destination(for: route)
            }
        }
        .background(Color.ariaBackground.ignoresSafeArea())
        .sheet(isPresented: $isDownloadSheetPresented) {
            MobileDownloadMusicSheet()
                .environmentObject(player)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Library")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.ariaTextPrimary)

                Text("Songs streamed from your Fedora server.")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
            }

            Spacer()

            Button {
                isDownloadSheetPresented = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Color.ariaBackground)
                    .frame(width: 42, height: 42)
                    .background(Color.ariaAccent)
                    .clipShape(Circle())
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.94))
            .disabled(player.isDownloadStarting || player.downloadJob?.isActive == true)
            .opacity(player.isDownloadStarting || player.downloadJob?.isActive == true ? 0.55 : 1)
            .accessibilityLabel("Download music")
        }
    }

    private var sectionPicker: some View {
        Picker("Library section", selection: $selectedSection) {
            ForEach(LibrarySection.allCases) { section in
                Text(section.title).tag(section)
            }
        }
        .pickerStyle(.segmented)
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
        LazyVStack(alignment: .leading, spacing: 10) {
            SectionTitle(title: "Songs")

            catalogStatus

            if player.catalog.isEmpty, !player.isCatalogLoading {
                Text("No songs loaded yet. Start the Fedora server and tap Retry.")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(player.catalog) { track in
                    TrackRow(track: track, source: player.catalog)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
    }

    @ViewBuilder
    private var catalogStatus: some View {
        if player.isCatalogLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(.ariaAccent)

                Text("Loading songs from Fedora...")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
            }
            .padding(.vertical, 6)
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

    private var albumsSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Albums")

            ForEach(player.albums) { album in
                AlbumRow(album: album)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var playlistsSection: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(AriaMotion.quickSpring) {
                    _ = player.createPlaylist()
                }
            } label: {
                Label("Create playlist", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(.ariaBackground)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.ariaAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))

            SectionTitle(title: "Playlists")

            ForEach(player.playlists) { playlist in
                PlaylistRow(playlist: playlist)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
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

    private var clampedSectionSwipeOffset: CGFloat {
        min(max(sectionSwipeDistance * 0.08, -14), 14)
    }

    private var sectionSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .updating($sectionSwipeDistance) { value, state, _ in
                guard isSectionSwipe(value) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isSectionSwipe(value) else { return }

                let distance = abs(value.translation.width)
                let predictedDistance = abs(value.predictedEndTranslation.width)
                guard distance > 140 || predictedDistance > 210 else { return }

                let targetSection = value.translation.width < 0 ? selectedSection.next : selectedSection.previous
                guard targetSection != selectedSection else { return }

                withAnimation(AriaMotion.quickSpring) {
                    selectedSection = targetSection
                }
            }
    }

    private func isSectionSwipe(_ value: DragGesture.Value) -> Bool {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)
        return horizontalDistance > 32 && horizontalDistance > verticalDistance * 1.55
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

    var next: LibrarySection {
        switch self {
        case .songs:
            .albums
        case .albums:
            .playlists
        case .playlists:
            .playlists
        }
    }

    var previous: LibrarySection {
        switch self {
        case .songs:
            .songs
        case .albums:
            .songs
        case .playlists:
            .albums
        }
    }
}

private struct AlbumRow: View {
    let album: AriaAlbum

    var body: some View {
        NavigationLink(value: LibraryRoute.album(album.id)) {
            HStack(spacing: 14) {
                if let artworkTrack = album.artworkTrack {
                    ArtworkView(track: artworkTrack, size: 76)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(album.title)
                        .font(.headline)
                        .foregroundStyle(.ariaTextPrimary)
                        .lineLimit(1)

                    Text(album.artist)
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                        .lineLimit(1)

                    Text(String(album.year))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.ariaAccent)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaTextSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
        .padding(.vertical, 6)
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
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var playlistArtwork: some View {
        if let firstTrack = playlist.tracks.first {
            ArtworkView(track: firstTrack, size: 76)
        } else {
            ZStack {
                Color.ariaSurfaceRaised

                Image(systemName: "music.note.list")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.ariaTextSecondary)
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct AlbumDetailView: View {
    @EnvironmentObject private var player: PlayerViewModel

    let album: AriaAlbum

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 24) {
                albumHeader

                DetailPlayButton(title: "Play album") {
                    playAlbum()
                }

                LazyVStack(alignment: .leading, spacing: 10) {
                    SectionTitle(title: "Songs")

                    ForEach(album.tracks) { track in
                        TrackRow(track: track, source: album.tracks, showAlbum: false)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
        }
        .background(Color.ariaBackground.ignoresSafeArea())
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var albumHeader: some View {
        VStack(spacing: 18) {
            if let artworkTrack = album.artworkTrack {
                ArtworkView(track: artworkTrack, size: 196)
                    .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 14)
            }

            VStack(spacing: 7) {
                Text("Album")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.ariaAccent)

                Text(album.title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(.ariaTextPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(verbatim: "\(album.artist) • \(String(album.year)) • \(songCountText(album.tracks.count))")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func playAlbum() {
        guard let firstTrack = album.tracks.first else { return }
        player.play(firstTrack, from: album.tracks)

        withAnimation(AriaMotion.playerSpring) {
            player.showPlayer()
        }
    }
}

private struct PlaylistDetailView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @State private var isRenaming = false
    @State private var draftTitle = ""

    let playlist: AriaPlaylist

    private var currentPlaylist: AriaPlaylist {
        player.playlists.first { $0.id == playlist.id } ?? playlist
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
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
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 32)
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
    }

    private var playlistHeader: some View {
        VStack(spacing: 18) {
            playlistArtwork

            VStack(spacing: 7) {
                Text("Playlist")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.ariaAccent)

                Text(currentPlaylist.title)
                    .font(.system(size: 32, weight: .black, design: .rounded))
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

    @ViewBuilder
    private var playlistArtwork: some View {
        if let firstTrack = currentPlaylist.tracks.first {
            ArtworkView(track: firstTrack, size: 196)
                .shadow(color: .black.opacity(0.28), radius: 22, x: 0, y: 14)
        } else {
            ZStack {
                Color.ariaSurfaceRaised

                Image(systemName: "music.note.list")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.ariaTextSecondary)
            }
            .frame(width: 196, height: 196)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 18, x: 0, y: 12)
        }
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

    private var canStartDownload: Bool {
        !trimmed(link).isEmpty
        && !trimmed(album).isEmpty
        && !trimmed(albumArtist).isEmpty
        && !player.isDownloadStarting
        && player.downloadJob?.isActive != true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Download") {
                    TextField("Playlist / album link", text: $link)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    TextField("Album name", text: $album)
                    TextField("Album artist", text: $albumArtist)
                    TextField("Year", text: $year)
                        .keyboardType(.numberPad)
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
                                album: album,
                                albumArtist: albumArtist,
                                year: year
                            )
                        }
                    } label: {
                        HStack {
                            Spacer()

                            if player.isDownloadStarting {
                                ProgressView()
                                    .tint(.ariaBackground)
                            } else {
                                Label("Download", systemImage: "arrow.down.circle.fill")
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
