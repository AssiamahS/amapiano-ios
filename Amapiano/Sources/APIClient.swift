import Foundation

class APIClient {
    static let shared = APIClient()

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }

    var isConfigured: Bool { !baseURL.isEmpty }

    private func url(_ path: String) -> URL? {
        URL(string: "\(baseURL)\(path)")
    }

    func fetchTracks(query: String? = nil, genre: String? = nil) async throws -> [Track] {
        var components = URLComponents(string: "\(baseURL)/api/tracks")!
        var items: [URLQueryItem] = []
        if let q = query, !q.isEmpty { items.append(.init(name: "q", value: q)) }
        if let g = genre, !g.isEmpty { items.append(.init(name: "genre", value: g)) }
        if !items.isEmpty { components.queryItems = items }

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        return try JSONDecoder().decode(TracksResponse.self, from: data).tracks
    }

    func fetchPlaylists() async throws -> [Playlist] {
        guard let url = url("/api/playlists") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(PlaylistsResponse.self, from: data).playlists
    }

    func fetchPlaylist(id: String) async throws -> PlaylistDetail {
        let (data, _) = try await URLSession.shared.data(from: url("/api/playlists/\(id)")!)
        return try JSONDecoder().decode(PlaylistDetail.self, from: data)
    }

    func fetchTags() async throws -> TagsResponse {
        let (data, _) = try await URLSession.shared.data(from: url("/api/tags")!)
        return try JSONDecoder().decode(TagsResponse.self, from: data)
    }

    func audioURL(for track: Track) -> URL? {
        var components = URLComponents(string: "\(baseURL)/api/audio")
        components?.queryItems = [.init(name: "path", value: track.path)]
        return components?.url
    }

    func coverURL(for track: Track) -> URL? {
        guard let cover = track.cover else { return nil }
        return URL(string: "\(baseURL)\(cover)")
    }

    func updateTrack(id: String, title: String? = nil, artist: String? = nil, genre: String? = nil) async throws {
        guard let url = url("/api/tracks/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = [:]
        if let t = title { body["title"] = t }
        if let a = artist { body["artist"] = a }
        if let g = genre { body["genre"] = g }
        req.httpBody = try JSONEncoder().encode(body)
        _ = try await URLSession.shared.data(for: req)
    }

    func spotifyGenreLookup(title: String, artist: String) async throws -> String? {
        guard let url = url("/api/spotify-genre") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["title": title, "artist": artist])
        let (data, _) = try await URLSession.shared.data(for: req)
        let result = try JSONDecoder().decode([String: String?].self, from: data)
        return result["genre"] ?? nil
    }

    func testConnection(url: String) async -> Bool {
        guard let testURL = URL(string: "\(url)/api/stats") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: testURL)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}
