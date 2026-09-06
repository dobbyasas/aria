import Combine
import AVFoundation
import Foundation
import MediaPlayer
import UIKit

struct QueueNotice: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbolName: String
}

@MainActor
final class PlaybackClock: ObservableObject {
    @Published var elapsed: TimeInterval = 0
}

@MainActor
final class PlayerViewModel: ObservableObject {
    @Published private(set) var catalog: [Track]
    @Published private(set) var albums: [AriaAlbum]
    @Published private(set) var playlists: [AriaPlaylist]
    @Published private(set) var queue: [Track]
    @Published private(set) var isCatalogLoading = false
    @Published private(set) var catalogErrorMessage: String?
    @Published private(set) var playbackSessionRole: PlaybackSessionRole?
    @Published private(set) var playbackHostName: String?
    @Published private(set) var playbackDevices: [PlaybackDevice] = []
    @Published private(set) var playbackSessionError: String?
    @Published private(set) var isSharedPlaybackSession = true
    @Published private(set) var listeningHistory: [Track] = []
    @Published private(set) var downloadJob: AriaDownloadJob?
    @Published private(set) var isDownloadStarting = false
    @Published private(set) var downloadErrorMessage: String?
    @Published private(set) var youtubeMusicResults: [YouTubeMusicAlbumResult] = []
    @Published private(set) var youtubeMusicSongResults: [YouTubeMusicSongResult] = []
    @Published private(set) var youtubeMusicPlaylistResults: [YouTubeMusicPlaylistResult] = []
    @Published private(set) var isSearchingYouTubeMusic = false
    @Published private(set) var youtubeMusicSearchError: String?
    @Published var presentedArtist: ArtistSelection?
    @Published private(set) var queueNotice: QueueNotice?
    @Published var currentTrack: Track?
    @Published var isPlaying = false
    @Published var isShuffleEnabled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var volume = 1.0 {
        didSet {
            let boundedVolume = min(max(volume, 0), 1)
            if isRemoteController, !isApplyingPlaybackSync {
                scheduleRemoteVolumeCommand(boundedVolume)
            } else {
                audioPlayer?.volume = Float(boundedVolume)
            }
        }
    }
    @Published var isPlayerPresented = true

    let playbackClock = PlaybackClock()

    var elapsed: TimeInterval {
        get { playbackClock.elapsed }
        set { playbackClock.elapsed = newValue }
    }

    private let serverClient: AriaServerClient
    private let playlistStore: PlaylistStore
    private let youtubeMusicSearchClient = YouTubeMusicSearchClient()
    private var audioPlayer: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var catalogTask: Task<Void, Never>?
    private var timer: AnyCancellable?
    private var remoteCommandTargets: [Any] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var nowPlayingArtworkTrackID: UUID?
    private var nowPlayingArtworkTask: Task<Void, Never>?
    private var downloadPollTask: Task<Void, Never>?
    private var queueNoticeTask: Task<Void, Never>?
    private var playbackSyncTask: Task<Void, Never>?
    private var volumeCommandTask: Task<Void, Never>?
    private var manuallyQueuedTrackIDs: [UUID] = []
    private let playbackDeviceID = PlayerViewModel.stablePlaybackDeviceID()
    private var playbackSessionID = PlayerViewModel.savedPlaybackSessionID()
    private var lastPlaybackCommandID = 0
    private var lastSentPlaybackQueueIDs: [String] = []
    private var isApplyingPlaybackSync = false
    private var isSyncingPlayback = false
    private var shouldStartAudioWhenBecomingHost = false

    private static let libraryPlaylistID = UUID(
        uuidString: "00000000-0000-0000-0000-000000000001"
    )!
    private static let playbackDeviceIDDefaultsKey = "aria.playback.deviceID"
    private static let playbackSessionIDDefaultsKey = "aria.playback.sessionID"
    private static let sharedPlaybackSessionID = "shared"

    init(
        catalog: [Track] = [],
        playlists: [AriaPlaylist] = [],
        serverClient: AriaServerClient = AriaServerClient(),
        playlistStore: PlaylistStore = PlaylistStore(),
        automaticallyLoadsCatalog: Bool = true,
        automaticallySyncsPlayback: Bool = true
    ) {
        self.catalog = catalog
        self.albums = Self.albums(from: catalog)
        self.playlists = (playlists.isEmpty ? playlistStore.load() : playlists)
            .filter { $0.id != Self.libraryPlaylistID }
        self.queue = catalog
        self.currentTrack = catalog.first
        self.serverClient = serverClient
        self.playlistStore = playlistStore
        self.isCatalogLoading = automaticallyLoadsCatalog

        configureAudioSession()
        configureRemoteCommands()
        updateNowPlayingInfo()

        Task {
            await youtubeMusicSearchClient.prepare()
        }

        if automaticallyLoadsCatalog {
            catalogTask = Task { [weak self] in
                await self?.refreshCatalog()
            }
        }

        if automaticallySyncsPlayback {
            startPlaybackSync()
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        nowPlayingArtworkTask?.cancel()
        downloadPollTask?.cancel()
        queueNoticeTask?.cancel()
        playbackSyncTask?.cancel()
        volumeCommandTask?.cancel()
    }

    var isRemoteController: Bool {
        playbackSessionRole == .controller
    }

    var playbackSessionTitle: String {
        if isRemoteController {
            return "Controlling \(playbackHostName ?? "another device")"
        }
        if isSharedPlaybackSession {
            return playbackDevices.count > 1 ? "Playing for \(playbackDevices.count) devices" : "Shared playback"
        }
        return "Separate playback"
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

    var editablePlaylists: [AriaPlaylist] {
        playlists.filter { $0.id != Self.libraryPlaylistID }
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
        let groupedTracks = Dictionary(grouping: catalog.filter { $0.isStandalone != true }) { track in
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

            if let serverPlaylists = try? await serverClient.fetchPlaylists() {
                await mergeServerPlaylists(serverPlaylists, tracks: tracks)
            }
        } catch {
            catalogErrorMessage = error.localizedDescription
        }

        isCatalogLoading = false
    }

    func startDownload(
        link: String,
        album: String,
        albumArtist: String,
        year: String,
        kind: String = "album"
    ) async {
        guard !isDownloadStarting, downloadJob?.isActive != true else { return }

        let request = AriaDownloadRequest(
            link: link.trimmingCharacters(in: .whitespacesAndNewlines),
            album: album.trimmingCharacters(in: .whitespacesAndNewlines),
            albumArtist: albumArtist.trimmingCharacters(in: .whitespacesAndNewlines),
            year: year.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind
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

    func searchYouTubeMusicAlbums(query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            youtubeMusicResults = []
            youtubeMusicSearchError = nil
            return
        }

        isSearchingYouTubeMusic = true
        youtubeMusicSearchError = nil
        youtubeMusicResults = []

        do {
            let results = try await youtubeMusicSearchClient.searchAlbums(query: query)
            youtubeMusicResults = results
            youtubeMusicSearchError = results.isEmpty
                ? "No YouTube Music albums matched that search."
                : nil
        } catch {
            youtubeMusicResults = []
            youtubeMusicSearchError = error.localizedDescription
        }

        isSearchingYouTubeMusic = false
    }

    func searchYouTubeMusic(query: String, category: YouTubeMusicSearchCategory) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            youtubeMusicResults = []
            youtubeMusicSongResults = []
            youtubeMusicPlaylistResults = []
            youtubeMusicSearchError = nil
            return
        }

        isSearchingYouTubeMusic = true
        youtubeMusicSearchError = nil
        youtubeMusicResults = []
        youtubeMusicSongResults = []
        youtubeMusicPlaylistResults = []
        do {
            switch category {
            case .albums:
                youtubeMusicResults = try await youtubeMusicSearchClient.searchAlbums(query: query)
            case .songs:
                youtubeMusicSongResults = try await youtubeMusicSearchClient.searchSongs(query: query)
            case .playlists:
                youtubeMusicPlaylistResults = try await youtubeMusicSearchClient.searchPlaylists(query: query)
            }
            let isEmpty = youtubeMusicResults.isEmpty
                && youtubeMusicSongResults.isEmpty
                && youtubeMusicPlaylistResults.isEmpty
            youtubeMusicSearchError = isEmpty ? "No YouTube Music \(category.rawValue.lowercased()) matched that search." : nil
        } catch {
            youtubeMusicSearchError = error.localizedDescription
        }
        isSearchingYouTubeMusic = false
    }

    func startDownload(_ result: YouTubeMusicAlbumResult) async {
        guard !isAlbumDownloaded(result) else { return }

        await startDownload(
            link: result.downloadLink,
            album: result.title,
            albumArtist: result.artist,
            year: result.year
        )
    }

    func startDownload(_ result: YouTubeMusicSongResult) async {
        guard !isSongDownloaded(result) else { return }
        await startDownload(
            link: result.downloadLink,
            album: result.title,
            albumArtist: result.artist,
            year: "",
            kind: "song"
        )
    }

    func startDownload(_ result: YouTubeMusicPlaylistResult) async {
        await startDownload(
            link: result.downloadLink,
            album: result.title,
            albumArtist: result.curator,
            year: "",
            kind: "playlist"
        )
    }

    func isSongDownloaded(_ result: YouTubeMusicSongResult) -> Bool {
        let title = Self.normalizedWords(in: result.title).joined(separator: " ")
        let artist = Self.canonicalArtistName(result.artist)
        return catalog.contains { track in
            Self.normalizedWords(in: track.title).joined(separator: " ") == title
                && Self.canonicalArtistName(track.artist) == artist
        }
    }

    func presentArtist(named name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        presentedArtist = ArtistSelection(name: name)
    }

    func dismissArtist() {
        presentedArtist = nil
    }

    func songs(byArtist name: String) -> [Track] {
        let artist = Self.canonicalArtistName(name)
        return catalog
            .filter { Self.canonicalArtistName($0.artist) == artist }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    func albums(byArtist name: String) -> [AriaAlbum] {
        let artist = Self.canonicalArtistName(name)
        return albums.filter { album in
            Self.canonicalArtistName(album.artist) == artist
                || album.tracks.contains { Self.canonicalArtistName($0.artist) == artist }
        }
    }

    func albumResult(_ result: YouTubeMusicAlbumResult, belongsToArtist name: String) -> Bool {
        Self.canonicalArtistName(result.artist) == Self.canonicalArtistName(name)
    }

    func deleteAlbum(_ album: AriaAlbum) async throws -> AlbumDeletionResult {
        guard let track = album.tracks.first else {
            throw AriaServerError.invalidResponse
        }
        let result = try await serverClient.deleteAlbum(id: album.serverID, containing: track)
        await refreshCatalog()
        return result
    }

    func isAlbumDownloaded(_ result: YouTubeMusicAlbumResult) -> Bool {
        let resultTitle = Self.canonicalAlbumName(result.title)
        let resultArtist = Self.canonicalArtistName(result.artist)

        return albums.contains { album in
            Self.canonicalAlbumName(album.title) == resultTitle
                && Self.canonicalArtistName(album.artist) == resultArtist
        }
    }

    func isDownloading(_ result: YouTubeMusicAlbumResult) -> Bool {
        guard let downloadJob, downloadJob.isActive else { return false }

        return Self.canonicalAlbumName(downloadJob.album) == Self.canonicalAlbumName(result.title)
            && Self.canonicalArtistName(downloadJob.albumArtist) == Self.canonicalArtistName(result.artist)
    }

    private static func canonicalAlbumName(_ value: String) -> String {
        let titleBeforeVariant = value.components(separatedBy: "|").first ?? value
        let withoutEditionNotes = titleBeforeVariant.replacingOccurrences(
            of: #"\([^)]*\)|\[[^\]]*\]"#,
            with: "",
            options: .regularExpression
        )
        let editionWords: Set<String> = [
            "anniversary", "bonus", "complete", "deluxe", "disc", "disk", "edition",
            "expanded", "reissue", "remaster", "remastered", "repented", "redux",
            "version"
        ]

        return normalizedWords(in: withoutEditionNotes)
            .filter { !editionWords.contains($0) && Int($0) == nil }
            .joined(separator: " ")
    }

    private static func canonicalArtistName(_ value: String) -> String {
        normalizedWords(in: value).joined(separator: " ")
    }

    private static func normalizedWords(in value: String) -> [String] {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    func clearFinishedDownload() {
        guard downloadJob?.isFinished == true else { return }
        downloadJob = nil
        downloadErrorMessage = nil
    }

    func play(_ track: Track, from collection: [Track]? = nil) {
        if shouldRoutePlaybackCommand {
            let remoteQueue = collection?.isEmpty == false ? collection! : (queue.isEmpty ? [track] : queue)
            queue = remoteQueue
            manuallyQueuedTrackIDs.removeAll()
            currentTrack = track
            elapsed = 0
            isPlaying = true
            sendPlaybackCommand(action: "play", track: track, queue: remoteQueue)
            refreshNowPlayingArtwork(for: track)
            updateNowPlayingInfo()
            return
        }

        if let collection, !collection.isEmpty {
            let keepsExistingQueue = collection.elementsEqual(queue) { firstTrack, secondTrack in
                firstTrack.id == secondTrack.id
            }
            queue = collection
            if !keepsExistingQueue {
                manuallyQueuedTrackIDs.removeAll()
            }
        } else if !queue.contains(track) {
            queue.insert(track, at: 0)
        }

        manuallyQueuedTrackIDs.removeAll { $0 == track.id }
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
        if shouldRoutePlaybackCommand {
            isPlaying.toggle()
            sendPlaybackCommand(action: "playPause")
            updateNowPlayingInfo()
            return
        }

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
        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "next")
            return
        }

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
        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "previous")
            return
        }

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
        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "next")
            return
        }

        guard let currentTrack, canSkipToNextTrack else { return }

        let nextTrack = orderedNext(after: currentTrack)
        guard let nextTrack else { return }

        play(nextTrack, from: queue)
    }

    func skipToPreviousTrack() {
        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "previous")
            return
        }

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

        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "seek", position: targetTime)
            updateNowPlayingInfo()
            return
        }

        if audioPlayer != nil {
            audioPlayer?.seek(to: CMTime(seconds: targetTime, preferredTimescale: 600))
        }

        updateNowPlayingInfo()
    }

    func toggleShuffle() {
        if shouldRoutePlaybackCommand {
            isShuffleEnabled.toggle()
            sendPlaybackCommand(action: "shuffle")
            updateRemoteCommandAvailability()
            return
        }

        if isShuffleEnabled {
            isShuffleEnabled = false
        } else {
            shuffleQueue()
            isShuffleEnabled = true
        }

        updateRemoteCommandAvailability()
    }

    func cycleRepeatMode() {
        if shouldRoutePlaybackCommand {
            advanceRepeatMode()
            sendPlaybackCommand(action: "repeat")
            updateRemoteCommandAvailability()
            return
        }

        advanceRepeatMode()
        updateRemoteCommandAvailability()
    }

    private func advanceRepeatMode() {
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

    func playNow(_ track: Track) {
        if shouldRoutePlaybackCommand {
            play(track, from: queue)
            return
        }

        if currentTrack?.id == track.id {
            restart(track)
            return
        }

        removeQueuedOccurrence(of: track)
        queue.insert(track, at: insertionIndexAfterCurrent())
        play(track, from: queue)
    }

    func playNext(_ track: Track) {
        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "playNext", track: track)
        }

        guard currentTrack?.id != track.id else {
            publishQueueNotice(message: "Already playing \(track.title)", symbolName: "waveform")
            return
        }

        removeQueuedOccurrence(of: track)
        queue.insert(track, at: insertionIndexAfterCurrent())
        manuallyQueuedTrackIDs.insert(track.id, at: 0)
        publishQueueNotice(message: "\(track.title) will play next", symbolName: "text.line.first.and.arrowtriangle.forward")
    }

    func addToQueue(_ track: Track) {
        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "addToQueue", track: track)
        }

        guard currentTrack?.id != track.id else {
            publishQueueNotice(message: "Already playing \(track.title)", symbolName: "waveform")
            return
        }

        removeQueuedOccurrence(of: track)

        let firstUpcomingIndex = insertionIndexAfterCurrent()
        let lastManualIndex = manuallyQueuedTrackIDs
            .compactMap { queuedID in
                queue.firstIndex { $0.id == queuedID }
            }
            .filter { $0 >= firstUpcomingIndex }
            .max()
        let insertionIndex = min((lastManualIndex ?? (firstUpcomingIndex - 1)) + 1, queue.endIndex)

        queue.insert(track, at: insertionIndex)
        manuallyQueuedTrackIDs.append(track.id)
        publishQueueNotice(message: "Added \(track.title) to queue", symbolName: "checkmark.circle.fill")
    }

    func moveQueuedTrack(_ trackID: UUID, to targetID: UUID) {
        guard trackID != targetID else { return }
        if shouldRoutePlaybackCommand,
           let track = queue.first(where: { $0.id == trackID }),
           let target = queue.first(where: { $0.id == targetID }) {
            sendPlaybackCommand(action: "moveQueueItem", track: track, targetTrack: target)
        }
        guard currentTrack?.id != trackID, currentTrack?.id != targetID else { return }
        guard
            let sourceIndex = queue.firstIndex(where: { $0.id == trackID }),
            let targetIndex = queue.firstIndex(where: { $0.id == targetID })
        else {
            return
        }

        let firstUpcomingIndex: Int
        if let currentTrack, let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id }) {
            firstUpcomingIndex = queue.index(after: currentIndex)
        } else {
            firstUpcomingIndex = queue.startIndex
        }

        guard sourceIndex >= firstUpcomingIndex, targetIndex >= firstUpcomingIndex else { return }

        let movesDown = sourceIndex < targetIndex
        let movedTrack = queue.remove(at: sourceIndex)
        guard let adjustedTargetIndex = queue.firstIndex(where: { $0.id == targetID }) else { return }

        let destinationIndex = movesDown ? queue.index(after: adjustedTargetIndex) : adjustedTargetIndex
        queue.insert(movedTrack, at: min(destinationIndex, queue.endIndex))

        var manualIDs = Set(manuallyQueuedTrackIDs)
        manualIDs.insert(trackID)
        manuallyQueuedTrackIDs = queue.map(\.id).filter { manualIDs.contains($0) }
    }

    private func insertionIndexAfterCurrent() -> Int {
        guard
            let currentTrack,
            let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id })
        else {
            return queue.startIndex
        }

        return queue.index(after: currentIndex)
    }

    private func removeQueuedOccurrence(of track: Track) {
        queue.removeAll { $0.id == track.id }
        manuallyQueuedTrackIDs.removeAll { $0 == track.id }
    }

    func removeFromQueue(_ track: Track) {
        if shouldRoutePlaybackCommand {
            sendPlaybackCommand(action: "removeFromQueue", track: track)
        }

        guard currentTrack?.id != track.id else { return }

        queue.removeAll { $0.id == track.id }
        manuallyQueuedTrackIDs.removeAll { $0 == track.id }
        publishQueueNotice(message: "Removed \(track.title) from queue", symbolName: "trash.fill")
    }

    func dismissQueueNotice() {
        queueNoticeTask?.cancel()
        queueNotice = nil
    }

    @discardableResult
    func createPlaylist(containing track: Track? = nil) -> AriaPlaylist {
        let playlistNumber = playlists.filter { $0.title.hasPrefix("New Playlist") }.count + 1
        var playlist = AriaPlaylist(
            title: "New Playlist \(playlistNumber)",
            subtitle: "0 songs",
            tracks: [],
            revision: 1
        )

        if let track {
            playlist.tracks.append(track)
            playlist.subtitle = subtitle(forTrackCount: playlist.tracks.count)
        }

        playlists.insert(playlist, at: 0)
        persistPlaylists()
        syncPlaylist(playlist)
        return playlist
    }

    func add(_ track: Track, to playlist: AriaPlaylist) {
        guard playlist.id != Self.libraryPlaylistID else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        guard !playlists[index].tracks.contains(where: { $0.id == track.id }) else { return }

        playlists[index].tracks.append(track)
        playlists[index].subtitle = subtitle(forTrackCount: playlists[index].tracks.count)
        finishPlaylistMutation(at: index)
    }

    func remove(_ track: Track, from playlist: AriaPlaylist) {
        guard playlist.id != Self.libraryPlaylistID else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        playlists[index].tracks.removeAll { $0.id == track.id }
        playlists[index].subtitle = subtitle(forTrackCount: playlists[index].tracks.count)
        finishPlaylistMutation(at: index)
    }

    func rename(_ playlist: AriaPlaylist, to title: String) {
        guard playlist.id != Self.libraryPlaylistID else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        playlists[index].title = trimmedTitle
        finishPlaylistMutation(at: index)
    }

    func setCoverImageData(_ imageData: Data?, for playlist: AriaPlaylist) {
        guard playlist.id != Self.libraryPlaylistID else { return }
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }

        playlists[index].coverImageData = imageData
        finishPlaylistMutation(at: index)
    }

    func canCustomize(_ playlist: AriaPlaylist) -> Bool {
        playlist.id != Self.libraryPlaylistID
    }

    func playlist(_ playlist: AriaPlaylist, contains track: Track) -> Bool {
        playlist.tracks.contains { $0.id == track.id }
    }

    private func subtitle(forTrackCount count: Int) -> String {
        count == 1 ? "1 song" : "\(count) songs"
    }

    private func persistPlaylists() {
        playlistStore.save(
            playlists.filter { $0.id != Self.libraryPlaylistID }
        )
    }

    private func finishPlaylistMutation(at index: Int) {
        playlists[index].revision = (playlists[index].revision ?? 0) + 1
        let playlist = playlists[index]
        persistPlaylists()
        syncPlaylist(playlist)
    }

    private func syncPlaylist(_ playlist: AriaPlaylist) {
        Task { [serverClient] in
            _ = try? await serverClient.savePlaylist(playlist)
        }
    }

    private func mergeServerPlaylists(
        _ serverPlaylists: [AriaServerPlaylist],
        tracks: [Track]
    ) async {
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let localPlaylists = playlists.filter { $0.id != Self.libraryPlaylistID }
        let localByID = Dictionary(uniqueKeysWithValues: localPlaylists.map { ($0.id, $0) })
        var merged: [AriaPlaylist] = []
        var uploads: [AriaPlaylist] = []
        var seen = Set<UUID>()

        for serverPlaylist in serverPlaylists {
            let serverModel = serverPlaylist.playlist(using: tracksByID)
            if let local = localByID[serverPlaylist.id],
               (local.revision ?? 0) > serverPlaylist.revision {
                merged.append(local)
                uploads.append(local)
            } else {
                merged.append(serverModel)
            }
            seen.insert(serverPlaylist.id)
        }

        for local in localPlaylists where seen.insert(local.id).inserted {
            merged.append(local)
            uploads.append(local)
        }

        let libraryPlaylist = playlists.first { $0.id == Self.libraryPlaylistID }
        playlists = (libraryPlaylist.map { [$0] } ?? []) + merged
        persistPlaylists()

        for playlist in uploads {
            _ = try? await serverClient.savePlaylist(playlist)
        }
    }

    private func publishQueueNotice(message: String, symbolName: String) {
        let notice = QueueNotice(message: message, symbolName: symbolName)
        queueNoticeTask?.cancel()
        queueNotice = notice

        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        queueNoticeTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            guard !Task.isCancelled, self?.queueNotice?.id == notice.id else { return }
            self?.queueNotice = nil
        }
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

    func startSeparatePlaybackSession() {
        switchPlaybackSession(to: UUID().uuidString.lowercased())
    }

    func joinSharedPlaybackSession() {
        switchPlaybackSession(to: Self.sharedPlaybackSessionID)
    }

    private var shouldRoutePlaybackCommand: Bool {
        !isApplyingPlaybackSync && playbackSessionRole != .host
    }

    private func startPlaybackSync() {
        playbackSyncTask?.cancel()
        playbackSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.syncPlaybackSession()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    private func syncPlaybackSession() async {
        guard !isSyncingPlayback else { return }
        isSyncingPlayback = true
        defer { isSyncingPlayback = false }

        let device = UIDevice.current
        let queueIDs = queue.map(remotePlaybackID)
        let includesQueue = playbackSessionRole != .controller && queueIDs != lastSentPlaybackQueueIDs
        let request = PlaybackSyncRequest(
            deviceID: playbackDeviceID,
            deviceName: device.name,
            platform: device.userInterfaceIdiom == .pad ? "iPadOS" : "iOS",
            sessionID: playbackSessionID,
            lastCommandID: lastPlaybackCommandID,
            state: playbackStateUpdate(queueIDs: includesQueue ? queueIDs : nil)
        )

        do {
            let previousRole = playbackSessionRole
            let response = try await serverClient.syncPlayback(request)
            playbackSessionError = nil
            playbackSessionRole = response.role
            playbackHostName = response.hostName
            playbackDevices = response.devices
            isSharedPlaybackSession = response.isShared
            if response.role == .host, includesQueue {
                lastSentPlaybackQueueIDs = queueIDs
            }

            switch response.role {
            case .controller:
                shouldStartAudioWhenBecomingHost = true
                applyPlaybackState(response.state, stopsLocalAudio: true)
            case .host:
                if previousRole == .controller || shouldStartAudioWhenBecomingHost {
                    applyPlaybackState(response.state, stopsLocalAudio: true)
                    startLocalAudioForCurrentState()
                    shouldStartAudioWhenBecomingHost = false
                }
                applyPlaybackCommands(response.commands)
            }
        } catch {
            playbackSessionError = error.localizedDescription
        }
    }

    private func playbackStateUpdate(queueIDs: [String]?) -> PlaybackStateUpdate {
        PlaybackStateUpdate(
            trackID: currentTrack.map(remotePlaybackID),
            queueTrackIDs: queueIDs,
            elapsed: elapsed,
            isPlaying: isPlaying,
            isShuffleEnabled: isShuffleEnabled,
            repeatMode: repeatMode.rawValue,
            volume: volume
        )
    }

    private func applyPlaybackState(_ state: RemotePlaybackState, stopsLocalAudio: Bool) {
        if stopsLocalAudio {
            audioPlayer?.pause()
            audioPlayer = nil
            removeEndObserver()
            timer?.cancel()
            timer = nil
        }

        let tracksByID = Dictionary(uniqueKeysWithValues: catalog.map { (remotePlaybackID(for: $0), $0) })
        let remoteQueue = state.queueTrackIDs.compactMap { tracksByID[$0.lowercased()] }
        let remoteTrack = state.trackID.flatMap { tracksByID[$0.lowercased()] }
            ?? remoteQueue.first

        isApplyingPlaybackSync = true
        queue = remoteQueue
        manuallyQueuedTrackIDs.removeAll()
        currentTrack = remoteTrack
        isPlaying = state.isPlaying
        isShuffleEnabled = state.isShuffleEnabled
        repeatMode = RepeatMode(rawValue: state.repeatMode) ?? .off
        volume = state.volume

        let age = state.updatedAt.map { max(Date().timeIntervalSince1970 - $0, 0) } ?? 0
        let projectedElapsed = state.elapsed + (state.isPlaying ? min(age, 3) : 0)
        if let duration = remoteTrack?.duration, duration > 0 {
            elapsed = min(max(projectedElapsed, 0), duration)
        } else {
            elapsed = max(projectedElapsed, 0)
        }
        isApplyingPlaybackSync = false

        if let remoteTrack {
            refreshNowPlayingArtwork(for: remoteTrack)
        }
        updateNowPlayingInfo()
    }

    private func startLocalAudioForCurrentState() {
        guard let currentTrack else { return }
        let shouldPlay = isPlaying
        let targetElapsed = elapsed
        startPlayback(for: currentTrack)
        audioPlayer?.seek(to: CMTime(seconds: targetElapsed, preferredTimescale: 600))

        if shouldPlay {
            isPlaying = true
            startTimer()
        } else {
            isPlaying = false
            audioPlayer?.pause()
            timer?.cancel()
            timer = nil
        }
        updateNowPlayingInfo()
    }

    private func applyPlaybackCommands(_ commands: [RemotePlaybackCommand]) {
        for command in commands.sorted(by: { $0.id < $1.id }) {
            isApplyingPlaybackSync = true
            applyPlaybackCommand(command)
            isApplyingPlaybackSync = false
            lastPlaybackCommandID = max(lastPlaybackCommandID, command.id)
        }
    }

    private func applyPlaybackCommand(_ command: RemotePlaybackCommand) {
        switch command.action {
        case "play":
            guard let track = track(forRemoteID: command.trackID) else { return }
            let remoteQueue = tracks(forRemoteIDs: command.queueTrackIDs)
            play(track, from: remoteQueue.isEmpty ? nil : remoteQueue)
        case "playPause":
            playPause()
        case "next":
            next()
        case "previous":
            previous()
        case "seek":
            guard let position = command.position, let duration = currentTrack?.duration, duration > 0 else { return }
            seek(toProgress: position / duration)
        case "shuffle":
            toggleShuffle()
        case "repeat":
            cycleRepeatMode()
        case "setVolume":
            if let value = command.value {
                volume = min(max(value, 0), 1)
            }
        case "playNext":
            if let track = track(forRemoteID: command.trackID) {
                playNext(track)
            }
        case "addToQueue":
            if let track = track(forRemoteID: command.trackID) {
                addToQueue(track)
            }
        case "removeFromQueue":
            if let track = track(forRemoteID: command.trackID) {
                removeFromQueue(track)
            }
        case "moveQueueItem":
            if let movedTrack = track(forRemoteID: command.trackID),
               let targetTrack = track(forRemoteID: command.targetTrackID) {
                moveQueuedTrack(movedTrack.id, to: targetTrack.id)
            }
        default:
            break
        }
    }

    private func sendPlaybackCommand(
        action: String,
        track: Track? = nil,
        queue: [Track]? = nil,
        targetTrack: Track? = nil,
        position: TimeInterval? = nil,
        value: Double? = nil
    ) {
        let command = PlaybackCommandRequest(
            deviceID: playbackDeviceID,
            action: action,
            trackID: track.map(remotePlaybackID),
            targetTrackID: targetTrack.map(remotePlaybackID),
            queueTrackIDs: queue?.map(remotePlaybackID),
            position: position,
            value: value
        )
        let sessionID = playbackSessionID

        Task { [weak self, serverClient] in
            do {
                try await serverClient.sendPlaybackCommand(command, sessionID: sessionID)
                await self?.syncPlaybackSession()
            } catch {
                self?.playbackSessionError = error.localizedDescription
            }
        }
    }

    private func scheduleRemoteVolumeCommand(_ value: Double) {
        volumeCommandTask?.cancel()
        volumeCommandTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.sendPlaybackCommand(action: "setVolume", value: value)
        }
    }

    private func switchPlaybackSession(to sessionID: String) {
        shouldStartAudioWhenBecomingHost = isRemoteController
        playbackSessionID = sessionID
        lastPlaybackCommandID = 0
        lastSentPlaybackQueueIDs = []
        playbackSessionRole = nil
        playbackHostName = nil
        playbackDevices = []
        playbackSessionError = nil
        isSharedPlaybackSession = sessionID == Self.sharedPlaybackSessionID
        UserDefaults.standard.set(sessionID, forKey: Self.playbackSessionIDDefaultsKey)
        Task { [weak self] in
            await self?.syncPlaybackSession()
        }
    }

    private func tracks(forRemoteIDs ids: [String]?) -> [Track] {
        guard let ids else { return [] }
        let tracksByID = Dictionary(uniqueKeysWithValues: catalog.map { (remotePlaybackID(for: $0), $0) })
        return ids.compactMap { tracksByID[$0.lowercased()] }
    }

    private func track(forRemoteID id: String?) -> Track? {
        guard let id else { return nil }
        return catalog.first { remotePlaybackID(for: $0) == id.lowercased() }
    }

    private func remotePlaybackID(for track: Track) -> String {
        track.id.uuidString.lowercased()
    }

    private static func stablePlaybackDeviceID() -> String {
        if let saved = UserDefaults.standard.string(forKey: playbackDeviceIDDefaultsKey), !saved.isEmpty {
            return saved
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: playbackDeviceIDDefaultsKey)
        return id
    }

    private static func savedPlaybackSessionID() -> String {
        guard let saved = UserDefaults.standard.string(forKey: playbackSessionIDDefaultsKey) else {
            return sharedPlaybackSessionID
        }
        return saved == sharedPlaybackSessionID || UUID(uuidString: saved) != nil
            ? saved
            : sharedPlaybackSessionID
    }

    private func replaceCatalog(with tracks: [Track]) {
        audioPlayer?.pause()
        removeEndObserver()

        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let userPlaylists = playlists
            .filter { $0.id != Self.libraryPlaylistID }
            .map { playlist in
                var refreshedPlaylist = playlist
                refreshedPlaylist.tracks = playlist.tracks.map { track in
                    tracksByID[track.id] ?? track
                }
                refreshedPlaylist.subtitle = subtitle(forTrackCount: refreshedPlaylist.tracks.count)
                return refreshedPlaylist
            }

        catalog = tracks
        albums = Self.albums(from: tracks)
        queue = tracks
        manuallyQueuedTrackIDs.removeAll()
        playlists = [
            AriaPlaylist(
                id: Self.libraryPlaylistID,
                title: "Fedora songs",
                subtitle: subtitle(forTrackCount: tracks.count),
                tracks: tracks
            )
        ] + userPlaylists
        persistPlaylists()
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
            manuallyQueuedTrackIDs.removeAll()
            return
        }

        var otherTracks = queue
        otherTracks.remove(at: currentIndex)
        queue = [currentTrack] + otherTracks.shuffled()
        manuallyQueuedTrackIDs.removeAll()
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

        persistPlaylists()

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
