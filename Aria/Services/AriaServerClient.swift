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

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AriaServerError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            throw AriaServerError.badStatus(httpResponse.statusCode)
        }

        let tracks = try JSONDecoder().decode([Track].self, from: data)
        guard !tracks.isEmpty else {
            throw AriaServerError.emptyCatalog
        }

        return tracks
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

enum AriaServerError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case emptyCatalog
    case unreachable([String])

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The song server returned an invalid response."
        case .badStatus(let statusCode):
            "The song server returned HTTP \(statusCode)."
        case .emptyCatalog:
            "The song server did not find any songs."
        case .unreachable(let failures):
            "Tried \(failures.joined(separator: "\n"))"
        }
    }
}
