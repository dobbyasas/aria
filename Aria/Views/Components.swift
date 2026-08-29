import SwiftUI
import UIKit

enum AriaMotion {
    static let fast = Animation.easeOut(duration: 0.18)
    static let quickSpring = Animation.spring(response: 0.24, dampingFraction: 0.86)
    static let playerSpring = Animation.spring(response: 0.32, dampingFraction: 0.86)
    static let press = Animation.spring(response: 0.18, dampingFraction: 0.78)
    static let queueReorder = Animation.interactiveSpring(response: 0.2, dampingFraction: 0.9, blendDuration: 0.08)
}

struct AriaPressButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(AriaMotion.press, value: configuration.isPressed)
    }
}

struct ArtworkView: View {
    @State private var cachedArtwork: UIImage?

    let track: Track
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            fallbackArtwork

            if let cachedArtwork {
                Image(uiImage: cachedArtwork)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .animation(AriaMotion.fast, value: track.artworkURL)
        .task(id: track.artworkURL) {
            await loadArtwork()
        }
    }

    private var fallbackArtwork: some View {
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
    }

    private func loadArtwork() async {
        guard let artworkURL = track.artworkURL else {
            cachedArtwork = nil
            return
        }

        cachedArtwork = nil

        guard let image = await AriaArtworkCache.shared.image(for: artworkURL) else {
            return
        }

        guard !Task.isCancelled, track.artworkURL == artworkURL else {
            return
        }

        withAnimation(AriaMotion.fast) {
            cachedArtwork = image
        }
    }
}

struct TrackRow: View {
    @EnvironmentObject private var player: PlayerViewModel
    @State private var isAddToPlaylistPresented = false
    @State private var isTrackActionsPresented = false

    let track: Track
    var source: [Track]
    var showAlbum = true
    var playlistForRemoval: AriaPlaylist? = nil
    var usesCustomQueueSwipe = false
    var queueDragItemProvider: (() -> NSItemProvider)? = nil

    var body: some View {
        rowContent
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .animation(AriaMotion.fast, value: player.currentTrack?.id)
            .swipeActions(edge: .trailing, allowsFullSwipe: !usesCustomQueueSwipe) {
                trailingSwipeActions
            }
            .swipeActions(edge: .leading, allowsFullSwipe: playlistForRemoval != nil) {
                leadingSwipeActions
            }
        .sheet(isPresented: $isAddToPlaylistPresented) {
            AddToPlaylistSheet(track: track)
                .environmentObject(player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ariaBackground)
        }
    }

    @ViewBuilder
    private var trailingSwipeActions: some View {
        if !usesCustomQueueSwipe {
            Button {
                addTrackToQueue()
            } label: {
                Label("Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
            .tint(.ariaAccent)

            Button {
                isAddToPlaylistPresented = true
            } label: {
                Label("Playlist", systemImage: "text.badge.plus")
            }
            .tint(.ariaSurfaceRaised)
        }
    }

    @ViewBuilder
    private var leadingSwipeActions: some View {
        if let playlistForRemoval {
            Button(role: .destructive) {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                    player.remove(track, from: playlistForRemoval)
                }
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            Button {
                handleRowTap()
            } label: {
                trackIdentity
            }
            .buttonStyle(.plain)

            trackActionButton

            if let queueDragItemProvider {
                Image(systemName: "line.3.horizontal")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(width: 44, height: 48)
                    .background(.white.opacity(0.055))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .contentShape(Rectangle())
                    .onDrag(queueDragItemProvider) {
                        QueueDragPreview(track: track)
                    }
                    .accessibilityLabel("Reorder \(track.title)")
            }
        }
        .contentShape(Rectangle())
    }

    private var trackIdentity: some View {
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
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.variableColor.iterative, options: .repeating.speed(3), isActive: player.isPlaying)
            } else if !usesCustomQueueSwipe {
                Text(track.duration.ariaClockTime)
                    .font(.caption)
                    .foregroundStyle(.ariaTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var trackActionButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isTrackActionsPresented = true
        } label: {
            Image(systemName: "ellipsis")
                .font(.headline.weight(.bold))
                .foregroundStyle(.ariaTextSecondary)
                .frame(width: 48, height: 48)
                .background(.white.opacity(isTrackActionsPresented ? 0.13 : 0.055))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.92))
        .accessibilityLabel("More options for \(track.title)")
        .popover(isPresented: $isTrackActionsPresented, attachmentAnchor: .rect(.bounds), arrowEdge: .trailing) {
            TrackActionsPopover(
                track: track,
                playNow: {
                    isTrackActionsPresented = false
                    playNow()
                },
                playNext: {
                    isTrackActionsPresented = false
                    withAnimation(AriaMotion.quickSpring) {
                        player.playNext(track)
                    }
                },
                addToQueue: {
                    isTrackActionsPresented = false
                    addTrackToQueue()
                },
                addToPlaylist: {
                    isTrackActionsPresented = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        isAddToPlaylistPresented = true
                    }
                }
            )
            .presentationCompactAdaptation(.popover)
            .presentationBackground(Color.ariaSurfaceRaised)
        }
    }

    private func handleRowTap() {
        player.play(track, from: source)
        withAnimation(AriaMotion.playerSpring) {
            player.showPlayer()
        }
    }

    private func playNow() {
        player.playNow(track)
        withAnimation(AriaMotion.playerSpring) {
            player.showPlayer()
        }
    }

    private func addTrackToQueue() {
        withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
            player.addToQueue(track)
        }
    }
}

private struct TrackActionsPopover: View {
    let track: Track
    let playNow: () -> Void
    let playNext: () -> Void
    let addToQueue: () -> Void
    let addToPlaylist: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(track.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ariaTextSecondary)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.bottom, 2)

            actionButton(title: "Play Now", systemImage: "play.fill", action: playNow)
            actionButton(
                title: "Play Next",
                systemImage: "text.line.first.and.arrowtriangle.forward",
                action: playNext
            )
            actionButton(
                title: "Add to Queue",
                systemImage: "text.line.last.and.arrowtriangle.forward",
                action: addToQueue
            )
            actionButton(
                title: "Add to Playlist",
                systemImage: "text.badge.plus",
                action: addToPlaylist
            )
        }
        .padding(10)
        .frame(width: 258)
        .background(Color.ariaSurfaceRaised)
    }

    private func actionButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: systemImage)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.ariaAccent)
                    .frame(width: 24)

                Text(title)
                    .font(.headline)
                    .foregroundStyle(.ariaTextPrimary)

                Spacer()
            }
            .padding(.horizontal, 13)
            .frame(height: 54)
        }
        .buttonStyle(TrackActionButtonStyle())
    }
}

private struct TrackActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Color.ariaAccent.opacity(0.2) : .white.opacity(0.055))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(AriaMotion.press, value: configuration.isPressed)
    }
}

private struct QueueDragPreview: View {
    let track: Track

    var body: some View {
        HStack(spacing: 11) {
            ArtworkView(track: track, size: 42, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(track.title)
                    .font(.headline)
                    .foregroundStyle(.ariaTextPrimary)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(.ariaTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .font(.callout.weight(.bold))
                .foregroundStyle(.ariaTextSecondary)
        }
        .padding(10)
        .frame(width: 276)
        .background(Color.ariaSurfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 14, x: 0, y: 8)
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
        .buttonStyle(AriaPressButtonStyle())
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
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
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
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))
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
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Button {
                        withAnimation(AriaMotion.playerSpring) {
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
                                    .contentTransition(.opacity)

                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.ariaTextSecondary)
                                    .lineLimit(1)
                                    .contentTransition(.opacity)
                            }
                        }
                    }
                    .buttonStyle(AriaPressButtonStyle(pressedScale: 0.98))

                    Spacer()

                    AddToPlaylistButton(track: track, size: 36, hasBackground: false)

                    Button {
                        player.playPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.ariaTextPrimary)
                            .frame(width: 40, height: 40)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .buttonStyle(AriaPressButtonStyle())
                    .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

                GeometryReader { geometry in
                    Capsule()
                        .fill(.ariaAccent)
                        .frame(width: max(geometry.size.width * player.progress, 4), height: 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 2)
                .opacity(player.progress > 0 ? 1 : 0)
                .animation(AriaMotion.fast, value: player.progress)
            }
            .background(.ariaSurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
            .animation(AriaMotion.fast, value: player.currentTrack?.id)
        }
    }
}
