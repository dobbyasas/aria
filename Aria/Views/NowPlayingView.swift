import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @GestureState private var pullDistance: CGFloat = 0
    @GestureState private var trackSwipeDistance: CGFloat = 0
    @State private var backgroundArtwork: ArtworkPalette?
    @State private var backgroundArtworkTrackID: UUID?
    @State private var draggedQueueTrackID: UUID?
    @State private var lyricsTrack: Track?

    var body: some View {
        Group {
            if let track = player.currentTrack {
                playerView(for: track)
            } else {
                emptyState
            }
        }
        .sheet(item: $lyricsTrack) { track in
            LyricsSheet(track: track)
                .environmentObject(player)
        }
    }

    private func playerView(for track: Track) -> some View {
        GeometryReader { geometry in
            let isTablet = UIDevice.current.userInterfaceIdiom == .pad
            let usesWideLayout = isTablet && geometry.size.width >= 780
            let compactArtworkLimit: CGFloat = isTablet ? 420 : 340
            let compactHorizontalInset: CGFloat = isTablet ? 96 : 56
            let artworkSize = min(geometry.size.width - compactHorizontalInset, compactArtworkLimit)

            ZStack {
                background(for: track)

                if usesWideLayout {
                    widePlayerLayout(for: track, in: geometry.size)
                } else {
                    compactPlayerLayout(for: track, artworkSize: artworkSize, isTablet: isTablet)
                }
            }
            .simultaneousGesture(pullToLibraryGesture)
            .animation(AriaMotion.fast, value: track.id)
            .task(id: track.id) {
                await loadBackgroundArtwork(for: track)
            }
        }
    }

    private func compactPlayerLayout(for track: Track, artworkSize: CGFloat, isTablet: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: isTablet ? 28 : 24) {
                pullHandle
                    .padding(.top, 10)

                header(for: track)

                swipeableTrackIdentity(for: track, artworkSize: artworkSize)

                progressSection(for: track)

                mainControls

                queuePreview
            }
            .padding(.horizontal, isTablet ? 32 : 24)
            .padding(.bottom, 28)
            .frame(maxWidth: isTablet ? 600 : 440)
            .frame(maxWidth: .infinity)
            .offset(y: min(pullDistance * 0.18, 18))
            .animation(.spring(response: 0.24, dampingFraction: 0.84), value: pullDistance)
        }
    }

    private func widePlayerLayout(for track: Track, in size: CGSize) -> some View {
        let artworkSize = min(size.width * 0.4, size.height * 0.48, 430)

        return HStack(alignment: .center, spacing: 42) {
            VStack(spacing: 24) {
                header(for: track)

                swipeableTrackIdentity(for: track, artworkSize: artworkSize)

                progressSection(for: track)

                mainControls
            }
            .frame(maxWidth: 510)

            ScrollView(showsIndicators: false) {
                queuePreview
                    .padding(.vertical, 4)
            }
            .frame(maxWidth: 440, maxHeight: min(size.height - 72, 760))
        }
        .padding(.horizontal, 42)
        .padding(.vertical, 32)
        .frame(maxWidth: 1080, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .offset(y: min(pullDistance * 0.12, 12))
        .animation(.spring(response: 0.24, dampingFraction: 0.84), value: pullDistance)
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

            HStack(spacing: 10) {
                Button {
                    lyricsTrack = track
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.headline)
                        .foregroundStyle(.ariaTextPrimary)
                        .frame(width: 38, height: 38)
                        .background(.black.opacity(0.18))
                        .clipShape(Circle())
                }
                .buttonStyle(AriaPressButtonStyle())
                .accessibilityLabel("Show lyrics")

                AddToPlaylistButton(track: track)
            }
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
                        QueueTrackRow(
                            draggedTrackID: $draggedQueueTrackID,
                            track: track,
                            isDragging: draggedQueueTrackID == track.id
                        )
                            .onDrop(
                                of: [UTType.text.identifier],
                                delegate: QueueReorderDropDelegate(
                                    targetTrackID: track.id,
                                    draggedTrackID: $draggedQueueTrackID,
                                    moveAction: { sourceID, targetID in
                                        withAnimation(AriaMotion.queueReorder) {
                                            player.moveQueuedTrack(sourceID, to: targetID)
                                        }
                                    }
                                )
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

private struct LyricsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel

    let track: Track

    @State private var lyrics: TrackLyrics?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var activeLineID: String? {
        lyrics?.activeLineID(at: player.elapsed)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: track.artwork.topHex).opacity(0.42),
                        Color.ariaBackground
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                content
            }
            .navigationTitle("Lyrics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.caption2)
                            .foregroundStyle(.ariaTextSecondary)
                            .lineLimit(1)
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: track.id) {
                await loadLyrics()
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 14) {
                ProgressView()
                    .tint(.ariaAccent)
                Text("Finding lyrics…")
                    .foregroundStyle(.ariaTextSecondary)
            }
        } else if let errorMessage {
            lyricsMessage(
                title: "Lyrics unavailable",
                message: errorMessage,
                systemImage: "wifi.exclamationmark",
                retry: true
            )
        } else if let lyrics, lyrics.instrumental {
            lyricsMessage(
                title: "Instrumental",
                message: "This track does not have sung lyrics.",
                systemImage: "music.note",
                retry: false
            )
        } else if let lyrics, lyrics.available {
            lyricsContent(lyrics)
        } else {
            lyricsMessage(
                title: "No lyrics found",
                message: "Aria checked the audio file and the online lyrics library.",
                systemImage: "quote.bubble",
                retry: true
            )
        }
    }

    private func lyricsContent(_ lyrics: TrackLyrics) -> some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: lyrics.isSynced ? 18 : 12) {
                    if lyrics.isSynced {
                        ForEach(lyrics.syncedLines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }) { line in
                            let isActive = line.id == activeLineID

                            Button {
                                seek(to: line.startTime)
                            } label: {
                                Text(line.text)
                                    .font(isActive ? .title2.bold() : .title3.weight(.semibold))
                                    .foregroundStyle(isActive ? Color.ariaTextPrimary : Color.ariaTextSecondary.opacity(0.72))
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(line.id)
                            .animation(AriaMotion.fast, value: isActive)
                        }
                    } else {
                        ForEach(Array(lyrics.plainLines.enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : line)
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.ariaTextPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if lyrics.source == "lrclib" {
                        Text("Lyrics provided by LRCLIB")
                            .font(.caption)
                            .foregroundStyle(.ariaTextSecondary.opacity(0.72))
                            .padding(.top, 20)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .onChange(of: activeLineID) { _, newLineID in
                guard let newLineID else { return }
                withAnimation(.easeInOut(duration: 0.34)) {
                    proxy.scrollTo(newLineID, anchor: .center)
                }
            }
        }
    }

    private func lyricsMessage(
        title: String,
        message: String,
        systemImage: String,
        retry: Bool
    ) -> some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.ariaAccent)

            Text(title)
                .font(.title2.bold())
                .foregroundStyle(.ariaTextPrimary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.ariaTextSecondary)
                .multilineTextAlignment(.center)

            if retry {
                Button("Try again") {
                    Task { await loadLyrics() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.ariaAccent)
            }
        }
        .padding(28)
    }

    private func loadLyrics() async {
        isLoading = true
        errorMessage = nil

        do {
            lyrics = try await AriaServerClient().fetchLyrics(for: track)
        } catch {
            lyrics = nil
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func seek(to startTime: TimeInterval) {
        guard track.duration > 0 else { return }
        player.seek(toProgress: min(max(startTime / track.duration, 0), 1))
    }
}

private struct QueueTrackRow: View {
    @EnvironmentObject private var player: PlayerViewModel
    @Binding var draggedTrackID: UUID?
    @State private var swipeOffset: CGFloat = 0
    @State private var swipeStartOffset: CGFloat?
    @State private var isHorizontalSwipe = false

    let track: Track
    let isDragging: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            removeButton
                .mask(alignment: .trailing) {
                    Rectangle()
                        .frame(width: deleteRevealWidth)
                }
                .allowsHitTesting(deleteRevealWidth >= 70)

            TrackRow(
                track: track,
                source: player.queue,
                showAlbum: false,
                usesCustomQueueSwipe: true,
                queueDragItemProvider: dragItemProvider
            )
            .padding(.horizontal, 4)
            .background(Color.ariaBackground.opacity(0.94))
            .offset(x: swipeOffset)
            .simultaneousGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .scaleEffect(isDragging ? 0.985 : 1)
        .opacity(isDragging ? 0.7 : 1)
        .zIndex(isDragging ? 1 : 0)
        .animation(AriaMotion.queueReorder, value: isDragging)
        .accessibilityAction(named: "Remove from queue") {
            removeFromQueue()
        }
    }

    private var deleteRevealWidth: CGFloat {
        min(max(-swipeOffset, 0), 82)
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            removeFromQueue()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "trash.fill")
                    .font(.callout.weight(.semibold))

                Text("Remove")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(width: 82)
            .frame(height: 64)
            .background(Color.red)
        }
        .buttonStyle(.plain)
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .onChanged { value in
                if swipeStartOffset == nil {
                    let horizontalDistance = abs(value.translation.width)
                    let verticalDistance = abs(value.translation.height)
                    guard horizontalDistance > verticalDistance * 1.25 else { return }

                    swipeStartOffset = swipeOffset
                    isHorizontalSwipe = true
                }

                guard isHorizontalSwipe else { return }
                let proposedOffset = (swipeStartOffset ?? 0) + value.translation.width
                swipeOffset = min(max(proposedOffset, -132), 0)
            }
            .onEnded { value in
                defer {
                    swipeStartOffset = nil
                    isHorizontalSwipe = false
                }

                guard isHorizontalSwipe else { return }
                let predictedOffset = (swipeStartOffset ?? 0) + value.predictedEndTranslation.width

                if swipeOffset < -104 || predictedOffset < -150 {
                    removeFromQueue()
                } else {
                    withAnimation(AriaMotion.quickSpring) {
                        swipeOffset = swipeOffset < -42 ? -82 : 0
                    }
                }
            }
    }

    private func dragItemProvider() -> NSItemProvider {
        swipeOffset = 0
        draggedTrackID = track.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.75)
        return NSItemProvider(object: track.id.uuidString as NSString)
    }

    private func removeFromQueue() {
        withAnimation(AriaMotion.quickSpring) {
            swipeOffset = 0
            player.removeFromQueue(track)
        }
    }
}

private struct QueueReorderDropDelegate: DropDelegate {
    let targetTrackID: UUID
    @Binding var draggedTrackID: UUID?
    let moveAction: (UUID, UUID) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedTrackID, draggedTrackID != targetTrackID else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        moveAction(draggedTrackID, targetTrackID)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        draggedTrackID = nil
        return true
    }
}
