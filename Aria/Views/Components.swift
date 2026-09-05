import SwiftUI
import UIKit

enum AriaMotion {
    static let fast = Animation.easeOut(duration: 0.14)
    static let quickSpring = Animation.spring(response: 0.22, dampingFraction: 0.9)
    static let playerSpring = Animation.spring(response: 0.28, dampingFraction: 0.92)
    static let press = Animation.easeOut(duration: 0.09)
    static let queueReorder = Animation.interactiveSpring(response: 0.18, dampingFraction: 0.94, blendDuration: 0.04)
}

struct AriaPressButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? pressedScale : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : AriaMotion.press, value: configuration.isPressed)
    }
}

struct AriaLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(.ariaAccent)
                        .frame(width: 4, height: 22)
                        .scaleEffect(
                            y: reduceMotion ? 0.72 : barScale(at: context.date, index: index),
                            anchor: .center
                        )
                }
            }
        }
        .frame(width: 40, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading library")
    }

    private func barScale(at date: Date, index: Int) -> CGFloat {
        let phase = date.timeIntervalSinceReferenceDate * 5.2 + Double(index) * 1.5
        return 0.42 + CGFloat((sin(phase) + 1) * 0.29)
    }
}

struct ScrollToTopScrollView<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsScrollToTop = false

    private let revealThreshold: CGFloat
    private let bottomClearance: CGFloat
    private let content: Content
    private let topID = "aria-scroll-top"

    init(
        revealThreshold: CGFloat = 120,
        bottomClearance: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.revealThreshold = revealThreshold
        self.bottomClearance = bottomClearance
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView(showsIndicators: false) {
                    Color.clear
                        .frame(height: 1)
                        .id(topID)
                        .onGeometryChange(for: Bool.self) { geometry in
                            geometry.frame(in: .scrollView).minY < -revealThreshold
                        } action: { shouldShow in
                            updateScrollToTopVisibility(shouldShow)
                        }

                    content
                }

                if showsScrollToTop {
                    Button {
                        withAnimation(reduceMotion ? nil : AriaMotion.quickSpring) {
                            proxy.scrollTo(topID, anchor: .top)
                        }
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.ariaAccent)
                            .frame(width: 42, height: 42)
                            .background(.ariaSurfaceRaised, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(.white.opacity(0.12), lineWidth: 1)
                            }
                            .shadow(color: .black.opacity(0.34), radius: 10, y: 5)
                    }
                    .buttonStyle(AriaPressButtonStyle(pressedScale: 0.92))
                    .padding(.trailing, 16)
                    .padding(.bottom, 16 + bottomClearance)
                    .transition(.scale(scale: 0.82).combined(with: .opacity))
                    .accessibilityLabel("Back to top")
                    .zIndex(10)
                }
            }
        }
    }

    private func updateScrollToTopVisibility(_ shouldShow: Bool) {
        guard shouldShow != showsScrollToTop else { return }
        withAnimation(reduceMotion ? nil : AriaMotion.fast) {
            showsScrollToTop = shouldShow
        }
    }
}

struct ArtistNameLink: View {
    @EnvironmentObject private var player: PlayerViewModel
    @State private var isHovering = false
    @State private var prefetchTask: Task<Void, Never>?

    let name: String

    var body: some View {
        Button {
            player.presentArtist(named: name)
        } label: {
            Text(name)
                .foregroundStyle(isHovering ? Color.ariaAccent : Color.ariaTextSecondary)
                .contentShape(Rectangle())
        }
            .buttonStyle(.plain)
            .accessibilityHint("Opens artist")
            .accessibilityAddTraits(.isLink)
            .onHover { hovering in
                isHovering = hovering
                prefetchTask?.cancel()
                guard hovering else { return }
                prefetchTask = Task {
                    try? await Task.sleep(for: .milliseconds(180))
                    guard !Task.isCancelled else { return }
                    await YouTubeMusicSearchClient().prefetchArtistPage(named: name)
                }
            }
            .onDisappear {
                prefetchTask?.cancel()
            }
            .animation(AriaMotion.fast, value: isHovering)
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
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        )
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

        let targetPixelSize = size * UIScreen.main.scale
        guard let image = await AriaArtworkCache.shared.image(
            for: artworkURL,
            targetPixelSize: targetPixelSize
        ) else {
            return
        }

        guard !Task.isCancelled, track.artworkURL == artworkURL else {
            return
        }

        cachedArtwork = image
    }
}

struct TrackRow: View {
    @EnvironmentObject private var player: PlayerViewModel
    @State private var isAddToPlaylistPresented = false
    @State private var queueSwipeOffset: CGFloat = 0
    @State private var isQueueSwipeActive = false
    @State private var suppressesPlayback = false

    let track: Track
    var source: [Track]
    var showAlbum = true
    var playlistForRemoval: AriaPlaylist? = nil
    var usesCustomQueueSwipe = false
    var playbackDisabled = false
    var queueDragItemProvider: (() -> NSItemProvider)? = nil

    var body: some View {
        ZStack(alignment: .leading) {
            Label("Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(.black)
                .padding(.leading, 16)
                .opacity(min(queueSwipeOffset / 42, 1))

            rowContent
                .background(Color.ariaBackground)
                .offset(x: queueSwipeOffset)
                .simultaneousGesture(addToQueueGesture)
        }
        .background(queueSwipeOffset > 0 ? Color.ariaAccent : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .sheet(isPresented: $isAddToPlaylistPresented) {
            AddToPlaylistSheet(track: track)
                .environmentObject(player)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ariaBackground)
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            trackIdentity
                .onTapGesture(perform: handleRowTap)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(named: "Play") {
                    handleRowTap()
                }

            trackActionButton

            if let queueDragItemProvider {
                Image(systemName: "line.3.horizontal")
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(width: 44, height: 48)
                    .contentShape(Rectangle())
                    .onDrag(queueDragItemProvider) {
                        QueueDragPreview(track: track)
                    }
                    .accessibilityLabel("Reorder \(track.title)")
            }
        }
        .padding(.horizontal, 2)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    private var trackIdentity: some View {
        HStack(spacing: 12) {
            ArtworkView(track: track, size: 52, cornerRadius: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .foregroundStyle(player.currentTrack?.id == track.id ? .ariaAccent : .ariaTextPrimary)
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

                HStack(spacing: 0) {
                    Text(track.artist)
                    if showAlbum {
                        Text(" • \(track.album)")
                    }
                }
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
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private var trackActionButton: some View {
        Menu {
            Button {
                playNow()
            } label: {
                Label("Play Now", systemImage: "play.fill")
            }

            Button {
                player.playNext(track)
            } label: {
                Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                addTrackToQueue()
            } label: {
                Label("Add to Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
            }

            Divider()

            Button {
                isAddToPlaylistPresented = true
            } label: {
                Label("Add to Playlist", systemImage: "text.badge.plus")
            }

            Button {
                player.presentArtist(named: track.artist)
            } label: {
                Label("View Artist", systemImage: "person.crop.circle")
            }

            if let playlistForRemoval {
                Divider()

                Button(role: .destructive) {
                    withAnimation(AriaMotion.quickSpring) {
                        player.remove(track, from: playlistForRemoval)
                    }
                } label: {
                    Label("Remove from Playlist", systemImage: "trash")
                }
            } else if usesCustomQueueSwipe {
                Divider()

                Button(role: .destructive) {
                    withAnimation(AriaMotion.quickSpring) {
                        player.removeFromQueue(track)
                    }
                } label: {
                    Label("Remove from Queue", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.ariaTextSecondary)
                .frame(width: 44, height: 48)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("More options for \(track.title)")
    }

    private func handleRowTap() {
        guard !playbackDisabled, !suppressesPlayback, abs(queueSwipeOffset) < 1 else { return }
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
        withAnimation(AriaMotion.quickSpring) {
            player.addToQueue(track)
        }
    }

    private var addToQueueGesture: some Gesture {
        DragGesture(minimumDistance: 26, coordinateSpace: .local)
            .onChanged { value in
                guard !usesCustomQueueSwipe, value.startLocation.x > 28 else { return }
                let horizontalDistance = value.translation.width
                let verticalDistance = abs(value.translation.height)
                guard horizontalDistance > 10, horizontalDistance > verticalDistance * 1.6 else { return }

                isQueueSwipeActive = true
                suppressesPlayback = true
                queueSwipeOffset = min(horizontalDistance * 0.82, 96)
            }
            .onEnded { value in
                guard isQueueSwipeActive else { return }
                let shouldQueue = value.translation.width > 78
                    || value.predictedEndTranslation.width > 138

                if shouldQueue {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.72)
                    addTrackToQueue()
                }

                withAnimation(AriaMotion.quickSpring) {
                    queueSwipeOffset = 0
                }
                isQueueSwipeActive = false

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    suppressesPlayback = false
                }
            }
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

                ArtistNameLink(name: track.artist)
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(.ariaTextPrimary)

            Spacer()

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.medium))
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

                        ForEach(player.editablePlaylists) { playlist in
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

                ArtistNameLink(name: track.artist)
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

struct PlaylistArtwork: View {
    let playlist: AriaPlaylist
    var size: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        ZStack {
            if let coverImageData = playlist.coverImageData,
               let coverImage = UIImage(data: coverImageData) {
                Image(uiImage: coverImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
            } else if let firstTrack = playlist.tracks.first {
                ArtworkView(track: firstTrack, size: size, cornerRadius: cornerRadius)
            } else {
                ZStack {
                    Color.ariaSurfaceRaised

                    Image(systemName: "music.note.list")
                        .font(.system(size: size * 0.32, weight: .semibold))
                        .foregroundStyle(.ariaTextSecondary)
                }
                .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(.white.opacity(0.1), lineWidth: 1)
        )
    }
}

struct MiniPlayerBar: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var playbackClock: PlaybackClock

    var body: some View {
        if let track = player.currentTrack {
            ZStack(alignment: .topTrailing) {
                Button {
                    withAnimation(AriaMotion.playerSpring) {
                        player.showPlayer()
                    }
                } label: {
                    VStack(spacing: 0) {
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

                            Spacer()

                            Color.clear
                                .frame(width: 40, height: 40)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)

                        GeometryReader { geometry in
                            Capsule()
                                .fill(.ariaAccent)
                                .frame(width: max(geometry.size.width * currentProgress, 4), height: 2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 2)
                        .opacity(currentProgress > 0 ? 1 : 0)
                        .animation(AriaMotion.fast, value: currentProgress)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(AriaPressButtonStyle(pressedScale: 0.99))
                .accessibilityLabel("Open now playing")

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
                .padding(.top, 8)
                .padding(.trailing, 10)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    private var currentProgress: Double {
        guard let track = player.currentTrack, track.duration > 0 else { return 0 }
        return min(max(playbackClock.elapsed / track.duration, 0), 1)
    }
}
