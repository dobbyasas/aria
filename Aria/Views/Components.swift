import SwiftUI

struct ArtworkView: View {
    let track: Track
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: track.artwork.topHex), Color(hex: track.artwork.bottomHex)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: track.artwork.symbolName)
                .font(.system(size: size * 0.28, weight: .semibold))
                .foregroundStyle(.white.opacity(0.88))
                .shadow(radius: 16)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
    }
}

struct TrackRow: View {
    @EnvironmentObject private var player: PlayerViewModel
    @GestureState private var horizontalDrag: CGFloat = 0
    @State private var restingOffset: CGFloat = 0
    @State private var isAddToPlaylistPresented = false
    @State private var isTapSuppressed = false

    let track: Track
    var source: [Track]
    var showAlbum = true
    var playlistForRemoval: AriaPlaylist? = nil
    var removesFromQueueOnLeftSwipe = false

    var body: some View {
        ZStack {
            swipeActionBackground

            rowSurface
                .offset(x: rowOffset)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .simultaneousGesture(swipeGesture)
        .animation(.spring(response: 0.24, dampingFraction: 0.86), value: restingOffset)
        .sheet(isPresented: $isAddToPlaylistPresented) {
            AddToPlaylistSheet(track: track)
                .environmentObject(player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ariaBackground)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 52)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .foregroundStyle(.ariaTextPrimary)
                        .font(.headline)
                        .lineLimit(1)

                    if track.isExplicit {
                        Text("E")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.ariaBackground)
                            .padding(.horizontal, 4)
                            .background(.ariaTextSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }

                Text(showAlbum ? "\(track.artist) • \(track.album)" : track.artist)
                    .foregroundStyle(.ariaTextSecondary)
                    .font(.subheadline)
                    .lineLimit(1)
            }

            Spacer()

            if player.currentTrack?.id == track.id {
                Image(systemName: player.isPlaying ? "waveform" : "pause.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.ariaAccent)
            } else {
                Text(track.duration.ariaClockTime)
                    .font(.caption)
                    .foregroundStyle(.ariaTextSecondary)
            }
        }
        .contentShape(Rectangle())
    }

    private var rowSurface: some View {
        rowContent
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(rowOffset == 0 ? Color.clear : Color.ariaBackground)
            .contentShape(Rectangle())
            .onTapGesture {
                handleRowTap()
            }
    }

    private var rowOffset: CGFloat {
        let proposedOffset = restingOffset + horizontalDrag

        if proposedOffset > 0 {
            return playlistForRemoval == nil ? 0 : min(proposedOffset, maxRightSwipe)
        }

        return max(proposedOffset, -leftSwipeLimit)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .local)
            .updating($horizontalDrag) { value, state, _ in
                guard isHorizontalSwipe(value) else { return }

                if value.translation.width > 0, playlistForRemoval != nil || restingOffset < 0 {
                    state = value.translation.width
                } else if value.translation.width < 0 {
                    state = value.translation.width
                }
            }
            .onEnded { value in
                guard isHorizontalSwipe(value) else { return }
                suppressTapBriefly()

                let proposedOffset = restingOffset + value.translation.width
                let predictedOffset = restingOffset + value.predictedEndTranslation.width

                if proposedOffset < 0 {
                    if removesFromQueueOnLeftSwipe {
                        handleQueueLeftSwipe(offset: proposedOffset, predictedOffset: predictedOffset)
                    } else {
                        handleLeftSwipe(offset: proposedOffset, predictedOffset: predictedOffset)
                    }
                } else if proposedOffset > 0, let playlistForRemoval {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                        if proposedOffset > rightCommitThreshold || predictedOffset > rightCommitThreshold {
                            player.remove(track, from: playlistForRemoval)
                        }
                        restingOffset = 0
                    }
                } else {
                    closeSwipeActions()
                }
            }
    }

    private var swipeActionBackground: some View {
        ZStack {
            Color.clear

            if rowOffset > 0 {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)

                    Spacer()
                }
                .padding(.leading, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.red.opacity(0.84))
            } else if rowOffset < 0, removesFromQueueOnLeftSwipe {
                HStack {
                    Spacer()

                    Image(systemName: "trash.fill")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                }
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.red.opacity(0.84))
            } else if rowOffset < 0 {
                HStack(spacing: 8) {
                    Spacer()

                    Button {
                        suppressTapBriefly()
                        addTrackToFront()
                    } label: {
                        Image(systemName: "arrow.up.to.line")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.ariaBackground)
                            .frame(width: actionButtonSize, height: actionButtonSize)
                            .background(.ariaAccent)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to front")

                    Button {
                        suppressTapBriefly()
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                            restingOffset = 0
                        }
                        isAddToPlaylistPresented = true
                    } label: {
                        Image(systemName: "text.badge.plus")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.ariaTextPrimary)
                            .frame(width: actionButtonSize, height: actionButtonSize)
                            .background(.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add to playlist")
                }
                .padding(.trailing, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.ariaSurfaceRaised.opacity(0.92))
            }
        }
    }

    private var actionButtonSize: CGFloat {
        56
    }

    private var openLeftOffset: CGFloat {
        actionButtonSize * 2 + 28
    }

    private var maxLeftSwipe: CGFloat {
        screenWidth * 0.58
    }

    private var leftSwipeLimit: CGFloat {
        removesFromQueueOnLeftSwipe ? maxRightSwipe : maxLeftSwipe
    }

    private var maxRightSwipe: CGFloat {
        min(screenWidth * 0.34, 132)
    }

    private var revealThreshold: CGFloat {
        screenWidth * 0.10
    }

    private var leftCommitThreshold: CGFloat {
        screenWidth * 0.50
    }

    private var rightCommitThreshold: CGFloat {
        max(screenWidth * 0.16, 72)
    }

    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    private func handleRowTap() {
        guard !isTapSuppressed else { return }

        if restingOffset != 0 {
            closeSwipeActions()
            return
        }

        player.play(track, from: source)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            player.showPlayer()
        }
    }

    private func handleLeftSwipe(offset: CGFloat, predictedOffset: CGFloat) {
        let leftOffset = abs(offset)
        let predictedLeftOffset = abs(predictedOffset)

        if leftOffset >= leftCommitThreshold || predictedLeftOffset >= leftCommitThreshold {
            addTrackToFront()
        } else if leftOffset >= revealThreshold {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                restingOffset = -openLeftOffset
            }
        } else {
            closeSwipeActions()
        }
    }

    private func handleQueueLeftSwipe(offset: CGFloat, predictedOffset: CGFloat) {
        let leftOffset = abs(offset)
        let predictedLeftOffset = abs(predictedOffset)

        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            if leftOffset > rightCommitThreshold || predictedLeftOffset > rightCommitThreshold {
                player.removeFromQueue(track)
            }

            restingOffset = 0
        }
    }

    private func addTrackToFront() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            player.addToFront(track)
            restingOffset = 0
        }
    }

    private func closeSwipeActions() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
            restingOffset = 0
        }
    }

    private func suppressTapBriefly() {
        isTapSuppressed = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            isTapSuppressed = false
        }
    }

    private func isHorizontalSwipe(_ value: DragGesture.Value) -> Bool {
        let width = abs(value.translation.width)
        let height = abs(value.translation.height)
        return width > 18 && width > height * 1.25
    }
}

struct SectionTitle: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(.ariaTextPrimary)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.ariaAccent)
            }
        }
    }
}

struct AddToPlaylistButton: View {
    @EnvironmentObject private var player: PlayerViewModel
    @State private var isPickerPresented = false

    let track: Track
    var size: CGFloat = 44
    var hasBackground = true

    var body: some View {
        Button {
            isPickerPresented = true
        } label: {
            Image(systemName: "text.badge.plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.ariaTextPrimary)
                .frame(width: size, height: size)
                .background(hasBackground ? .white.opacity(0.08) : .clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add to playlist")
        .sheet(isPresented: $isPickerPresented) {
            AddToPlaylistSheet(track: track)
                .environmentObject(player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ariaBackground)
        }
    }
}

private struct AddToPlaylistSheet: View {
    @EnvironmentObject private var player: PlayerViewModel
    @Environment(\.dismiss) private var dismiss

    let track: Track

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    trackHeader
                    createPlaylistButton

                    VStack(alignment: .leading, spacing: 8) {
                        SectionTitle(title: "Playlists")

                        ForEach(player.playlists) { playlist in
                            AddToPlaylistRow(track: track, playlist: playlist)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 32)
            }
            .background(Color.ariaBackground.ignoresSafeArea())
            .navigationTitle("Add to playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                }
            }
        }
        .tint(.ariaAccent)
    }

    private var trackHeader: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 54)

            VStack(alignment: .leading, spacing: 4) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.ariaTextPrimary)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(12)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var createPlaylistButton: some View {
        Button {
            player.createPlaylist(containing: track)
        } label: {
            Label("Create playlist with song", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(.ariaBackground)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ariaAccent)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct AddToPlaylistRow: View {
    @EnvironmentObject private var player: PlayerViewModel

    let track: Track
    let playlist: AriaPlaylist

    private var containsTrack: Bool {
        player.playlist(playlist, contains: track)
    }

    var body: some View {
        Button {
            player.add(track, to: playlist)
        } label: {
            HStack(spacing: 14) {
                PlaylistArtwork(playlist: playlist, size: 64)

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

                Image(systemName: containsTrack ? "checkmark.circle.fill" : "plus.circle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(containsTrack ? .ariaAccent : .ariaTextSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 6)
    }
}

private struct PlaylistArtwork: View {
    let playlist: AriaPlaylist
    var size: CGFloat

    var body: some View {
        if let firstTrack = playlist.tracks.first {
            ArtworkView(track: firstTrack, size: size)
        } else {
            ZStack {
                Color.ariaSurfaceRaised

                Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.32, weight: .semibold))
                    .foregroundStyle(.ariaTextSecondary)
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerViewModel

    var body: some View {
        if let track = player.currentTrack {
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        player.showPlayer()
                    }
                } label: {
                    HStack(spacing: 12) {
                        ArtworkView(track: track, size: 44, cornerRadius: 6)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.ariaTextPrimary)
                                .lineLimit(1)

                            Text(track.artist)
                                .font(.caption)
                                .foregroundStyle(.ariaTextSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                AddToPlaylistButton(track: track, size: 36, hasBackground: false)

                Button {
                    player.playPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.ariaTextPrimary)
                        .frame(width: 40, height: 40)
                }
                .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ariaSurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}
