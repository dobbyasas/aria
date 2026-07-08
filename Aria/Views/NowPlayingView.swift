import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @GestureState private var pullDistance: CGFloat = 0

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
                            .contentShape(Rectangle())
                            .gesture(pullToLibraryGesture)

                        ArtworkView(track: track, size: artworkSize, cornerRadius: 8)
                            .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 18)

                        songIdentity(for: track)

                        progressSection(for: track)

                        mainControls

                        volumeControl

                        queuePreview
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .frame(maxWidth: 440)
                    .frame(maxWidth: .infinity)
                    .offset(y: min(pullDistance * 0.18, 18))
                    .animation(.spring(response: 0.28, dampingFraction: 0.82), value: pullDistance)
                }
            }
        }
    }

    private func background(for track: Track) -> some View {
        ZStack {
            Color.ariaBackground

            LinearGradient(
                colors: [
                    Color(hex: track.artwork.topHex).opacity(0.68),
                    Color(hex: track.artwork.bottomHex).opacity(0.52),
                    .ariaBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Color.ariaBackground.opacity(0.22)
        }
        .ignoresSafeArea()
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .gesture(pullToLibraryGesture)
            .accessibilityLabel("Pull down to open library")
    }

    private var pullToLibraryGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($pullDistance) { value, state, _ in
                guard value.translation.height > 0 else { return }
                state = value.translation.height
            }
            .onEnded { value in
                guard value.translation.height > 72 || value.predictedEndTranslation.height > 120 else { return }

                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    player.hidePlayer()
                }
            }
    }

    private func songIdentity(for track: Track) -> some View {
        VStack(spacing: 8) {
            Text(track.title)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.ariaTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)

            Text(track.artist)
                .font(.title3.weight(.medium))
                .foregroundStyle(.ariaTextSecondary)
                .lineLimit(1)
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
                Spacer()
                Text(track.duration.ariaClockTime)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.ariaTextSecondary)
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
            .accessibilityLabel(player.isShuffleEnabled ? "Turn shuffle off" : "Turn shuffle on")

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.ariaTextPrimary)
                    .frame(width: 48, height: 48)
            }
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
            }
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.ariaTextPrimary)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("Next song")

            Button {
                player.cycleRepeatMode()
            } label: {
                Image(systemName: player.repeatMode.systemImage)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(player.repeatMode == .off ? .ariaTextSecondary : .ariaAccent)
                    .frame(width: 42, height: 42)
            }
            .accessibilityLabel(player.repeatMode.title)
        }
    }

    private var volumeControl: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .foregroundStyle(.ariaTextSecondary)

            Slider(value: $player.volume, in: 0...1)
                .tint(.ariaTextPrimary)

            Image(systemName: "speaker.wave.3.fill")
                .foregroundStyle(.ariaTextSecondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
    }

    private var queuePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Up next")

            if player.upNext.isEmpty {
                Text("End of queue")
                    .font(.subheadline)
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(player.upNext) { track in
                        TrackRow(
                            track: track,
                            source: player.queue,
                            showAlbum: false,
                            removesFromQueueOnLeftSwipe: true
                        )
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
