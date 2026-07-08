import Combine
import AVFoundation
import Foundation

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var catalog: [Track]
    @Published private(set) var playlists: [AriaPlaylist]
    @Published private(set) var queue: [Track]
    @Published private(set) var isCatalogLoading = false
    @Published private(set) var catalogErrorMessage: String?
    @Published private(set) var listeningHistory: [Track] = []
    @Published var currentTrack: Track?
    @Published var elapsed: TimeInterval = 0
    @Published var isPlaying = false
    @Published var isShuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume = 0.74 {
        didSet {
            audioPlayer?.volume = Float(volume)
        }
    }
    @Published var isPlayerPresented = true

    private let serverClient: AriaServerClient
    private var audioPlayer: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var catalogTask: Task<Void, Never>?
    private var timer: AnyCancellable?

    init(
        catalog: [Track] = [],
        playlists: [AriaPlaylist] = [],
        serverClient: AriaServerClient = AriaServerClient(),
        automaticallyLoadsCatalog: Bool = true
    ) {
        self.catalog = catalog
        self.playlists = playlists
        self.queue = catalog
        self.currentTrack = catalog.first
        self.serverClient = serverClient

        if automaticallyLoadsCatalog {
            catalogTask = Task { [weak self] in
                await self?.refreshCatalog()
            }
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    var progress: Double {
        guard let currentTrack, currentTrack.duration > 0 else { return 0 }
        return min(max(elapsed / currentTrack.duration, 0), 1)
    }

    var upNext: [Track] {
        guard let currentTrack, let index = queue.firstIndex(of: currentTrack) else {
            return queue
        }

        let nextIndex = queue.index(after: index)
        guard nextIndex < queue.endIndex else { return [] }
        return Array(queue[nextIndex...])
    }

    var albums: [AriaAlbum] {
        let groupedTracks = Dictionary(grouping: catalog) { track in
            "\(track.artist)-\(track.album)"
        }

        return groupedTracks.values.compactMap { tracks in
            guard let firstTrack = tracks.first else { return nil }

            return AriaAlbum(
                title: firstTrack.album,
                artist: firstTrack.artist,
                year: firstTrack.year,
                tracks: tracks.sorted { $0.title < $1.title }
            )
        }
        .sorted { firstAlbum, secondAlbum in
            firstAlbum.title.localizedCaseInsensitiveCompare(secondAlbum.title) == .orderedAscending
        }
    }

    func showPlayer() {
        isPlayerPresented = true
    }

    func hidePlayer() {
        isPlayerPresented = false
    }

    func refreshCatalog() async {
        isCatalogLoading = true
        catalogErrorMessage = nil

        do {
            let tracks = try await serverClient.fetchTracks()
            replaceCatalog(with: tracks)
        } catch {
            catalogErrorMessage = error.localizedDescription
        }

        isCatalogLoading = false
    }

    func play(_ track: Track, from collection: [Track]? = nil) {
        if let collection, !collection.isEmpty {
            queue = collection
        } else if !queue.contains(track) {
            queue.insert(track, at: 0)
        }

        currentTrack = track
        elapsed = 0
        isPlaying = true
        addToHistory(track)
        startPlayback(for: track)
        startTimer()
    }

    func playPause() {
        guard currentTrack != nil else {
            if let firstTrack = catalog.first {
                play(firstTrack, from: catalog)
            }
            return
        }

        isPlaying.toggle()
        if isPlaying {
            audioPlayer?.play()
            startTimer()
        } else {
            audioPlayer?.pause()
        }
    }

    func next() {
        guard let currentTrack else { return }

        if repeatMode == .one {
            restart(currentTrack)
            return
        }

        let nextTrack = isShuffleEnabled ? shuffledNext(after: currentTrack) : orderedNext(after: currentTrack)

        if let nextTrack {
            play(nextTrack, from: queue)
        } else if repeatMode == .all, let firstTrack = queue.first {
            play(firstTrack, from: queue)
        } else {
            elapsed = currentTrack.duration
            isPlaying = false
            audioPlayer?.pause()
        }
    }

    func previous() {
        guard let currentTrack else { return }

        if elapsed > 3 {
            seek(toProgress: 0)
            return
        }

        guard let currentIndex = queue.firstIndex(of: currentTrack), currentIndex > queue.startIndex else {
            elapsed = 0
            return
        }

        play(queue[queue.index(before: currentIndex)], from: queue)
    }

    func seek(toProgress progress: Double) {
        guard let currentTrack else { return }
        let targetTime = min(max(progress, 0), 1) * currentTrack.duration
        elapsed = targetTime

        if audioPlayer != nil {
            audioPlayer?.seek(to: CMTime(seconds: targetTime, preferredTimescale: 600))
        }
    }

    func toggleShuffle() {
        isShuffleEnabled.toggle()
    }

    func cycleRepeatMode() {
        switch repeatMode {
        case .off:
            repeatMode = .all
        case .all:
            repeatMode = .one
        case .one:
            repeatMode = .off
        }
    }

    func playPlaylist(_ playlist: AriaPlaylist) {
        guard let firstTrack = playlist.tracks.first else { return }
        play(firstTrack, from: playlist.tracks)
        showPlayer()
    }

    func addToFront(_ track: Track) {
        guard currentTrack?.id != track.id else { return }

        queue.removeAll { $0.id == track.id }

        guard let currentTrack, let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id }) else {
            queue.insert(track, at: 0)
            return
        }

        queue.insert(track, at: queue.index(after: currentIndex))
    }

    func removeFromQueue(_ track: Track) {
        guard currentTrack?.id != track.id else { return }

        queue.removeAll { $0.id == track.id }
    }

    @discardableResult
    func createPlaylist(containing track: Track? = nil) -> AriaPlaylist {
        let playlistNumber = playlists.filter { $0.title.hasPrefix("New Playlist") }.count + 1
        var playlist = AriaPlaylist(title: "New Playlist \(playlistNumber)", subtitle: "0 songs", tracks: [])

        if let track {
            playlist.tracks.append(track)
            playlist.subtitle = subtitle(forTrackCount: playlist.tracks.count)
        }

        playlists.insert(playlist, at: 0)
        return playlist
    }

    func add(_ track: Track, to playlist: AriaPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        guard !playlists[index].tracks.contains(where: { $0.id == track.id }) else { return }

        playlists[index].tracks.append(track)
        playlists[index].subtitle = subtitle(forTrackCount: playlists[index].tracks.count)
    }

    func remove(_ track: Track, from playlist: AriaPlaylist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        playlists[index].tracks.removeAll { $0.id == track.id }
        playlists[index].subtitle = subtitle(forTrackCount: playlists[index].tracks.count)
    }

    func rename(_ playlist: AriaPlaylist, to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        playlists[index].title = trimmedTitle
    }

    func playlist(_ playlist: AriaPlaylist, contains track: Track) -> Bool {
        playlist.tracks.contains { $0.id == track.id }
    }

    private func subtitle(forTrackCount count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    private func replaceCatalog(with tracks: [Track]) {
        audioPlayer?.pause()
        removeEndObserver()

        catalog = tracks
        queue = tracks
        playlists = [
            AriaPlaylist(
                title: "Fedora songs",
                subtitle: subtitle(forTrackCount: tracks.count),
                tracks: tracks
            )
        ]
        listeningHistory = []
        currentTrack = tracks.first
        elapsed = 0
        isPlaying = false
    }

    private func startPlayback(for track: Track) {
        audioPlayer?.pause()
        removeEndObserver()

        guard let streamURL = track.streamURL else {
            audioPlayer = nil
            return
        }

        let item = AVPlayerItem(url: streamURL)
        let player = AVPlayer(playerItem: item)
        player.volume = Float(volume)
        audioPlayer = player

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.next()
            }
        }

        player.play()
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    private func startTimer() {
        guard timer == nil else { return }

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    private func tick() {
        guard isPlaying, let currentTrack else { return }

        if let audioPlayer, currentTrack.streamURL != nil {
            let currentSeconds = audioPlayer.currentTime().seconds
            if currentSeconds.isFinite {
                elapsed = max(currentSeconds, 0)
            }

            updateCurrentTrackDurationIfNeeded()
            return
        }

        if elapsed + 1 >= currentTrack.duration {
            elapsed = currentTrack.duration
            next()
        } else {
            elapsed += 1
        }
    }

    private func restart(_ track: Track) {
        currentTrack = track
        elapsed = 0
        isPlaying = true

        if let audioPlayer, track.streamURL != nil {
            audioPlayer.seek(to: .zero)
            audioPlayer.play()
        }

        startTimer()
    }

    private func orderedNext(after track: Track) -> Track? {
        guard let currentIndex = queue.firstIndex(of: track) else { return queue.first }
        let nextIndex = queue.index(after: currentIndex)
        guard nextIndex < queue.endIndex else { return nil }
        return queue[nextIndex]
    }

    private func shuffledNext(after track: Track) -> Track? {
        let candidates = queue.filter { $0 != track }
        return candidates.randomElement()
    }

    private func addToHistory(_ track: Track) {
        listeningHistory.removeAll { $0.id == track.id }
        listeningHistory.insert(track, at: 0)
        listeningHistory = Array(listeningHistory.prefix(12))
    }

    private func updateCurrentTrackDurationIfNeeded() {
        guard let currentTrack, currentTrack.duration <= 0 else { return }
        guard let duration = audioPlayer?.currentItem?.duration.seconds else { return }
        guard duration.isFinite, duration > 0 else { return }

        updateDuration(duration, for: currentTrack.id)
    }

    private func updateDuration(_ duration: TimeInterval, for trackID: UUID) {
        if currentTrack?.id == trackID {
            currentTrack?.duration = duration
        }

        if let index = catalog.firstIndex(where: { $0.id == trackID }) {
            catalog[index].duration = duration
        }

        if let index = queue.firstIndex(where: { $0.id == trackID }) {
            queue[index].duration = duration
        }

        for playlistIndex in playlists.indices {
            if let trackIndex = playlists[playlistIndex].tracks.firstIndex(where: { $0.id == trackID }) {
                playlists[playlistIndex].tracks[trackIndex].duration = duration
            }
        }
    }
}
