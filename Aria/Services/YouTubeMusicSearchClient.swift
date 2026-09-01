import Foundation

enum YouTubeMusicSearchCategory: String, CaseIterable, Identifiable {
    case albums = "Albums"
    case songs = "Songs"
    case playlists = "Playlists"

    var id: String { rawValue }

    var downloadKind: String {
        switch self {
        case .albums: "album"
        case .songs: "song"
        case .playlists: "playlist"
        }
    }
}

struct ArtistSelection: Identifiable, Equatable {
    let name: String

    var id: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }
}

struct YouTubeMusicArtistResult: Identifiable, Equatable {
    let id: String
    let name: String
    let artworkURL: URL?
}

struct YouTubeMusicAlbumResult: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let year: String
    let artworkURL: URL?

    var downloadLink: String {
        "https://music.youtube.com/browse/\(id)"
    }
}

struct YouTubeMusicSongResult: Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String
    let artworkURL: URL?

    var downloadLink: String {
        "https://music.youtube.com/watch?v=\(id)"
    }
}

struct YouTubeMusicPlaylistResult: Identifiable, Equatable {
    let id: String
    let title: String
    let curator: String
    let artworkURL: URL?

    var downloadLink: String {
        let playlistID = id.hasPrefix("VL") ? String(id.dropFirst(2)) : id
        return "https://music.youtube.com/playlist?list=\(playlistID)"
    }
}

struct YouTubeMusicSearchClient {
    private struct WebConfiguration {
        let apiKey: String
        let clientVersion: String
    }

    private static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
        + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
    private static let consentCookie = "SOCS=CAI; CONSENT=YES+cb.20210328-17-p0.en+FX+917"

    func searchAlbums(query: String, limit: Int = 60) async throws -> [YouTubeMusicAlbumResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }

        let configuration = try await fetchWebConfiguration()
        let initialResponse = try await fetchSearchResponse(
            query: query,
            parameters: nil,
            configuration: configuration
        )

        if let albumParameters = Self.albumSearchParameters(in: initialResponse) {
            let albumResponse = try await fetchSearchResponse(
                query: query,
                parameters: albumParameters,
                configuration: configuration
            )
            return Self.parseAlbums(from: albumResponse, limit: limit)
        }

        return Self.parseAlbums(from: initialResponse, limit: limit)
    }

    func searchSongs(query: String, limit: Int = 60) async throws -> [YouTubeMusicSongResult] {
        let response = try await filteredSearchResponse(query: query, chipTitle: "Songs")
        return Self.parseSongs(from: response, limit: limit)
    }

    func searchPlaylists(query: String, limit: Int = 60) async throws -> [YouTubeMusicPlaylistResult] {
        let response = try await filteredSearchResponse(query: query, chipTitle: "Playlists")
        return Self.parsePlaylists(from: response, limit: limit)
    }

    func searchArtist(named name: String) async throws -> YouTubeMusicArtistResult? {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        let response = try await filteredSearchResponse(query: query, chipTitle: "Artists")
        let artists = Self.parseArtists(from: response)
        let requestedName = Self.normalizedArtistName(query)
        return artists.first { Self.normalizedArtistName($0.name) == requestedName }
            ?? artists.first
    }

    private func filteredSearchResponse(query: String, chipTitle: String) async throws -> Any {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [:] }
        let configuration = try await fetchWebConfiguration()
        let initialResponse = try await fetchSearchResponse(
            query: query,
            parameters: nil,
            configuration: configuration
        )
        guard let parameters = Self.searchParameters(titled: chipTitle, in: initialResponse) else {
            return initialResponse
        }
        return try await fetchSearchResponse(
            query: query,
            parameters: parameters,
            configuration: configuration
        )
    }

    private func fetchWebConfiguration() async throws -> WebConfiguration {
        guard let url = URL(string: "https://music.youtube.com/?cbrd=1") else {
            throw YouTubeMusicSearchError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.consentCookie, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)

        guard
            let html = String(data: data, encoding: .utf8),
            let apiKey = Self.configurationValue(named: "INNERTUBE_API_KEY", in: html),
            let clientVersion = Self.configurationValue(named: "INNERTUBE_CLIENT_VERSION", in: html)
        else {
            throw YouTubeMusicSearchError.configurationUnavailable
        }

        return WebConfiguration(apiKey: apiKey, clientVersion: clientVersion)
    }

    private func fetchSearchResponse(
        query: String,
        parameters: String?,
        configuration: WebConfiguration
    ) async throws -> Any {
        var components = URLComponents(string: "https://music.youtube.com/youtubei/v1/search")
        components?.queryItems = [
            URLQueryItem(name: "prettyPrint", value: "false"),
            URLQueryItem(name: "key", value: configuration.apiKey)
        ]

        guard let url = components?.url else {
            throw YouTubeMusicSearchError.invalidResponse
        }

        var body: [String: Any] = [
            "context": [
                "client": [
                    "clientName": "WEB_REMIX",
                    "clientVersion": configuration.clientVersion,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "query": query
        ]

        if let parameters {
            body["params"] = parameters
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 18
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://music.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(Self.consentCookie, forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validate(response)

        do {
            return try JSONSerialization.jsonObject(with: data)
        } catch {
            throw YouTubeMusicSearchError.invalidResponse
        }
    }

    private static func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw YouTubeMusicSearchError.invalidResponse
        }

        guard 200..<300 ~= response.statusCode else {
            throw YouTubeMusicSearchError.httpStatus(response.statusCode)
        }
    }

    private static func configurationValue(named name: String, in html: String) -> String? {
        let marker = "\"\(name)\":\""
        guard let markerRange = html.range(of: marker) else { return nil }

        let remainder = html[markerRange.upperBound...]
        guard let closingQuote = remainder.firstIndex(of: "\"") else { return nil }
        return String(remainder[..<closingQuote])
    }

    private static func parseAlbums(from response: Any, limit: Int) -> [YouTubeMusicAlbumResult] {
        var parsed: [YouTubeMusicAlbumResult] = []
        collectAlbums(in: response, into: &parsed)

        var seen = Set<String>()
        return parsed
            .filter { seen.insert($0.id).inserted }
            .prefix(max(limit, 0))
            .map { $0 }
    }

    private static func parseArtists(from response: Any) -> [YouTubeMusicArtistResult] {
        var parsed: [YouTubeMusicArtistResult] = []
        collectArtists(in: response, into: &parsed)
        var seen = Set<String>()
        return parsed.filter { seen.insert($0.id).inserted }
    }

    private static func collectArtists(in value: Any, into results: inout [YouTubeMusicArtistResult]) {
        if let dictionary = value as? [String: Any] {
            for key in ["musicResponsiveListItemRenderer", "musicTwoRowItemRenderer", "musicCardShelfRenderer"] {
                if let renderer = dictionary[key] as? [String: Any],
                   let artist = artist(from: renderer) {
                    results.append(artist)
                }
            }
            for child in dictionary.values {
                collectArtists(in: child, into: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectArtists(in: child, into: &results)
            }
        }
    }

    private static func artist(from renderer: [String: Any]) -> YouTubeMusicArtistResult? {
        let columns = renderer["flexColumns"] as? [[String: Any]] ?? []
        let responsiveTitle = columns.first.flatMap {
            ($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
        }
        let titleRuns = runs(from: responsiveTitle ?? renderer["title"])
        let browseID = titleRuns
            .compactMap { $0["navigationEndpoint"] as? [String: Any] }
            .compactMap(artistBrowseID(from:))
            .first
            ?? artistBrowseID(from: renderer["navigationEndpoint"] as? [String: Any])
            ?? artistBrowseID(from: renderer["onTap"] as? [String: Any])

        guard let browseID,
              let name = titleRuns.first?["text"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return YouTubeMusicArtistResult(
            id: browseID,
            name: name,
            artworkURL: largestThumbnailURL(in: renderer)
        )
    }

    private static func albumSearchParameters(in value: Any) -> String? {
        searchParameters(titled: "Albums", in: value)
    }

    private static func searchParameters(titled requestedTitle: String, in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let chip = dictionary["chipCloudChipRenderer"] as? [String: Any] {
                let title = runs(from: chip["text"])
                    .compactMap { $0["text"] as? String }
                    .joined()

                if title.localizedCaseInsensitiveCompare(requestedTitle) == .orderedSame,
                   let navigationEndpoint = chip["navigationEndpoint"] as? [String: Any],
                   let searchEndpoint = navigationEndpoint["searchEndpoint"] as? [String: Any],
                   let parameters = searchEndpoint["params"] as? String {
                    return parameters
                }
            }

            for child in dictionary.values {
                if let parameters = searchParameters(titled: requestedTitle, in: child) {
                    return parameters
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let parameters = searchParameters(titled: requestedTitle, in: child) {
                    return parameters
                }
            }
        }

        return nil
    }

    private static func parseSongs(from response: Any, limit: Int) -> [YouTubeMusicSongResult] {
        var parsed: [YouTubeMusicSongResult] = []
        collectSongs(in: response, into: &parsed)
        var seen = Set<String>()
        return parsed.filter { seen.insert($0.id).inserted }.prefix(max(limit, 0)).map { $0 }
    }

    private static func collectSongs(in value: Any, into results: inout [YouTubeMusicSongResult]) {
        if let dictionary = value as? [String: Any] {
            if let renderer = dictionary["musicResponsiveListItemRenderer"] as? [String: Any],
               let song = song(from: renderer) {
                results.append(song)
            }
            for child in dictionary.values {
                collectSongs(in: child, into: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectSongs(in: child, into: &results)
            }
        }
    }

    private static func song(from renderer: [String: Any]) -> YouTubeMusicSongResult? {
        guard let columns = renderer["flexColumns"] as? [[String: Any]], !columns.isEmpty else {
            return nil
        }
        let titleContainer = (columns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
        let titleRuns = runs(from: titleContainer)
        let metadata = columns.dropFirst().flatMap { column -> [String] in
            let container = (column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
            return runs(from: container).compactMap { $0["text"] as? String }
        }
        let videoID = titleRuns
            .compactMap { $0["navigationEndpoint"] as? [String: Any] }
            .compactMap(videoID(from:))
            .first
            ?? videoID(from: renderer["navigationEndpoint"] as? [String: Any])
        guard let videoID,
              let title = titleRuns.first?["text"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        let artist = metadata.first(where: isMeaningfulCreator) ?? "Unknown Artist"
        return YouTubeMusicSongResult(
            id: videoID,
            title: title,
            artist: artist,
            artworkURL: largestThumbnailURL(in: renderer)
        )
    }

    private static func parsePlaylists(from response: Any, limit: Int) -> [YouTubeMusicPlaylistResult] {
        var parsed: [YouTubeMusicPlaylistResult] = []
        collectPlaylists(in: response, into: &parsed)
        var seen = Set<String>()
        return parsed.filter { seen.insert($0.id).inserted }.prefix(max(limit, 0)).map { $0 }
    }

    private static func collectPlaylists(in value: Any, into results: inout [YouTubeMusicPlaylistResult]) {
        if let dictionary = value as? [String: Any] {
            for key in ["musicResponsiveListItemRenderer", "musicTwoRowItemRenderer"] {
                if let renderer = dictionary[key] as? [String: Any],
                   let playlist = playlist(from: renderer) {
                    results.append(playlist)
                }
            }
            for child in dictionary.values {
                collectPlaylists(in: child, into: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectPlaylists(in: child, into: &results)
            }
        }
    }

    private static func playlist(from renderer: [String: Any]) -> YouTubeMusicPlaylistResult? {
        let columns = renderer["flexColumns"] as? [[String: Any]] ?? []
        let responsiveTitle = columns.first.flatMap {
            ($0["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
        }
        let titleRuns = runs(from: responsiveTitle ?? renderer["title"])
        let metadata = columns.dropFirst().flatMap { column -> [String] in
            let container = (column["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
            return runs(from: container).compactMap { $0["text"] as? String }
        } + runs(from: renderer["subtitle"]).compactMap { $0["text"] as? String }
        let browseID = titleRuns
            .compactMap { $0["navigationEndpoint"] as? [String: Any] }
            .compactMap(playlistBrowseID(from:))
            .first
            ?? playlistBrowseID(from: renderer["navigationEndpoint"] as? [String: Any])
        guard let browseID,
              let title = titleRuns.first?["text"] as? String,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return YouTubeMusicPlaylistResult(
            id: browseID,
            title: title,
            curator: metadata.first(where: isMeaningfulCreator) ?? "YouTube Music",
            artworkURL: largestThumbnailURL(in: renderer)
        )
    }

    private static func videoID(from endpoint: [String: Any]?) -> String? {
        (endpoint?["watchEndpoint"] as? [String: Any])?["videoId"] as? String
    }

    private static func playlistBrowseID(from endpoint: [String: Any]?) -> String? {
        guard let browse = endpoint?["browseEndpoint"] as? [String: Any],
              let browseID = browse["browseId"] as? String else { return nil }
        let supportedConfigs = browse["browseEndpointContextSupportedConfigs"] as? [String: Any]
        let musicConfig = supportedConfigs?["browseEndpointContextMusicConfig"] as? [String: Any]
        let pageType = musicConfig?["pageType"] as? String ?? ""
        guard pageType == "MUSIC_PAGE_TYPE_PLAYLIST" || browseID.hasPrefix("VL") else { return nil }
        return browseID
    }

    private static func isMeaningfulCreator(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "•" else { return false }
        let ignored = ["Song", "Video", "Playlist", "Community playlist", "Episodes for later"]
        if ignored.contains(where: { trimmed.localizedCaseInsensitiveCompare($0) == .orderedSame }) {
            return false
        }
        if trimmed.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil {
            return false
        }
        return true
    }

    private static func collectAlbums(in value: Any, into results: inout [YouTubeMusicAlbumResult]) {
        if let dictionary = value as? [String: Any] {
            if let renderer = dictionary["musicResponsiveListItemRenderer"] as? [String: Any],
               let album = responsiveAlbum(from: renderer) {
                results.append(album)
            }

            if let renderer = dictionary["musicCardShelfRenderer"] as? [String: Any],
               let album = cardAlbum(from: renderer) {
                results.append(album)
            }

            if let renderer = dictionary["musicTwoRowItemRenderer"] as? [String: Any],
               let album = twoRowAlbum(from: renderer) {
                results.append(album)
            }

            for child in dictionary.values {
                collectAlbums(in: child, into: &results)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectAlbums(in: child, into: &results)
            }
        }
    }

    private static func responsiveAlbum(from renderer: [String: Any]) -> YouTubeMusicAlbumResult? {
        guard let columns = renderer["flexColumns"] as? [[String: Any]], columns.count >= 2 else {
            return nil
        }

        let titleContainer = (columns[0]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
        let metadataContainer = (columns[1]["musicResponsiveListItemFlexColumnRenderer"] as? [String: Any])?["text"]
        let titleRuns = runs(from: titleContainer)
        let metadata = runs(from: metadataContainer).compactMap { $0["text"] as? String }

        guard metadata.contains(where: isAlbumLabel) else { return nil }

        let endpoint = titleRuns
            .compactMap { $0["navigationEndpoint"] as? [String: Any] }
            .compactMap(albumBrowseID(from:))
            .first
            ?? albumBrowseID(from: renderer["navigationEndpoint"] as? [String: Any])

        return makeAlbum(
            browseID: endpoint,
            title: titleRuns.first?["text"] as? String,
            metadata: metadata,
            renderer: renderer
        )
    }

    private static func cardAlbum(from renderer: [String: Any]) -> YouTubeMusicAlbumResult? {
        let titleRuns = runs(from: renderer["title"])
        let metadata = runs(from: renderer["subtitle"]).compactMap { $0["text"] as? String }
        guard metadata.contains(where: isAlbumLabel) else { return nil }

        let endpoint = titleRuns
            .compactMap { $0["navigationEndpoint"] as? [String: Any] }
            .compactMap(albumBrowseID(from:))
            .first
            ?? albumBrowseID(from: renderer["onTap"] as? [String: Any])

        return makeAlbum(
            browseID: endpoint,
            title: titleRuns.first?["text"] as? String,
            metadata: metadata,
            renderer: renderer
        )
    }

    private static func twoRowAlbum(from renderer: [String: Any]) -> YouTubeMusicAlbumResult? {
        let titleRuns = runs(from: renderer["title"])
        let metadata = runs(from: renderer["subtitle"]).compactMap { $0["text"] as? String }
        guard metadata.contains(where: isAlbumLabel) else { return nil }

        let endpoint = titleRuns
            .compactMap { $0["navigationEndpoint"] as? [String: Any] }
            .compactMap(albumBrowseID(from:))
            .first
            ?? albumBrowseID(from: renderer["navigationEndpoint"] as? [String: Any])

        return makeAlbum(
            browseID: endpoint,
            title: titleRuns.first?["text"] as? String,
            metadata: metadata,
            renderer: renderer
        )
    }

    private static func makeAlbum(
        browseID: String?,
        title: String?,
        metadata: [String],
        renderer: [String: Any]
    ) -> YouTubeMusicAlbumResult? {
        guard
            let browseID,
            !browseID.isEmpty,
            let title = title?.trimmingCharacters(in: .whitespacesAndNewlines),
            !title.isEmpty
        else {
            return nil
        }

        let meaningfulMetadata = metadata.filter {
            let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed != "•" && !isAlbumLabel(trimmed)
        }
        let year = meaningfulMetadata.first(where: isYear) ?? ""
        guard let artist = meaningfulMetadata.first(where: { !isYear($0) }) else { return nil }

        return YouTubeMusicAlbumResult(
            id: browseID,
            title: title,
            artist: artist,
            year: year,
            artworkURL: largestThumbnailURL(in: renderer)
        )
    }

    private static func runs(from value: Any?) -> [[String: Any]] {
        guard let dictionary = value as? [String: Any] else { return [] }
        return dictionary["runs"] as? [[String: Any]] ?? []
    }

    private static func albumBrowseID(from endpoint: [String: Any]?) -> String? {
        guard
            let browseEndpoint = endpoint?["browseEndpoint"] as? [String: Any],
            let browseID = browseEndpoint["browseId"] as? String,
            let supportedConfigs = browseEndpoint["browseEndpointContextSupportedConfigs"] as? [String: Any],
            let musicConfig = supportedConfigs["browseEndpointContextMusicConfig"] as? [String: Any],
            musicConfig["pageType"] as? String == "MUSIC_PAGE_TYPE_ALBUM"
        else {
            return nil
        }

        return browseID
    }

    private static func artistBrowseID(from endpoint: [String: Any]?) -> String? {
        guard let browse = endpoint?["browseEndpoint"] as? [String: Any],
              let browseID = browse["browseId"] as? String else { return nil }
        let supportedConfigs = browse["browseEndpointContextSupportedConfigs"] as? [String: Any]
        let musicConfig = supportedConfigs?["browseEndpointContextMusicConfig"] as? [String: Any]
        let pageType = musicConfig?["pageType"] as? String ?? ""
        guard pageType == "MUSIC_PAGE_TYPE_ARTIST" || browseID.hasPrefix("UC") else { return nil }
        return browseID
    }

    private static func normalizedArtistName(_ value: String) -> String {
        value
            .replacingOccurrences(of: " - Topic", with: "", options: .caseInsensitive)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func largestThumbnailURL(in value: Any) -> URL? {
        var candidates: [(url: String, area: Int)] = []
        collectThumbnails(in: value, into: &candidates)

        guard let candidate = candidates.max(by: { $0.area < $1.area }) else { return nil }
        let absolute = candidate.url.hasPrefix("//") ? "https:\(candidate.url)" : candidate.url
        return URL(string: absolute)
    }

    private static func collectThumbnails(
        in value: Any,
        into candidates: inout [(url: String, area: Int)]
    ) {
        if let dictionary = value as? [String: Any] {
            if
                let url = dictionary["url"] as? String,
                url.contains("googleusercontent.com") || url.contains("ytimg.com")
            {
                let width = dictionary["width"] as? Int ?? 1
                let height = dictionary["height"] as? Int ?? 1
                candidates.append((url, width * height))
            }

            for child in dictionary.values {
                collectThumbnails(in: child, into: &candidates)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectThumbnails(in: child, into: &candidates)
            }
        }
    }

    private static func isAlbumLabel(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare("Album") == .orderedSame
    }

    private static func isYear(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.count == 4 && value.allSatisfy(\.isNumber)
    }
}

enum YouTubeMusicSearchError: LocalizedError {
    case configurationUnavailable
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .configurationUnavailable:
            "YouTube Music search is temporarily unavailable."
        case .invalidResponse:
            "YouTube Music returned an unexpected response."
        case .httpStatus(let status):
            "YouTube Music search failed with status \(status)."
        }
    }
}
