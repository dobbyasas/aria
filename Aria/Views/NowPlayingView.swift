import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @GestureState private var pullDistance: CGFloat = 0
    @GestureState private var trackSwipeDistance: CGFloat = 0
    @State private var backgroundArtwork: ArtworkPalette?
    @State private var backgroundArtworkTrackID: UUID?

    var body: some View {
        Group {
            if let track = player.currentTrack {
                playerView(for: track)
            } else {
                emptyState
            }
        }
    }

    private func playerView(for track: Track) -> some View {
        GeometryReader { geometry in
            let artworkSize = min(geometry.size.width - 56, 340)

            ZStack {
                background(for: track)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        pullHandle
                            .padding(.top, 10)

                        header(for: track)

                        swipeableTrackIdentity(for: track, artworkSize: artworkSize)

                        progressSection(for: track)

                        mainControls

                        queuePreview
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .offset(y: min(pullDistance * 0.18, 18))
                    .animation(.spring(response: 0.24, dampingFraction: 0.84), value: pullDistance)
                }
            }
            .simultaneousGesture(pullToLibraryGesture)
            .animation(AriaMotion.fast, value: track.id)
            .task(id: track.id) {
                await loadBackgroundArtwork(for: track)
            }
        }
    }

    private func background(for track: Track) -> some View {
        let artwork = backgroundArtworkTrackID == track.id ? backgroundArtwork ?? track.artwork : track.artwork

        return ZStack {
            Color.ariaBackground

            LinearGradient(
                colors: [
                    Color(hex: artwork.topHex).opacity(0.74),
                    Color(hex: artwork.bottomHex).opacity(0.58),
                    .ariaBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Color.ariaBackground.opacity(0.22)
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.28), value: artwork)
    }

    private func header(for track: Track) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("ARIA PLAYER")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(.ariaAccent)

                Text(track.album)
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            AddToPlaylistButton(track: track)
        }
    }

    private var pullHandle: some View {
        Capsule()
            .fill(.ariaTextPrimary.opacity(0.28))
            .frame(width: 44, height: 5)
            .scaleEffect(x: 1 + min(pullDistance / 220, 0.18), y: 1, anchor: .center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .accessibilityLabel("Pull down to open library")
    }

    private var pullToLibraryGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($pullDistance) { value, state, _ in
                guard isLibraryPull(value) else { return }
                state = value.translation.height
            }
            .onEnded { value in
                guard isLibraryPull(value) else { return }
                guard value.translation.height > 42 || value.predictedEndTranslation.height > 84 else { return }

                withAnimation(AriaMotion.playerSpring) {
                    player.hidePlayer()
                }
            }
    }

    private func isLibraryPull(_ value: DragGesture.Value) -> Bool {
        let verticalDistance = value.translation.height
        let horizontalDistance = abs(value.translation.width)
        return verticalDistance > 0 && verticalDistance > horizontalDistance * 1.15
    }

    private func swipeableTrackIdentity(for track: Track, artworkSize: CGFloat) -> some View {
        VStack(spacing: 24) {
            ArtworkView(track: track, size: artworkSize, cornerRadius: 8)
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 18)
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            songIdentity(for: track)
        }
        .contentShape(Rectangle())
        .offset(x: clampedTrackSwipeOffset)
        .simultaneousGesture(trackNavigationGesture)
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: trackSwipeDistance)
    }

    private var clampedTrackSwipeOffset: CGFloat {
        min(max(trackSwipeDistance * 0.12, -18), 18)
    }

    private var trackNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .updating($trackSwipeDistance) { value, state, _ in
                guard isTrackNavigationSwipe(value) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isTrackNavigationSwipe(value) else { return }

                let committedDistance = abs(value.translation.width)
                let predictedDistance = abs(value.predictedEndTranslation.width)
                guard committedDistance > 72 || predictedDistance > 132 else { return }

                if value.translation.width < 0 {
                    player.skipToNextTrack()
                } else {
                    player.skipToPreviousTrack()
                }
            }
    }

    private func isTrackNavigationSwipe(_ value: DragGesture.Value) -> Bool {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)
        return horizontalDistance > 28 && horizontalDistance > verticalDistance * 1.35
    }

    private func loadBackgroundArtwork(for track: Track) async {
        backgroundArtworkTrackID = track.id
        backgroundArtwork = nil

        guard let artworkURL = track.artworkURL else {
            return
        }

        guard let artwork = await AriaArtworkCache.shared.palette(
            for: artworkURL,
            symbolName: track.artwork.symbolName
        ) else {
            return
        }

        guard !Task.isCancelled, player.currentTrack?.id == track.id else {
            return
        }

        withAnimation(.easeOut(duration: 0.28)) {
            backgroundArtworkTrackID = track.id
            backgroundArtwork = artwork
        }
    }

    private func songIdentity(for track: Track) -> some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.ariaTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .contentTransition(.opacity)

            Text(track.artist)
                .font(.title3.weight(.medium))
                .foregroundStyle(.ariaTextSecondary)
                .lineLimit(1)
                .contentTransition(.opacity)
        }
        .frame(maxWidth: .infinity)
    }

    private func progressSection(for track: Track) -> some View {
        VStack(spacing: 8) {
            Slider(
                value: Binding(
                    get: { player.progress },
                    set: { player.seek(toProgress: $0) }
                ),
                in: 0...1
            )
            .tint(.ariaAccent)

            HStack {
                Text(player.elapsed.ariaClockTime)
                    .contentTransition(.numericText())
                Spacer()
                Text(track.duration.ariaClockTime)
                    .contentTransition(.numericText())
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.ariaTextSecondary)
            .animation(AriaMotion.fast, value: player.elapsed)
        }
    }

    private var mainControls: some View {
        HStack(spacing: 18) {
            Button {
                player.toggleShuffle()
            } label: {
                Image(systemName: "shuffle")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(player.isShuffleEnabled ? .ariaAccent : .ariaTextSecondary)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(AriaPressButtonStyle())
            .accessibilityLabel(player.isShuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")
            .animation(AriaMotion.fast, value: player.isShuffleEnabled)

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.ariaTextPrimary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(AriaPressButtonStyle())
            .accessibilityLabel("Previous song")

            Button {
                player.playPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.ariaBackground)
                    .frame(width: 74, height: 74)
                    .background(.ariaTextPrimary)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.26), radius: 18, x: 0, y: 10)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.92))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
            .animation(AriaMotion.fast, value: player.isPlaying)

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.ariaTextPrimary)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(AriaPressButtonStyle())
            .accessibilityLabel("Next song")

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(player.repeatMode == .off ? .ariaTextSecondary : .ariaAccent)
                    .frame(width: 42, height: 42)
            }
            .buttonStyle(AriaPressButtonStyle())
            .accessibilityLabel(player.repeatMode.title)
            .animation(AriaMotion.fast, value: player.repeatMode)
        }
    }

    private var queuePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Up next")

            if player.upNextPreview.isEmpty {
                Text("End of queue")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(player.upNextPreview) { track in
                        TrackRow(
                            track: track,
                            source: player.queue,
                            showAlbum: false,
                            removesFromQueueOnLeftSwipe: true
                        )
                    }

                    if player.remainingUpNextCount > player.upNextPreview.count {
                        Text("\(player.remainingUpNextCount - player.upNextPreview.count) more in queue")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.ariaTextSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                }
            }
        }
        .padding(14)
        .background(.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var emptyState: some View {
        ZStack {
            Color.ariaBackground.ignoresSafeArea()

            VStack(spacing: 16) {
                if player.isCatalogLoading {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(.ariaAccent)

                    Text("Loading songs from Fedora")
                        .font(.title2.bold())
                        .foregroundStyle(.ariaTextPrimary)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.ariaAccent)

                    Text("Choose a song to begin")
                        .font(.title2.bold())
                        .foregroundStyle(.ariaTextPrimary)
                }

                Button("Open library") {
                    player.hidePlayer()
                }
                .buttonStyle(.borderedProminent)
                .tint(.ariaAccent)
            }
        }
    }
}
