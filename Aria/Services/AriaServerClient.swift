import Foundation

struct AriaServerClient {
    var baseURL: URL

    init(baseURL: URL = URL(string: "http://100.93.250.104:8000")!) {
        self.baseURL = baseURL
    }

    func fetchTracks() async throws -> [Track] {
        let url = baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("tracks")

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8

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
}

enum AriaServerError: LocalizedError {
    case invalidResponse
    case badStatus(Int)
    case emptyCatalog

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The song server returned an invalid response."
        case .badStatus(let statusCode):
            "The song server returned HTTP \(statusCode)."
        case .emptyCatalog:
            "The song server did not find any songs."
        }
    }
}
