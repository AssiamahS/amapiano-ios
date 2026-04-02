import Foundation

class APIClient {
    static let shared = APIClient()

    var baseURL: String {
        get { UserDefaults.standard.string(forKey: "serverURL") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "serverURL") }
    }

    var isConfigured: Bool { !baseURL.isEmpty }

    private let localSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private func url(_ path: String) -> URL? {
        URL(string: "\(baseURL)\(path)")
    }

    func fetchTracks(query: String? = nil, genre: String? = nil) async throws -> [Track] {
        var components = URLComponents(string: "\(baseURL)/api/tracks")!
        var items: [URLQueryItem] = []
        if let q = query, !q.isEmpty { items.append(.init(name: "q", value: q)) }
        if let g = genre, !g.isEmpty { items.append(.init(name: "genre", value: g)) }
        if !items.isEmpty { components.queryItems = items }

        let (data, _) = try await localSession.data(from: components.url!)
        return try JSONDecoder().decode(TracksResponse.self, from: data).tracks
    }

    func fetchPlaylists() async throws -> [Playlist] {
        guard let url = url("/api/playlists") else { return [] }
        let (data, _) = try await localSession.data(from: url)
        return try JSONDecoder().decode(PlaylistsResponse.self, from: data).playlists
    }

    func fetchPlaylist(id: String) async throws -> PlaylistDetail {
        let (data, _) = try await localSession.data(from: url("/api/playlists/\(id)")!)
        return try JSONDecoder().decode(PlaylistDetail.self, from: data)
    }

    func fetchTags() async throws -> TagsResponse {
        let (data, _) = try await localSession.data(from: url("/api/tags")!)
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
        _ = try await localSession.data(for: req)
    }

    func addTrackToPlaylist(playlistId: String, trackId: String) async throws {
        guard let url = url("/api/playlists/\(playlistId)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["add_track": trackId])
        _ = try await localSession.data(for: req)
    }

    func spotifyGenreLookup(title: String, artist: String) async throws -> String? {
        guard let url = url("/api/spotify-genre") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["title": title, "artist": artist])
        let (data, _) = try await localSession.data(for: req)
        let result = try JSONDecoder().decode([String: String?].self, from: data)
        return result["genre"] ?? nil
    }

    func createPlaylist(name: String, trackIds: [String] = []) async throws -> String {
        guard let url = url("/api/playlists") else { return "" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["name": name, "track_ids": trackIds]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await localSession.data(for: req)
        if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return result["id"] as? String ?? ""
        }
        return ""
    }

    func deletePlaylist(id: String) async throws {
        guard let url = url("/api/playlists/\(id)") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        _ = try await localSession.data(for: req)
    }

    func exportToSerato(playlistId: String) async throws -> String {
        guard let url = url("/api/serato/export") else { return "" }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["playlist_id": playlistId])
        let (data, _) = try await localSession.data(for: req)
        if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return result["path"] as? String ?? ""
        }
        return ""
    }

    struct SeratoCrate: Codable, Identifiable {
        var id: String { name }
        let name: String
        let path: String
        let count: Int
        let source: String
    }

    struct SeratoCratesResponse: Codable {
        let crates: [SeratoCrate]
    }

    func fetchSeratoCrates() async throws -> [SeratoCrate] {
        guard let url = url("/api/serato/crates") else { return [] }
        let (data, _) = try await localSession.data(from: url)
        return try JSONDecoder().decode(SeratoCratesResponse.self, from: data).crates
    }

    struct CrateTracksResponse: Codable {
        let name: String
        let tracks: [Track]
    }

    func fetchCrateTracks(name: String) async throws -> [Track] {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = url("/api/serato/crates/\(encoded)/tracks") else { return [] }
        let (data, _) = try await localSession.data(from: url)
        return try JSONDecoder().decode(CrateTracksResponse.self, from: data).tracks
    }

    func addToCrate(name: String, trackId: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = url("/api/serato/crates/\(encoded)/add") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["track_id": trackId])
        _ = try await localSession.data(for: req)
    }

    func removeFromCrate(name: String, trackId: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = url("/api/serato/crates/\(encoded)/remove") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["track_id": trackId])
        _ = try await localSession.data(for: req)
    }

    func reorderCrate(name: String, trackIds: [String]) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = url("/api/serato/crates/\(encoded)/reorder") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["track_ids": trackIds])
        _ = try await localSession.data(for: req)
    }

    func renameCrate(name: String, newName: String) async throws {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = url("/api/serato/crates/\(encoded)/rename") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["name": newName])
        _ = try await localSession.data(for: req)
    }

    func createCrate(name: String) async throws {
        guard let url = url("/api/serato/crates/create") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["name": name])
        _ = try await localSession.data(for: req)
    }

    func importSeratoCrate(path: String, name: String) async throws {
        guard let url = url("/api/serato/crates/import") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["path": path, "name": name])
        _ = try await localSession.data(for: req)
    }

    // MARK: - Downloads

    struct Download: Codable, Identifiable {
        let id: String
        let status: String
        let url: String
        let name: String
        let newTracks: Int?
        let error: String?
        let progress: String?

        enum CodingKeys: String, CodingKey {
            case id, status, url, name, error, progress
            case newTracks = "new_tracks"
        }
    }

    struct DownloadsResponse: Codable {
        let downloads: [Download]
    }

    func resolveName(url: String) async throws -> String {
        guard let apiURL = self.url("/api/resolve-name") else { return "" }
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["url": url])
        let (data, _) = try await localSession.data(for: req)
        if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return result["name"] as? String ?? ""
        }
        return ""
    }

    func startDownload(url: String, name: String) async throws -> String {
        guard let apiURL = self.url("/api/download") else { return "" }
        var req = URLRequest(url: apiURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["url": url, "name": name])
        let (data, _) = try await localSession.data(for: req)
        if let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return result["id"] as? String ?? ""
        }
        return ""
    }

    func fetchDownloads() async throws -> [Download] {
        guard let url = url("/api/downloads") else { return [] }
        let (data, _) = try await localSession.data(from: url)
        return try JSONDecoder().decode(DownloadsResponse.self, from: data).downloads
    }

    func fetchDownloadStatus(id: String) async throws -> Download {
        let (data, _) = try await localSession.data(from: url("/api/download/\(id)")!)
        return try JSONDecoder().decode(Download.self, from: data)
    }

    func testConnection(url: String, timeout: TimeInterval = 5) async -> Bool {
        guard let testURL = URL(string: "\(url)/api/stats") else { return false }
        do {
            var req = URLRequest(url: testURL)
            req.timeoutInterval = timeout
            let (_, response) = try await localSession.data(for: req)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            print("[APIClient] testConnection failed for \(url): \(error.localizedDescription)")
            return false
        }
    }
}
