import Combine
import AVFoundation
import Foundation
import MediaPlayer
import UIKit

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var catalog: [Track]
    @Published private(set) var albums: [AriaAlbum]
    @Published private(set) var playlists: [AriaPlaylist]
    @Published private(set) var queue: [Track]
    @Published private(set) var isCatalogLoading = false
    @Published private(set) var catalogErrorMessage: String?
    @Published private(set) var listeningHistory: [Track] = []
    @Published private(set) var downloadJob: AriaDownloadJob?
    @Published private(set) var isDownloadStarting = false
    @Published private(set) var downloadErrorMessage: String?
    @Published var currentTrack: Track?
    @Published var elapsed: TimeInterval = 0
    @Published var isPlaying = false
    @Published var isShuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume = 1.0 {
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
    private var remoteCommandTargets: [Any] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var nowPlayingArtworkTrackID: UUID?
    private var nowPlayingArtworkTask: Task<Void, Never>?
    private var downloadPollTask: Task<Void, Never>?

    init(
        catalog: [Track] = [],
        playlists: [AriaPlaylist] = [],
        serverClient: AriaServerClient = AriaServerClient(),
        automaticallyLoadsCatalog: Bool = true
    ) {
        self.catalog = catalog
        self.albums = Self.albums(from: catalog)
        self.playlists = playlists
        self.queue = catalog
        self.currentTrack = catalog.first
        self.serverClient = serverClient

        configureAudioSession()
        configureRemoteCommands()
        updateNowPlayingInfo()

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

        nowPlayingArtworkTask?.cancel()
        downloadPollTask?.cancel()
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

    var upNextPreview: [Track] {
        guard let currentTrack, let index = queue.firstIndex(of: currentTrack) else {
            return Array(queue.prefix(20))
        }

        let nextIndex = queue.index(after: index)
        guard nextIndex < queue.endIndex else { return [] }
        return Array(queue[nextIndex...].prefix(20))
    }

    var remainingUpNextCount: Int {
        guard let currentTrack, let index = queue.firstIndex(of: currentTrack) else {
            return queue.count
        }

        let nextIndex = queue.index(after: index)
        guard nextIndex < queue.endIndex else { return 0 }
        return queue.distance(from: nextIndex, to: queue.endIndex)
    }

    var canSkipToNextTrack: Bool {
        guard let currentTrack else { return false }
        guard let index = queue.firstIndex(of: currentTrack) else {
            return queue.count > 1
        }

        return queue.index(after: index) < queue.endIndex
    }

    var canSkipToPreviousTrack: Bool {
        guard
            let currentTrack,
            let index = queue.firstIndex(of: currentTrack)
        else {
            return false
        }

        return index > queue.startIndex
    }

    private static func albums(from catalog: [Track]) -> [AriaAlbum] {
        let groupedTracks = Dictionary(grouping: catalog) { track in
            albumGroupingKey(for: track)
        }

        return groupedTracks.values.compactMap { tracks in
            let sortedTracks = tracks.sortedForAlbumPlayback()
            guard let firstTrack = sortedTracks.first else { return nil }

            return AriaAlbum(
                title: firstTrack.album,
                artist: albumArtist(for: sortedTracks),
                year: firstTrack.year,
                tracks: sortedTracks
            )
        }
        .sorted { firstAlbum, secondAlbum in
            firstAlbum.title.localizedCaseInsensitiveCompare(secondAlbum.title) == .orderedAscending
        }
    }

    private static func albumGroupingKey(for track: Track) -> String {
        let album = track.album.trimmingCharacters(in: .whitespacesAndNewlines)
        return album.isEmpty ? "unknown album" : album.localizedLowercase
    }

    private static func albumArtist(for tracks: [Track]) -> String {
        var artistsByKey: [String: String] = [:]

        for track in tracks {
            let artist = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !artist.isEmpty else { continue }

            artistsByKey[artist.localizedLowercase] = artist
        }

        let artists = artistsByKey.values.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }

        guard let firstArtist = artists.first else { return "Unknown Artist" }
        return artists.count == 1 ? firstArtist : "Various Artists"
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
        await AriaArtworkCache.shared.removeExpiredArtwork()

        do {
            let tracks = try await serverClient.fetchTracks()
            replaceCatalog(with: tracks)
        } catch {
            catalogErrorMessage = error.localizedDescription
        }

        isCatalogLoading = false
    }

    func startDownload(link: String, album: String, albumArtist: String, year: String) async {
        let request = AriaDownloadRequest(
            link: link.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
            albumArtist: albumArtist.trimmingCharacters(in: .whitespacesAndNewlines),
            year: year.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        isDownloadStarting = true
        downloadErrorMessage = nil

        do {
            let job = try await serverClient.startDownload(request)
            downloadJob = job
            isDownloadStarting = false
            beginDownloadPolling(id: job.id)
        } catch {
            downloadErrorMessage = error.localizedDescription
            isDownloadStarting = false
        }
    }

    func clearFinishedDownload() {
        guard downloadJob?.isFinished == true else { return }
        downloadJob = nil
        downloadErrorMessage = nil
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
        refreshNowPlayingArtwork(for: track)
        updateNowPlayingInfo()
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

        updateNowPlayingInfo()
    }

    func next() {
        guard let currentTrack else { return }

        if repeatMode == .one {
            restart(currentTrack)
            return
        }

        let nextTrack = orderedNext(after: currentTrack)

        if let nextTrack {
            play(nextTrack, from: queue)
        } else if repeatMode == .all, let firstTrack = queue.first {
            play(firstTrack, from: queue)
        } else {
            elapsed = currentTrack.duration
            isPlaying = false
            audioPlayer?.pause()
            updateNowPlayingInfo()
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

    func skipToNextTrack() {
        guard let currentTrack, canSkipToNextTrack else { return }

        let nextTrack = orderedNext(after: currentTrack)
        guard let nextTrack else { return }

        play(nextTrack, from: queue)
    }

    func skipToPreviousTrack() {
        guard
            let currentTrack,
            canSkipToPreviousTrack,
            let currentIndex = queue.firstIndex(of: currentTrack)
        else {
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

        updateNowPlayingInfo()
    }

    func toggleShuffle() {
        if isShuffleEnabled {
            isShuffleEnabled = false
        } else {
            shuffleQueue()
            isShuffleEnabled = true
        }

        updateRemoteCommandAvailability()
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

        updateRemoteCommandAvailability()
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

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
    }

    private func activateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            return
        }
    }

    private func configureRemoteCommands() {
        UIApplication.shared.beginReceivingRemoteControlEvents()

        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true

        remoteCommandTargets = [
            commandCenter.playCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    if self?.isPlaying == false {
                        self?.playPause()
                    }
                }
                return .success
            },
            commandCenter.pauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    if self?.isPlaying == true {
                        self?.playPause()
                    }
                }
                return .success
            },
            commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.playPause()
                }
                return .success
            },
            commandCenter.nextTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.next()
                }
                return .success
            },
            commandCenter.previousTrackCommand.addTarget { [weak self] _ in
                Task { @MainActor in
                    self?.previous()
                }
                return .success
            },
            commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                    return .commandFailed
                }

                Task { @MainActor in
                    guard let currentTrack = self?.currentTrack, currentTrack.duration > 0 else { return }
                    self?.seek(toProgress: event.positionTime / currentTrack.duration)
                }

                return .success
            }
        ]
    }

    private func updateRemoteCommandAvailability() {
        let commandCenter = MPRemoteCommandCenter.shared()
        let hasTrack = currentTrack != nil
        commandCenter.playCommand.isEnabled = hasTrack
        commandCenter.pauseCommand.isEnabled = hasTrack
        commandCenter.togglePlayPauseCommand.isEnabled = hasTrack
        commandCenter.changePlaybackPositionCommand.isEnabled = hasTrack
        commandCenter.nextTrackCommand.isEnabled = hasTrack && (canSkipToNextTrack || repeatMode == .all)
        commandCenter.previousTrackCommand.isEnabled = hasTrack
    }

    private func beginDownloadPolling(id: String) {
        downloadPollTask?.cancel()
        downloadPollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_250_000_000)
                } catch {
                    return
                }

                guard let self else { return }
                await self.refreshDownloadStatus(id: id)

                if self.downloadJob?.isFinished == true {
                    return
                }
            }
        }
    }

    private func refreshDownloadStatus(id: String) async {
        do {
            let job = try await serverClient.fetchDownloadStatus(id: id)
            downloadJob = job

            if job.isFinished {
                downloadPollTask?.cancel()

                if job.isSuccessful {
                    await refreshCatalog()
                }
            }
        } catch {
            downloadErrorMessage = "Download status failed: \(error.localizedDescription)"
        }
    }

    private func refreshNowPlayingArtwork(for track: Track) {
        nowPlayingArtworkTask?.cancel()
        nowPlayingArtwork = nil
        nowPlayingArtworkTrackID = nil

        guard let artworkURL = track.artworkURL else { return }

        nowPlayingArtworkTask = Task { [weak self] in
            guard let image = await AriaArtworkCache.shared.image(for: artworkURL) else { return }
            let lockScreenArtwork = image.ariaCenteredSquareCrop()

            await MainActor.run {
                guard self?.currentTrack?.id == track.id else { return }

                self?.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: lockScreenArtwork.size) { _ in
                    lockScreenArtwork
                }
                self?.nowPlayingArtworkTrackID = track.id
                self?.updateNowPlayingInfo()
            }
        }
    }

    private func updateNowPlayingInfo() {
        guard let currentTrack else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            updateRemoteCommandAvailability()
            return
        }

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: currentTrack.title,
            MPMediaItemPropertyArtist: currentTrack.artist,
            MPMediaItemPropertyAlbumTitle: currentTrack.album,
            MPMediaItemPropertyPlaybackDuration: currentTrack.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1 : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1
        ]

        if nowPlayingArtworkTrackID == currentTrack.id, let nowPlayingArtwork {
            nowPlayingInfo[MPMediaItemPropertyArtwork] = nowPlayingArtwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
        updateRemoteCommandAvailability()
    }

    private func replaceCatalog(with tracks: [Track]) {
        audioPlayer?.pause()
        removeEndObserver()

        catalog = tracks
        albums = Self.albums(from: tracks)
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
        nowPlayingArtwork = nil
        nowPlayingArtworkTrackID = nil
        nowPlayingArtworkTask?.cancel()
        updateNowPlayingInfo()
    }

    private func startPlayback(for track: Track) {
        audioPlayer?.pause()
        removeEndObserver()

        activateAudioSession()

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
            updateNowPlayingInfo()
            return
        }

        if elapsed + 1 >= currentTrack.duration {
            elapsed = currentTrack.duration
            next()
        } else {
            elapsed += 1
            updateNowPlayingInfo()
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
        updateNowPlayingInfo()
    }

    private func orderedNext(after track: Track) -> Track? {
        guard let currentIndex = queue.firstIndex(of: track) else { return queue.first }
        let nextIndex = queue.index(after: currentIndex)
        guard nextIndex < queue.endIndex else { return nil }
        return queue[nextIndex]
    }

    private func shuffleQueue() {
        guard queue.count > 1 else { return }
        guard let currentTrack, let currentIndex = queue.firstIndex(of: currentTrack) else {
            queue.shuffle()
            return
        }

        var otherTracks = queue
        otherTracks.remove(at: currentIndex)
        queue = [currentTrack] + otherTracks.shuffled()
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

        updateNowPlayingInfo()
    }
}

private extension Array where Element == Track {
    func sortedForAlbumPlayback() -> [Track] {
        sorted { firstTrack, secondTrack in
            switch (firstTrack.trackNumber, secondTrack.trackNumber) {
            case let (firstNumber?, secondNumber?) where firstNumber != secondNumber:
                return firstNumber < secondNumber
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return firstTrack.title.localizedCaseInsensitiveCompare(secondTrack.title) == .orderedAscending
            }
        }
    }
}

private extension UIImage {
    func ariaCenteredSquareCrop() -> UIImage {
        guard size.width > 0, size.height > 0 else { return self }
        guard abs(size.width - size.height) > 0.5 else { return self }

        let side = min(size.width, size.height)
        let cropOrigin = CGPoint(
            x: (size.width - side) / 2,
            y: (size.height - side) / 2
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            draw(at: CGPoint(x: -cropOrigin.x, y: -cropOrigin.y))
        }
    }
}
