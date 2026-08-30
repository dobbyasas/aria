import Foundation

struct AriaServerClient {
    var baseURLs: [URL]

    init(baseURLs: [URL] = Self.defaultBaseURLs) {
        self.baseURLs = Self.unique(baseURLs)
    }

    func fetchTracks() async throws -> [Track] {
        var failures: [String] = []

        for baseURL in baseURLs {
            do {
                return try await fetchTracks(from: baseURL)
            } catch {
                failures.append("\(baseURL.absoluteString): \(error.localizedDescription)")
            }
        }

        throw AriaServerError.unreachable(failures)
    }

    private func fetchTracks(from baseURL: URL) async throws -> [Track] {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("tracks")

        let data = try await sendRequest(to: url, method: "GET")
        let tracks = try JSONDecoder().decode([Track].self, from: data)
        guard !tracks.isEmpty else {
            throw AriaServerError.emptyCatalog
        }

        return tracks
    }

    func fetchLyrics(for track: Track) async throws -> TrackLyrics {
        var failures: [String] = []

        for baseURL in baseURLs {
            do {
                let data = try await sendRequest(
                    to: lyricsEndpoint(for: track, baseURL: baseURL),
                    method: "GET"
                )
                return try JSONDecoder().decode(TrackLyrics.self, from: data)
            } catch {
                failures.append("\(baseURL.absoluteString): \(error.localizedDescription)")
            }
        }

        throw AriaServerError.unreachable(failures)
    }

    func fetchPlaylists() async throws -> [AriaServerPlaylist] {
        var failures: [String] = []

        for baseURL in baseURLs {
            do {
                let data = try await sendRequest(to: playlistsEndpoint(baseURL: baseURL), method: "GET")
                return try JSONDecoder().decode([AriaServerPlaylist].self, from: data)
            } catch {
                failures.append("\(baseURL.absoluteString): \(error.localizedDescription)")
            }
        }

        throw AriaServerError.unreachable(failures)
    }

    func savePlaylist(_ playlist: AriaPlaylist) async throws -> AriaServerPlaylist {
        let payload = AriaServerPlaylist(playlist: playlist)
        let body = try JSONEncoder().encode(payload)
        var failures: [String] = []

        for baseURL in baseURLs {
            do {
                let endpoint = playlistsEndpoint(baseURL: baseURL)
                    .appendingPathComponent(playlist.id.uuidString.lowercased())
                let data = try await sendRequest(
                    to: endpoint,
                    method: "PUT",
                    body: body,
                    contentType: "application/json"
                )
                return try JSONDecoder().decode(AriaServerPlaylist.self, from: data)
            } catch {
                failures.append("\(baseURL.absoluteString): \(error.localizedDescription)")
            }
        }

        throw AriaServerError.unreachable(failures)
    }

    func startDownload(_ request: AriaDownloadRequest) async throws -> AriaDownloadJob {
        let body = try JSONEncoder().encode(request)
        var failures: [String] = []

        for baseURL in baseURLs {
            do {
                let data = try await sendRequest(
                    to: downloadsEndpoint(baseURL: baseURL),
                    method: "POST",
                    body: body,
                    contentType: "application/json"
                )
                return try JSONDecoder().decode(AriaDownloadJob.self, from: data)
            } catch {
                failures.append("\(baseURL.absoluteString): \(error.localizedDescription)")
            }
        }

        throw AriaServerError.unreachable(failures)
    }

    func fetchDownloadStatus(id: String) async throws -> AriaDownloadJob {
        var failures: [String] = []

        for baseURL in baseURLs {
            do {
                let data = try await sendRequest(to: downloadStatusEndpoint(id: id, baseURL: baseURL), method: "GET")
                return try JSONDecoder().decode(AriaDownloadJob.self, from: data)
            } catch {
                failures.append("\(baseURL.absoluteString): \(error.localizedDescription)")
            }
        }

        throw AriaServerError.unreachable(failures)
    }

    func deleteAlbum(containing track: Track) async throws -> AlbumDeletionResult {
        var failures: [String] = []
        for baseURL in baseURLs {
            do {
                let endpoint = baseURL
                    .appendingPathComponent("api")
                    .appendingPathComponent("tracks")
                    .appendingPathComponent(track.id.uuidString.lowercased())
                    .appendingPathComponent("album")
                let data = try await sendRequest(to: endpoint, method: "DELETE")
                return try JSONDecoder().decode(AlbumDeletionResult.self, from: data)
            } catch {
                failures.append("\(baseURL.absoluteString): \(error.localizedDescription)")
            }
        }
        throw AriaServerError.unreachable(failures)
    }

    private func sendRequest(
        to url: URL,
        method: String,
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 12
        request.httpBody = body

        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AriaServerError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            if let payload = try? JSONDecoder().decode(ServerErrorPayload.self, from: data),
               !payload.error.isEmpty {
                throw AriaServerError.serverMessage(httpResponse.statusCode, payload.error)
            }
            throw AriaServerError.badStatus(httpResponse.statusCode)
        }

        return data
    }

    private func downloadsEndpoint(baseURL: URL) -> URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("downloads")
    }

    private func playlistsEndpoint(baseURL: URL) -> URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("playlists")
    }

    private func downloadStatusEndpoint(id: String, baseURL: URL) -> URL {
        downloadsEndpoint(baseURL: baseURL).appendingPathComponent(id)
    }

    private func lyricsEndpoint(for track: Track, baseURL: URL) -> URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("tracks")
            .appendingPathComponent(track.id.uuidString.lowercased())
            .appendingPathComponent("lyrics")
    }

    private static let defaultBaseURLs = [
        URL(string: "http://100.93.250.104:8000")!,
        URL(string: "http://192.168.0.16:8000")!,
        URL(string: "http://tofios.local:8000")!
    ]

    private static func unique(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []

        return urls.filter { url in
            let key = url.absoluteString
            guard !seen.contains(key) else { return false }

            seen.insert(key)
            return true
        }
    }
}

struct AriaDownloadRequest: Encodable {
    var link: String
    var album: String
    var albumArtist: String
    var year: String
    var kind: String = "album"
}

struct AriaDownloadJob: Decodable, Identifiable, Equatable {
    var id: String
    var status: String
    var phase: String
    var message: String
    var progress: Double
    var album: String
    var albumArtist: String
    var year: String
    var kind: String?
    var filesStarted: Int
    var newFiles: Int?
    var reusedFiles: Int?
    var playlistID: String?
    var playlistTrackCount: Int?
    var error: String?
    var outputTail: [String]

    var isActive: Bool {
        status == "queued" || status == "running"
    }

    var isFinished: Bool {
        status == "succeeded" || status == "failed"
    }

    var isSuccessful: Bool {
        status == "succeeded"
    }

    var progressFraction: Double {
        min(max(progress, 0), 1)
    }
}

struct AlbumDeletionResult: Decodable {
    var deletedFiles: Int
    var deletedTrackIDs: [String]
    var updatedPlaylists: Int
}

private struct ServerErrorPayload: Decodable {
    let error: String
}

enum AriaServerError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case serverMessage(Int, String)
    case emptyCatalog
    case unreachable([String])

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The song server returned an invalid response."
        case .badStatus(let statusCode):
            "The song server returned HTTP \(statusCode)."
        case .serverMessage(_, let message):
            message
        case .emptyCatalog:
            "The song server did not find any songs."
        case .unreachable(let failures):
            "Tried \(failures.joined(separator: "\n"))"
        }
    }
}
