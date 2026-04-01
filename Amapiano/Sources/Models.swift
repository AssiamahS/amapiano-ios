import Foundation

struct Track: Codable, Identifiable, Equatable {
    let id: String
    let path: String
    let title: String
    let artist: String
    let genre: String
    let album: String
    let duration: Double
    let cover: String?
    let customTags: [String]?
    let flags: [String]?

    enum CodingKeys: String, CodingKey {
        case id, path, title, artist, genre, album, duration, cover, flags
        case customTags = "custom_tags"
    }

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
}

struct TracksResponse: Codable {
    let tracks: [Track]
    let total: Int
}

struct Playlist: Codable, Identifiable {
    let id: String
    let name: String
    let count: Int?
    let tracks: [Track]?
}

struct PlaylistsResponse: Codable {
    let playlists: [Playlist]
}

struct PlaylistDetail: Codable {
    let id: String
    let name: String
    let tracks: [Track]
}

struct TagsResponse: Codable {
    let genres: [String]
    let customTags: [String]

    enum CodingKeys: String, CodingKey {
        case genres
        case customTags = "custom_tags"
    }
}
