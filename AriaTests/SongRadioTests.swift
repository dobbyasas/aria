import XCTest
import SwiftUI
@testable import Aria

private final class RadioURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private actor RadioProvider: SongRadioProviding {
    var songs: [YouTubeMusicSongResult]
    var delay: Duration
    var calls = 0
    init(_ songs: [YouTubeMusicSongResult], delay: Duration = .zero) {
        self.songs = songs
        self.delay = delay
    }
    func searchSongs(query: String, limit: Int) async throws -> [YouTubeMusicSongResult] { songs }
    func radio(seedVideoID: String, continuation: String?) async throws -> SongRadioPage {
        calls += 1
        // Deliberately return even when cancelled, exercising session guards.
        try? await Task.sleep(for: delay)
        return SongRadioPage(songs: songs, continuation: "next-page")
    }
}

@MainActor
final class SongRadioTests: XCTestCase {
    private var defaults: UserDefaults!
    private var defaultsName: String!
    private var players: [PlayerViewModel] = []
    private var serverTracks: [Track] = []
    private var downloadTracks: [Track] = []
    private var downloadedLinks: [String] = []
    private var downloadSources: [String] = []
    private var bulkDeleteRequests = 0
    private var deletedIDs: [String] = []
    private var deleteBusyCount = 0
    private var deleteFails = false
    private var keepFails = false
    private var keepBusyCount = 0
    private var failedDownloadTitles: Set<String> = []
    private var reusedTrackID: UUID?

    override func setUp() async throws {
        defaultsName = "AriaRadioTests.\(UUID())"
        defaults = UserDefaults(suiteName: defaultsName)!
    }

    override func tearDown() async throws {
        players.forEach { $0.stopRadio(); if $0.isPlaying { $0.playPause() } }
        players = []
        defaults.removePersistentDomain(forName: defaultsName)
        RadioURLProtocol.handler = nil
    }

    private func track(_ n: Int) -> Track {
        Track(title: "Song \(n)", artist: "Artist", album: "Album", duration: 240,
              artwork: ArtworkPalette(topHex: "111111", bottomHex: "222222", symbolName: "music.note"))
    }

    private func song(_ track: Track, id: String? = nil) -> YouTubeMusicSongResult {
        YouTubeMusicSongResult(id: id ?? String(track.id.uuidString.prefix(11)), title: track.title,
                              artist: track.artist, artworkURL: nil)
    }

    private func makePlayer(tracks: [Track], provider: RadioProvider) -> PlayerViewModel {
        serverTracks = tracks
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RadioURLProtocol.self]
        var client = AriaServerClient(baseURLs: [URL(string: "https://aria.test")!])
        client.session = URLSession(configuration: configuration)
        // URLProtocol callbacks run off-main. This fixture is only mutated inside
        // the callback, or after awaiting the corresponding app operation.
        RadioURLProtocol.handler = { [self] request in
            switch (request.httpMethod!, request.url!.path) {
            case ("GET", "/api/tracks"):
                return (200, try JSONEncoder().encode(serverTracks))
            case ("GET", "/api/playlists"):
                return (200, Data("[]".utf8))
            case ("GET", "/api/downloads"):
                return (200, Data("{\"active\":null}".utf8))
            case ("POST", "/api/downloads"):
                var body = request.httpBody
                if body == nil, let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        data.append(buffer, count: count)
                    }
                    body = data
                }
                let json = try JSONSerialization.jsonObject(with: body!) as! [String: String]
                downloadedLinks.append(json["link"]!)
                downloadSources.append(json["source"] ?? "manual")
                if !failedDownloadTitles.contains(json["album"]!), var track = downloadTracks.first(where: { $0.title == json["album"] }) {
                    track.isRadioDownload = json["source"] == "radio"
                    serverTracks.append(track)
                }
                var job: [String: Any] = ["id": "job", "status": failedDownloadTitles.contains(json["album"]!) ? "failed" : "succeeded", "phase": "Done", "message": "Done",
                    "progress": 1, "album": json["album"]!, "albumArtist": "Artist", "year": "", "filesStarted": 1, "outputTail": []]
                if let reusedTrackID { job["trackID"] = reusedTrackID.uuidString }
                return (200, try JSONSerialization.data(withJSONObject: job))
            case ("POST", let path) where path.hasPrefix("/api/radio-downloads/") && path.hasSuffix("/keep"):
                if keepFails { return (500, Data("{\"error\":\"Disk unavailable\"}".utf8)) }
                if keepBusyCount > 0 {
                    keepBusyCount -= 1
                    return (409, Data("{\"error\":\"Download in progress\"}".utf8))
                }
                let id = String(path.split(separator: "/")[2])
                guard let index = serverTracks.firstIndex(where: { $0.id.uuidString.lowercased() == id }) else {
                    return (404, Data("{}".utf8))
                }
                serverTracks[index].isRadioDownload = false
                return (200, Data("{}".utf8))
            case ("DELETE", let path):
                if deleteFails { return (500, Data("{\"error\":\"Server unavailable\"}".utf8)) }
                if deleteBusyCount > 0 {
                    deleteBusyCount -= 1
                    return (409, Data("{\"error\":\"Download in progress\"}".utf8))
                }
                if path == "/api/radio-downloads" {
                    bulkDeleteRequests += 1
                    let ids = serverTracks.filter { $0.isRadioDownload == true }.map { $0.id.uuidString.lowercased() }
                    serverTracks.removeAll { $0.isRadioDownload == true }
                    deletedIDs.append(contentsOf: ids)
                    return (200, try JSONSerialization.data(withJSONObject: ["deletedFiles": ids.count, "deletedTrackIDs": ids, "updatedPlaylists": 0]))
                }
                let id = String(path.split(separator: "/").last!)
                deletedIDs.append(id)
                serverTracks.removeAll { $0.id.uuidString.lowercased() == id }
                return (200, Data("{}".utf8))
            default: throw URLError(.unsupportedURL)
            }
        }
        let store = PlaylistStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).json"))
        let player = PlayerViewModel(catalog: tracks, serverClient: client, playlistStore: store,
                                    automaticallyLoadsCatalog: false, automaticallySyncsPlayback: false,
                                    radioClient: provider, radioDefaults: defaults)
        players.append(player)
        return player
    }

    private func eventually(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Condition did not become true", file: file, line: line)
    }

    func testDownloadedSeedPlaysFirstAndRefillsAfterNext() async throws {
        let tracks = (0..<8).map(track)
        let provider = RadioProvider(tracks.map { song($0) })
        let player = makePlayer(tracks: tracks, provider: provider)
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(player.upNext.map(\.id), Array(tracks[1...3]).map(\.id))
        XCTAssertTrue(downloadedLinks.isEmpty)
        player.next()
        try await eventually { player.remainingUpNextCount == 3 }
        XCTAssertEqual(player.currentTrack?.id, tracks[1].id)
        XCTAssertEqual(player.upNext.last?.id, tracks[4].id)
    }

    func testMissingSeedDownloadsBeforePlayingWithEmptyLibrary() async throws {
        let tracks = (0..<4).map(track)
        let provider = RadioProvider(tracks.map { song($0) })
        let player = makePlayer(tracks: [], provider: provider)
        downloadTracks = tracks
        player.startRadio(song(tracks[0]))
        try await eventually { player.queue.count == 4 }
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(downloadedLinks.count, 4)
        XCTAssertEqual(downloadSources, Array(repeating: "radio", count: 4))
        XCTAssertEqual(player.radioDownloadCount, 4)
        XCTAssertTrue(player.isPlaying)
    }

    func testCatalogRefreshPreservesPlaybackPositionAndRadioQueue() async throws {
        let tracks = (0..<6).map(track)
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }))
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        player.elapsed = 42
        let ids = player.queue.map(\.id)
        let refreshStarted = Date()
        await player.refreshCatalog()
        XCTAssertEqual(player.queue.map(\.id), ids)
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertGreaterThanOrEqual(player.elapsed, 42)
        XCTAssertLessThanOrEqual(player.elapsed, 43 + Date().timeIntervalSince(refreshStarted))
        XCTAssertTrue(player.isPlaying)
    }

    func testOrdinaryPlaybackCancelsDelayedRadioResults() async throws {
        let tracks = (0..<6).map(track)
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }, delay: .milliseconds(120)))
        player.startRadio(tracks[0])
        try await eventually { player.currentTrack?.id == tracks[0].id }
        player.play(tracks[5], from: [tracks[5]])
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(player.isRadioActive)
        XCTAssertEqual(player.queue.map(\.id), [tracks[5].id])
        XCTAssertNil(player.radioErrorMessage)
    }

    func testPauseWhileWaitingDoesNotAutoplayArrivingSong() async throws {
        let tracks = (0..<6).map(track)
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }, delay: .milliseconds(120)))
        player.startRadio(tracks[0])
        try await eventually { player.currentTrack?.id == tracks[0].id }
        player.next()
        XCTAssertTrue(player.isWaitingForRadioTrack)
        player.playPause()
        try await eventually { player.queue.count == 4 }
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        player.playPause()
        XCTAssertEqual(player.currentTrack?.id, tracks[1].id)
        XCTAssertTrue(player.isPlaying)
    }

    func testRemoveSkipsImmediatelyThenDeletesAndPersistsExclusion() async throws {
        let tracks = (0..<8).map(track)
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }))
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        player.next()
        try await eventually { player.remainingUpNextCount == 3 }
        deleteBusyCount = 1
        player.removeCurrentSongFromRadio()
        XCTAssertEqual(player.currentTrack?.id, tracks[2].id)
        XCTAssertEqual(player.pendingRadioDeletionCount, 1)
        try await eventually { player.pendingRadioDeletionCount == 0 }
        XCTAssertEqual(deletedIDs, [tracks[1].id.uuidString.lowercased()])
        XCTAssertFalse(player.catalog.contains { $0.id == tracks[1].id })
        XCTAssertTrue(defaults.stringArray(forKey: "aria.radio.excludedSongs")!.contains(tracks[1].radioIdentity))
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        XCTAssertFalse(player.queue.contains { $0.id == tracks[1].id })
        XCTAssertTrue(downloadedLinks.isEmpty)
    }

    func testBulkDeleteRemovesOnlyFlaggedTracksAndPreservesOrdinaryPlayback() async throws {
        var tracks = (0..<3).map(track)
        tracks[1].isRadioDownload = true
        tracks[2].isRadioDownload = true
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }))
        player.play(tracks[0], from: tracks)
        player.elapsed = 31
        XCTAssertEqual(player.radioDownloadCount, 2)
        await player.deleteAllRadioDownloads()
        XCTAssertEqual(bulkDeleteRequests, 1)
        XCTAssertEqual(Set(deletedIDs), Set(tracks.dropFirst().map { $0.id.uuidString.lowercased() }))
        XCTAssertEqual(player.queue.map(\.id), [tracks[0].id])
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertTrue(player.isPlaying)
        XCTAssertGreaterThanOrEqual(player.elapsed, 31)
        XCTAssertEqual(player.radioDownloadCount, 0)
        XCTAssertNil(player.radioCleanupError)
        XCTAssertNil(defaults.stringArray(forKey: "aria.radio.excludedSongs"))
    }

    func testBulkDeleteStopsRadioAndWaitsForDownloader() async throws {
        var tracks = (0..<6).map(track)
        tracks[0].isRadioDownload = true
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }))
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        deleteBusyCount = 1
        let cleanup = Task { await player.deleteAllRadioDownloads() }
        try await eventually { player.isDeletingRadioDownloads }
        XCTAssertFalse(player.isRadioActive)
        player.startRadio(tracks[1])
        XCTAssertFalse(player.isRadioActive)
        await cleanup.value
        XCTAssertFalse(player.isDeletingRadioDownloads)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.radioDownloadCount, 0)
        XCTAssertFalse(player.catalog.contains { $0.id == tracks[0].id })
    }

    func testBulkDeleteFailureKeepsFlagsAndOffersRetry() async throws {
        var tracks = [track(0)]
        tracks[0].isRadioDownload = true
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }))
        deleteFails = true
        await player.deleteAllRadioDownloads()
        XCTAssertNotNil(player.radioCleanupError)
        XCTAssertEqual(player.radioDownloadCount, 1)
        XCTAssertFalse(player.isDeletingRadioDownloads)
        deleteFails = false
        await player.deleteAllRadioDownloads()
        XCTAssertNil(player.radioCleanupError)
        XCTAssertEqual(player.radioDownloadCount, 0)
    }

    func testReusedDownloadTrackIDHandlesDifferentSavedMetadataAndDislike() async throws {
        let tracks = (0..<6).map(track)
        let seed = YouTubeMusicSongResult(id: "abcdefghijk", title: "Different saved title", artist: "Artist", artworkURL: nil)
        let player = makePlayer(tracks: tracks, provider: RadioProvider([seed] + tracks.dropFirst().map { song($0) }))
        reusedTrackID = tracks[0].id
        player.startRadio(seed)
        try await eventually { player.queue.count == 4 }
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(downloadedLinks.count, 1)
        player.removeCurrentSongFromRadio()
        try await eventually { player.pendingRadioDeletionCount == 0 }
        let excluded = defaults.stringArray(forKey: "aria.radio.excludedSongs")!
        XCTAssertTrue(excluded.contains("video:abcdefghijk"))
        XCTAssertTrue(excluded.contains(seed.radioIdentity))
    }

    func testFailedRecommendationDownloadSkipsToNextSong() async throws {
        let tracks = (0..<6).map(track)
        let player = makePlayer(tracks: [tracks[0]], provider: RadioProvider(tracks.map { song($0) }))
        downloadTracks = Array(tracks.dropFirst())
        failedDownloadTitles = [tracks[1].title]
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        XCTAssertEqual(player.upNext.map(\.id), Array(tracks[2...4]).map(\.id))
        XCTAssertNil(player.radioErrorMessage)
        XCTAssertTrue(player.isPlaying)
    }

    func testFailedDeletionSurvivesStoppingRadioAndRetriesOnRelaunch() async throws {
        let tracks = (0..<7).map(track)
        let provider = RadioProvider(tracks.map { song($0) })
        let player = makePlayer(tracks: tracks, provider: provider)
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        deleteFails = true
        player.removeCurrentSongFromRadio()
        try await eventually { player.radioDeletionError != nil }
        XCTAssertEqual(player.pendingRadioDeletionCount, 1)
        player.stopRadio()
        deleteFails = false
        let relaunched = makePlayer(tracks: tracks, provider: provider)
        try await eventually { relaunched.pendingRadioDeletionCount == 0 }
        XCTAssertEqual(deletedIDs, [tracks[0].id.uuidString.lowercased()])
        XCTAssertFalse(relaunched.catalog.contains { $0.id == tracks[0].id })
    }

    func testReplacingRadioCannotAppendCancelledSessionResults() async throws {
        let tracks = (0..<8).map(track)
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }, delay: .milliseconds(120)))
        player.startRadio(tracks[0])
        try await eventually { player.currentTrack?.id == tracks[0].id }
        player.startRadio(tracks[4])
        try await eventually { player.queue.count == 4 }
        XCTAssertEqual(player.queue.first?.id, tracks[4].id)
        XCTAssertEqual(player.currentTrack?.id, tracks[4].id)
        XCTAssertEqual(Set(player.queue.map(\.id)).count, 4)
        XCTAssertNil(player.radioErrorMessage)
    }

    func testPhoneRadioLayoutPreview() async throws {
        let tracks = (0..<5).map(track)
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }))
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        let controller = UIHostingController(rootView: NowPlayingView()
            .environmentObject(player).environmentObject(player.playbackClock))
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(150))
        window.layoutIfNeeded()
        controller.view.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "iPhone radio player"
        attachment.lifetime = .keepAlways
        add(attachment)
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("aria-radio-preview.png")
        try image.pngData()!.write(to: path)
        print("RADIO_PREVIEW=\(path.path)")
    }

    func testKeepProtectsFromCleanupAndPreservesPlayback() async throws {
        var tracks = (0..<3).map(track)
        tracks[0].isRadioDownload = true
        tracks[1].isRadioDownload = true
        let player = makePlayer(tracks: tracks, provider: RadioProvider([]))
        player.play(tracks[0], from: tracks)
        player.elapsed = 37
        await player.keepRadioDownload(tracks[0])
        XCTAssertNil(player.radioReviewError)
        XCTAssertEqual(player.radioDownloads.map(\.id), [tracks[1].id])
        XCTAssertEqual(player.currentTrack?.id, tracks[0].id)
        XCTAssertEqual(player.currentTrack?.isRadioDownload, false)
        XCTAssertEqual(player.elapsed, 37)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.queue.map(\.id), tracks.map(\.id))
        await player.refreshCatalog()
        await player.deleteAllRadioDownloads()
        XCTAssertTrue(player.catalog.contains { $0.id == tracks[0].id })
        XCTAssertTrue(player.catalog.contains { $0.id == tracks[2].id })
        XCTAssertFalse(player.catalog.contains { $0.id == tracks[1].id })
        XCTAssertTrue(player.isPlaying)
    }

    func testReviewFailureStaysVisibleAndCanBeRetried() async throws {
        var item = track(0)
        item.isRadioDownload = true
        let player = makePlayer(tracks: [item], provider: RadioProvider([]))
        keepFails = true
        await player.keepRadioDownload(item)
        XCTAssertNotNil(player.radioReviewError)
        XCTAssertEqual(player.radioDownloadCount, 1)
        XCTAssertTrue(player.radioReviewTrackIDs.isEmpty)
        deleteFails = true
        await player.deleteRadioDownload(item)
        XCTAssertNotNil(player.radioReviewError)
        XCTAssertEqual(player.radioDownloadCount, 1)
        deleteFails = false
        await player.deleteRadioDownload(item)
        XCTAssertNil(player.radioReviewError)
        XCTAssertTrue(player.catalog.isEmpty)
        XCTAssertEqual(deletedIDs, [item.id.uuidString.lowercased()])
    }

    func testBusyKeepBlocksCleanupUntilProtected() async throws {
        var item = track(0)
        item.isRadioDownload = true
        let player = makePlayer(tracks: [item], provider: RadioProvider([]))
        keepBusyCount = 1
        let keeping = Task { await player.keepRadioDownload(item) }
        try await eventually { !player.radioReviewTrackIDs.isEmpty }
        await player.deleteAllRadioDownloads()
        XCTAssertEqual(bulkDeleteRequests, 0)
        XCTAssertEqual(player.radioDownloadCount, 1)
        await keeping.value
        XCTAssertNil(player.radioReviewError)
        XCTAssertEqual(player.radioDownloadCount, 0)
        XCTAssertTrue(player.radioReviewTrackIDs.isEmpty)
    }

    func testReviewDeletingPlayingRadioSongAdvancesWithoutExcluding() async throws {
        var tracks = (0..<6).map(track)
        tracks[0].isRadioDownload = true
        let player = makePlayer(tracks: tracks, provider: RadioProvider(tracks.map { song($0) }))
        player.startRadio(tracks[0])
        try await eventually { player.queue.count == 4 }
        await player.deleteRadioDownload(tracks[0])
        XCTAssertNil(player.radioReviewError)
        XCTAssertEqual(player.currentTrack?.id, tracks[1].id)
        XCTAssertTrue(player.isRadioActive)
        XCTAssertTrue(player.isPlaying)
        XCTAssertFalse(player.catalog.contains { $0.id == tracks[0].id })
        XCTAssertFalse(player.queue.contains { $0.id == tracks[0].id })
        XCTAssertFalse((defaults.stringArray(forKey: "aria.radio.excludedSongs") ?? []).contains(tracks[0].radioIdentity))
    }

    func testRadioDownloadsLayouts() async throws {
        var tracks = (0..<5).map(track)
        for i in tracks.indices { tracks[i].isRadioDownload = i != 4 }
        let player = makePlayer(tracks: tracks, provider: RadioProvider([]))
        for size in [CGSize(width: 393, height: 852), CGSize(width: 1024, height: 1366)] {
            let host = UIHostingController(rootView: LibraryView(initialSection: .radioDownloads).environmentObject(player).preferredColorScheme(.dark))
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let path = FileManager.default.temporaryDirectory.appendingPathComponent("aria-radio-review-\(Int(size.width)).png")
            try image.pngData()!.write(to: path)
            print("RADIO_REVIEW_PREVIEW=\(path.path)")
            window.isHidden = true
        }
    }

    func testRadioParserKeepsPrimaryOrderSkipsUnavailableAndReadsContinuation() throws {
        func renderer(_ id: String, _ title: String) -> [String: Any] {
            ["playlistPanelVideoRenderer": ["videoId": id, "title": ["runs": [["text": title]]],
                "longBylineText": ["runs": [["text": "Artist", "navigationEndpoint": ["browseEndpoint": ["browseId": "UCartist"]]], ["text": " • Album"]]]]]
        }
        let wrapped: [String: Any] = ["playlistPanelVideoWrapperRenderer": [
            "primaryRenderer": renderer("second", "Second"), "counterpart": [["counterpartRenderer": renderer("video", "Music Video")]]]]
        let panel: [String: Any] = ["contents": [renderer("first", "First"), wrapped, renderer("first", "Duplicate"),
            ["playlistPanelVideoRenderer": ["videoId": "blocked", "unplayableText": [:]]]],
            "continuations": [["nextRadioContinuationData": ["continuation": "token"]]]]
        for key in ["playlistPanelRenderer", "playlistPanelContinuation"] {
            let page = try YouTubeMusicSearchClient.parseRadioPage([key: panel])
            XCTAssertEqual(page.songs.map(\.id), ["first", "second"])
            XCTAssertEqual(page.songs.map(\.artist), ["Artist", "Artist"])
            XCTAssertEqual(page.continuation, "token")
        }
        XCTAssertThrowsError(try YouTubeMusicSearchClient.parseRadioPage(["error": "bad response"]))
    }

    func testBufferDeduplicatesAndExcludesAcrossPages() {
        let a = song(track(0), id: "original")
        let duplicate = song(track(0), id: "different-video")
        let b = song(track(1), id: "disliked")
        let c = song(track(2), id: "keep")
        var buffer = SongRadioBuffer()
        buffer.markSeen(a)
        buffer.append(SongRadioPage(songs: [a, duplicate, b, c, c], continuation: "next"), excluding: [b.radioIdentity])
        XCTAssertEqual(buffer.pending.map(\.id), [c.id])
        buffer.removeFirst()
        buffer.append(SongRadioPage(songs: [c], continuation: nil), excluding: [])
        XCTAssertTrue(buffer.pending.isEmpty)
    }

    func testIdentityReusesVideoIDAndMetadataWithoutMatchingOtherArtists() {
        var exact = track(0)
        exact.streamURL = URL(string: "https://aria.test/api/stream/Old%20Name%20[abcdefghijk].mp3")
        XCTAssertEqual(exact.youtubeVideoID, "abcdefghijk")
        let renamed = YouTubeMusicSongResult(id: "abcdefghijk", title: "Renamed", artist: "Other", artworkURL: nil)
        XCTAssertEqual(renamed.downloadedTrack(in: [exact])?.id, exact.id)
        let topic = YouTubeMusicSongResult(id: "another-id", title: "SONG 0", artist: "Artist - Topic", artworkURL: nil)
        XCTAssertEqual(topic.downloadedTrack(in: [exact])?.id, exact.id)
        let otherArtist = YouTubeMusicSongResult(id: "another-id", title: exact.title, artist: "Other", artworkURL: nil)
        XCTAssertNil(otherArtist.downloadedTrack(in: [exact]))
    }
}
