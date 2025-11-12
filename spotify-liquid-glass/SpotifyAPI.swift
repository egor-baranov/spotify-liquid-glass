import Foundation
import SwiftUI
import Combine

enum SpotifyAPIError: Error {
    case missingCredentials
    case invalidResponse
    case decodingFailed
}

struct SpotifyAuthConfiguration {
    let clientID: String = "<#Spotify Client ID#>"
    let clientSecret: String = "<#Spotify Client Secret#>"
}

final class SpotifyAuthManager {
    static let shared = SpotifyAuthManager()
    private let configuration = SpotifyAuthConfiguration()
    private var cachedToken: SpotifyAccessToken?

    private init() {}

    func validAccessToken() async throws -> String {
        if let token = cachedToken, token.expiration > Date().addingTimeInterval(60) {
            return token.value
        }
        return try await requestAccessToken()
    }

    private func requestAccessToken() async throws -> String {
        guard !configuration.clientID.contains("<#"), !configuration.clientSecret.contains("<#") else {
            throw SpotifyAPIError.missingCredentials
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = "\(configuration.clientID):\(configuration.clientSecret)"
        guard let data = credentials.data(using: .utf8) else { throw SpotifyAPIError.missingCredentials }
        request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAPIError.invalidResponse
        }

        let token = try JSONDecoder().decode(SpotifyAccessToken.self, from: responseData)
        cachedToken = token
        return token.value
    }
}

struct SpotifyAccessToken: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int

    var value: String { access_token }
    var expiration: Date { Date().addingTimeInterval(TimeInterval(expires_in)) }
}

final class SpotifyAPIClient {
    static let shared = SpotifyAPIClient()
    private let authManager = SpotifyAuthManager.shared

    func fetchFeaturedPlaylists(limit: Int = 6) async throws -> [SpotifyRemotePlaylist] {
        let token = try await authManager.validAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/browse/featured-playlists")!
        components.queryItems = [
            URLQueryItem(name: "country", value: "US"),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAPIError.invalidResponse
        }
        let decoded = try JSONDecoder().decode(SpotifyFeaturedPlaylistsResponse.self, from: data)
        return decoded.playlists.items
    }
}

struct SpotifyFeaturedPlaylistsResponse: Decodable {
    let playlists: SpotifyPlaylistContainer
}

struct SpotifyPlaylistContainer: Decodable {
    let items: [SpotifyRemotePlaylist]
}

struct SpotifyRemotePlaylist: Decodable {
    struct Owner: Decodable { let display_name: String? }
    let id: String
    let name: String
    let description: String?
    let owner: Owner
}

@MainActor
final class SpotifyDataProvider: ObservableObject {
    @Published var heroSong: Song?
    @Published var dailyMixes: [Playlist] = []
    @Published var quickPicks: [Playlist] = []
    @Published var trendingSongs: [Song] = []

    private let api = SpotifyAPIClient.shared

    init() {
        Task { await refreshHome() }
    }

    func refreshHome() async {
        do {
            let remote = try await api.fetchFeaturedPlaylists(limit: 6)
            let playlists = remote.map { $0.asPlaylist }
            dailyMixes = playlists
            quickPicks = playlists
            heroSong = playlists.first.map { playlist in
                Song(
                    title: playlist.title,
                    artist: playlist.subtitle,
                    tagline: playlist.descriptor,
                    duration: "3:30",
                    colors: playlist.colors
                )
            }
            trendingSongs = DemoData.trendingSongs
        } catch {
            dailyMixes = DemoData.dailyMixes
            quickPicks = DemoData.quickPicks
            trendingSongs = DemoData.trendingSongs
            heroSong = DemoData.heroSong
        }
    }
}

private extension SpotifyRemotePlaylist {
    var asPlaylist: Playlist {
        Playlist(
            title: name,
            subtitle: owner.display_name ?? "Spotify",
            descriptor: description ?? "Featured playlist",
            colors: ColorPalette.gradient(for: id)
        )
    }
}

enum ColorPalette {
    static func gradient(for seed: String) -> [Color] {
        let palettes: [[Color]] = [
            [Color(red: 0.93, green: 0.34, blue: 0.63), Color(red: 0.49, green: 0.22, blue: 0.98)],
            [Color(red: 0.18, green: 0.9, blue: 0.69), Color(red: 0.08, green: 0.58, blue: 0.34)],
            [Color(red: 0.98, green: 0.55, blue: 0.22), Color(red: 0.68, green: 0.2, blue: 0.12)],
            [Color(red: 0.28, green: 0.91, blue: 0.82), Color(red: 0.12, green: 0.55, blue: 0.78)]
        ]
        let index = abs(seed.hashValue) % palettes.count
        return palettes[index]
    }
}
