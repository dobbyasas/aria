import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct NowPlayingView: View {
    @EnvironmentObject private var player: PlayerViewModel
    @GestureState private var pullDistance: CGFloat = 0
    @GestureState private var trackSwipeDistance: CGFloat = 0
    @State private var backgroundArtwork: ArtworkPalette?
    @State private var backgroundArtworkTrackID: UUID?
    @State private var lyricsTrack: Track?
    @State private var isQueuePresented = false

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
        .sheet(isPresented: $isQueuePresented) {
            MobileQueueSheet()
                .environmentObject(player)
        }
    }

    private func playerView(for track: Track) -> some View {
        GeometryReader { geometry in
            let isTablet = UIDevice.current.userInterfaceIdiom == .pad
            let usesWideLayout = isTablet && geometry.size.width >= 780
            let compactArtworkLimit: CGFloat = isTablet ? 520 : geometry.size.width
            let artworkSize = min(geometry.size.width, compactArtworkLimit)

            ZStack {
                background(for: track)

                if usesWideLayout {
                    widePlayerLayout(for: track, in: geometry.size)
                } else {
                    compactPlayerLayout(for: track, artworkSize: artworkSize, isTablet: isTablet)
                }
            }
            .simultaneousGesture(pullToLibraryGesture)
            .task(id: track.id) {
                await loadBackgroundArtwork(for: track)
            }
        }
    }

    private func compactPlayerLayout(for track: Track, artworkSize: CGFloat, isTablet: Bool) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    swipeableTrackIdentity(for: track, artworkSize: artworkSize)
                    header(for: track)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }

                VStack(spacing: isTablet ? 24 : 18) {
                    songIdentity(for: track)
                    progressSection(for: track)
                    mainControls
                    upNextStrip
                }
                .padding(.horizontal, isTablet ? 36 : 20)
                .padding(.top, 22)
                .padding(.bottom, 28)
                .background(Color.ariaBackground)
                .overlay(alignment: .top) {
                    Rectangle().fill(.ariaAccent).frame(height: 3)
                }
            }
            .frame(maxWidth: isTablet ? 620 : 440)
            .frame(maxWidth: .infinity)
            .offset(y: min(pullDistance * 0.18, 18))
        }
    }

    private func widePlayerLayout(for track: Track, in size: CGSize) -> some View {
        let artworkSize = min(size.width * 0.50, size.height * 0.72, 560)

        return HStack(spacing: 0) {
            ZStack(alignment: .top) {
                swipeableTrackIdentity(for: track, artworkSize: artworkSize)
                header(for: track)
                    .padding(18)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    songIdentity(for: track)
                    Text(track.album)
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                    progressSection(for: track)
                    mainControls
                    upNextStrip
                }
                .padding(32)
            }
            .frame(width: min(460, size.width * 0.44))
            .background(Color.ariaBackground)
            .overlay(alignment: .leading) {
                Rectangle().fill(.ariaAccent).frame(width: 3)
            }
        }
        .frame(maxWidth: 1120, maxHeight: .infinity)
        .frame(maxWidth: .infinity)
        .offset(y: min(pullDistance * 0.12, 12))
    }

    private func background(for track: Track) -> some View {
        let artwork = backgroundArtworkTrackID == track.id ? backgroundArtwork ?? track.artwork : track.artwork

        return ZStack {
            Color.ariaBackground
            Color(hex: artwork.topHex).opacity(0.12)
        }
        .ignoresSafeArea()
    }

    private func header(for track: Track) -> some View {
        HStack(alignment: .center) {
            Button {
                player.hidePlayer()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.42), in: Circle())
            }
            .buttonStyle(AriaPressButtonStyle())
            .accessibilityLabel("Close player")

            Text("Now Playing")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(.black.opacity(0.42), in: Capsule())

            Spacer()

            HStack(spacing: 10) {
                Button {
                    isQueuePresented = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(AriaPressButtonStyle())
                .accessibilityLabel("Show queue")

                Button {
                    lyricsTrack = track
                } label: {
                    Image(systemName: "quote.bubble")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.black.opacity(0.42), in: Circle())
                }
                .buttonStyle(AriaPressButtonStyle())
                .accessibilityLabel("Show lyrics")

                AddToPlaylistButton(track: track, size: 40, hasBackground: true)
            }
        }
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
        ArtworkView(track: track, size: artworkSize, cornerRadius: 0)
        .id(track.id)
        .transition(.opacity)
        .contentShape(Rectangle())
        .offset(x: clampedTrackSwipeOffset)
        .simultaneousGesture(trackNavigationGesture)
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
        VStack(alignment: .leading, spacing: 7) {
            Text(track.title)
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(.ariaTextPrimary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .contentTransition(.opacity)

            ArtistNameLink(name: track.artist)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.ariaTextSecondary)
                .lineLimit(1)
                .contentTransition(.opacity)

            Text(queuePosition(for: track))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.ariaTextSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func queuePosition(for track: Track) -> String {
        let position = (player.queue.firstIndex(where: { $0.id == track.id }) ?? 0) + 1
        let total = max(player.queue.count, 1)
        return String(format: "%02d / %02d", position, total)
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
        }
    }

    private var mainControls: some View {
        HStack(spacing: 0) {
            controlIcon("shuffle", active: player.isShuffleEnabled, label: "Shuffle") {
                player.toggleShuffle()
            }

            controlIcon("backward.end.fill", label: "Previous") {
                player.previous()
            }

            Button {
                player.playPause()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(.ariaBackground)
                    .frame(width: 68, height: 68)
                    .background(.ariaAccent, in: Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(AriaPressButtonStyle(pressedScale: 0.94))
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            controlIcon("forward.end.fill", label: "Next") {
                player.next()
            }

            controlIcon(
                player.repeatMode.systemImage,
                active: player.repeatMode != .off,
                label: player.repeatMode.title
            ) {
                player.cycleRepeatMode()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func controlIcon(
        _ systemImage: String,
        active: Bool = false,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(active ? .ariaAccent : .ariaTextSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
        }
        .buttonStyle(AriaPressButtonStyle())
        .accessibilityLabel(label)
    }

    private var upNextStrip: some View {
        Button {
            isQueuePresented = true
        } label: {
            HStack(spacing: 12) {
                Text("Next")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaTextSecondary)
                    .frame(width: 34, alignment: .leading)

                if let nextTrack = player.upNextPreview.first {
                    ArtworkView(track: nextTrack, size: 42, cornerRadius: 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(nextTrack.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ariaTextPrimary)
                            .lineLimit(1)
                        Text(nextTrack.artist)
                            .font(.caption)
                            .foregroundStyle(.ariaTextSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("End of queue")
                        .font(.subheadline)
                        .foregroundStyle(.ariaTextSecondary)
                }

                Spacer()

                if player.remainingUpNextCount > 0 {
                    Text("\(player.remainingUpNextCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.ariaTextSecondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.ariaTextSecondary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(.ariaDivider).frame(height: 1)
        }
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

private struct MobileQueueSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var player: PlayerViewModel
    @State private var draggedTrackID: UUID?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 4) {
                    ForEach(player.queue) { track in
                        QueueTrackRow(
                            draggedTrackID: $draggedTrackID,
                            track: track,
                            isDragging: draggedTrackID == track.id
                        )
                        .onDrop(
                            of: [UTType.text.identifier],
                            delegate: QueueReorderDropDelegate(
                                targetTrackID: track.id,
                                draggedTrackID: $draggedTrackID,
                                moveAction: { sourceID, targetID in
                                    withAnimation(AriaMotion.queueReorder) {
                                        player.moveQueuedTrack(sourceID, to: targetID)
                                    }
                                }
                            )
                        )
                    }
                }
                .padding(16)
            }
            .background(Color.ariaBackground)
            .navigationTitle("Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
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
