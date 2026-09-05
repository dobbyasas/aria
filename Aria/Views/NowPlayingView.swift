import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var playbackClock: PlaybackClock
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var trackSwipeDistance: CGFloat = 0
    @State private var pullDistance: CGFloat = 0
    @State private var isPlayerScrollAtTop = true
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
        .offset(y: max(pullDistance, 0))
        .simultaneousGesture(pullToLibraryGesture)
        .onDisappear {
            pullDistance = 0
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
            .task(id: track.id) {
                await loadBackgroundArtwork(for: track)
            }
        }
    }

    private func compactPlayerLayout(for track: Track, artworkSize: CGFloat, isTablet: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            Color.clear
                .frame(height: 1)
                .onGeometryChange(for: Bool.self) { geometry in
                    geometry.frame(in: .scrollView).minY >= -1
                } action: { isAtTop in
                    isPlayerScrollAtTop = isAtTop
                }

            VStack(spacing: isTablet ? 28 : 24) {
                header(for: track)

                trackIdentity(for: track, artworkSize: artworkSize)

                progressSection(for: track)

                mainControls

                queuePreview
            }
            .padding(.horizontal, isTablet ? 32 : 24)
            .padding(.bottom, 28)
            .frame(maxWidth: isTablet ? 600 : 440)
            .frame(maxWidth: .infinity)
        }
    }

    private func widePlayerLayout(for track: Track, in size: CGSize) -> some View {
        let artworkSize = min(size.width * 0.4, size.height * 0.48, 430)

        return HStack(alignment: .center, spacing: 42) {
            VStack(spacing: 24) {
                header(for: track)

                trackIdentity(for: track, artworkSize: artworkSize)

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
    }

    private func background(for track: Track) -> some View {
        let artwork = backgroundArtworkTrackID == track.id ? backgroundArtwork ?? track.artwork : track.artwork

        return ZStack {
            Color.ariaBackground

            LinearGradient(
                colors: [
                    Color(hex: artwork.topHex).opacity(0.48),
                    Color(hex: artwork.bottomHex).opacity(0.34),
                    .ariaBackground
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Color.ariaBackground.opacity(0.34)
        }
        .ignoresSafeArea()
    }

    private func header(for track: Track) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .center) {
                Button(action: dismissPlayer) {
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.ariaTextPrimary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(AriaPressButtonStyle())
                .accessibilityLabel("Close player")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Now Playing")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.ariaTextPrimary)

                    Text(track.album)
                        .font(.caption)
                        .foregroundStyle(.ariaTextSecondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        lyricsTrack = track
                    } label: {
                        Image(systemName: "quote.bubble")
                            .font(.headline)
                            .foregroundStyle(.ariaTextPrimary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(AriaPressButtonStyle())
                    .accessibilityLabel("Show lyrics")

                    AddToPlaylistButton(track: track, size: 44, hasBackground: false)
                }
            }
        }
    }

    private var pullToLibraryGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .global)
            .onChanged { value in
                guard player.currentTrack != nil, isPlayerScrollAtTop, isLibraryPull(value) else { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    pullDistance = rubberBandDistance(value.translation.height)
                }
            }
            .onEnded { value in
                let shouldDismiss = isPlayerScrollAtTop && isLibraryPull(value)
                    && (value.translation.height > 84 || value.predictedEndTranslation.height > 150)

                if shouldDismiss {
                    dismissPlayer()
                } else {
                    withAnimation(reduceMotion ? nil : AriaMotion.playerSpring) {
                        pullDistance = 0
                    }
                }
            }
    }

    private func isLibraryPull(_ value: DragGesture.Value) -> Bool {
        let verticalDistance = value.translation.height
        let horizontalDistance = abs(value.translation.width)
        return verticalDistance > 20 && verticalDistance > horizontalDistance * 1.35
    }

    private func rubberBandDistance(_ distance: CGFloat) -> CGFloat {
        guard distance > 220 else { return max(distance, 0) }
        return 220 + (distance - 220) * 0.22
    }

    private func trackIdentity(for track: Track, artworkSize: CGFloat) -> some View {
        VStack(spacing: 24) {
            ArtworkView(track: track, size: artworkSize, cornerRadius: 4)
                .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
                .id(track.id)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))

            songIdentity(for: track)
        }
        .contentShape(Rectangle())
        .offset(x: trackSwipeOffset)
        .simultaneousGesture(trackNavigationGesture)
        .accessibilityHint("Swipe left for the next song or right for the previous song")
        .accessibilityAction(named: "Next song") {
            playNextTrack()
        }
        .accessibilityAction(named: "Previous song") {
            playPreviousTrack()
        }
    }

    private var trackSwipeOffset: CGFloat {
        let distance = trackSwipeDistance * 0.24
        return min(max(distance, -58), 58)
    }

    private var trackNavigationGesture: some Gesture {
        DragGesture(minimumDistance: 26, coordinateSpace: .local)
            .updating($trackSwipeDistance) { value, state, _ in
                guard isTrackNavigationSwipe(value) else { return }
                state = value.translation.width
            }
            .onEnded { value in
                guard isTrackNavigationSwipe(value) else { return }

                let travelledFarEnough = abs(value.translation.width) > 72
                    || abs(value.predictedEndTranslation.width) > 136
                guard travelledFarEnough else { return }

                if value.translation.width < 0 {
                    playNextTrack()
                } else {
                    playPreviousTrack()
                }
            }
    }

    private func isTrackNavigationSwipe(_ value: DragGesture.Value) -> Bool {
        let horizontalDistance = abs(value.translation.width)
        let verticalDistance = abs(value.translation.height)
        return horizontalDistance > 12 && horizontalDistance > verticalDistance * 1.4
    }

    private func playNextTrack() {
        guard player.canSkipToNextTrack else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : AriaMotion.quickSpring) {
            player.skipToNextTrack()
        }
    }

    private func playPreviousTrack() {
        guard player.canSkipToPreviousTrack else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? nil : AriaMotion.quickSpring) {
            player.skipToPreviousTrack()
        }
    }

    private func dismissPlayer() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(reduceMotion ? nil : AriaMotion.playerSpring) {
            player.hidePlayer()
        }
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
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(.ariaTextPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .contentTransition(.opacity)

            ArtistNameLink(name: track.artist)
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
                    get: { currentProgress(for: track) },
                    set: { player.seek(toProgress: $0) }
                ),
                in: 0...1
            )
            .tint(.ariaAccent)

            HStack {
                Text(playbackClock.elapsed.ariaClockTime)
                    .contentTransition(.numericText())
                Spacer()
                Text(track.duration.ariaClockTime)
                    .contentTransition(.numericText())
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.ariaTextSecondary)
        }
    }

    private func currentProgress(for track: Track) -> Double {
        guard track.duration > 0 else { return 0 }
        return min(max(playbackClock.elapsed / track.duration, 0), 1)
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
                    .frame(width: 68, height: 68)
                    .background(.ariaTextPrimary)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.2), radius: 12, x: 0, y: 7)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.92))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

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

            if player.isCatalogLoading {
                AriaLoadingIndicator()
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "music.note")
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.ariaAccent)

                    Text("Choose a song to begin")
                        .font(.title2.bold())
                        .foregroundStyle(.ariaTextPrimary)
                    Button("Open library") {
                        player.hidePlayer()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.ariaAccent)
                }
            }
        }
    }
}

private struct LyricsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @EnvironmentObject private var playbackClock: PlaybackClock

    let track: Track

    @State private var lyrics: TrackLyrics?
    @State private var errorMessage: String?
    @State private var isLoading = true

    private var activeLineID: String? {
        lyrics?.activeLineID(at: playbackClock.elapsed)
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
                        ArtistNameLink(name: track.artist)
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
    @State private var isHorizontalSwipe = false
    @State private var suppressesPlayback = false

    let track: Track
    let isDragging: Bool

    var body: some View {
        ZStack(alignment: .trailing) {
            Label("Remove", systemImage: "trash.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .padding(.trailing, 14)
                .opacity(min(-swipeOffset / 42, 1))

            TrackRow(
                track: track,
                source: player.queue,
                showAlbum: false,
                usesCustomQueueSwipe: true,
                playbackDisabled: suppressesPlayback,
                queueDragItemProvider: dragItemProvider
            )
            .background(Color.ariaBackground)
            .offset(x: swipeOffset)
            .simultaneousGesture(swipeGesture)
        }
        .background(swipeOffset < 0 ? Color.red : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .scaleEffect(isDragging ? 0.985 : 1)
        .opacity(isDragging ? 0.7 : 1)
        .zIndex(isDragging ? 1 : 0)
        .animation(AriaMotion.queueReorder, value: isDragging)
        .accessibilityAction(named: "Remove from queue") {
            removeFromQueue()
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 26, coordinateSpace: .local)
            .onChanged { value in
                let horizontalDistance = -value.translation.width
                let verticalDistance = abs(value.translation.height)
                guard horizontalDistance > 10, horizontalDistance > verticalDistance * 1.6 else { return }

                isHorizontalSwipe = true
                suppressesPlayback = true
                swipeOffset = max(value.translation.width * 0.82, -96)
            }
            .onEnded { value in
                guard isHorizontalSwipe else { return }
                let shouldRemove = value.translation.width < -78
                    || value.predictedEndTranslation.width < -138

                if shouldRemove {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred(intensity: 0.78)
                    removeFromQueue()
                } else {
                    withAnimation(AriaMotion.quickSpring) {
                        swipeOffset = 0
                    }
                }
                isHorizontalSwipe = false

                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(180))
                    suppressesPlayback = false
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
