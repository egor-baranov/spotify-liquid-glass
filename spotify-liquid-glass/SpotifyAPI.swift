import Foundation
import SwiftUI
import Combine

enum SpotifyAPIError: Error, LocalizedError {
    case missingCredentials
    case invalidResponse
    case decodingFailed
    case httpError(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Missing Spotify API credentials."
        case .invalidResponse:
            return "Received an unexpected response from Spotify."
        case .decodingFailed:
            return "Failed to decode Spotify response."
        case let .httpError(status, message):
            return "Spotify API returned HTTP \(status): \(message)"
        }
    }
}

struct SpotifyAuthConfiguration {
    static let clientID: String = "b39c40971d754da5b8104cfc3219470b"
    static let clientSecret: String = "f369d980c86f433aa8284e3f1fbf9a7f"
    static let redirectURI: String = "spotify-liquid-glass://auth"
}

struct SpotifyAccessToken: Decodable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let expiration: Date

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try container.decode(String.self, forKey: .accessToken)
        tokenType = try container.decode(String.self, forKey: .tokenType)
        expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        expiration = Date().addingTimeInterval(TimeInterval(expiresIn))
    }
}

struct TokenExchangeResponse: Decodable {
    let access_token: String
    let token_type: String
    let expires_in: Int
    let refresh_token: String?
}

final class SpotifyAuthManager {
    static let shared = SpotifyAuthManager()
    private var cachedToken: SpotifyAccessToken?

    private init() {}

    func validAccessToken() async throws -> String {
        if let token = cachedToken, token.expiration > Date().addingTimeInterval(60) {
            return token.accessToken
        }
        return try await requestAccessToken()
    }

    private func requestAccessToken() async throws -> String {
        guard !SpotifyAuthConfiguration.clientID.isEmpty,
              !SpotifyAuthConfiguration.clientSecret.isEmpty else {
            throw SpotifyAPIError.missingCredentials
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let credentials = "\(SpotifyAuthConfiguration.clientID):\(SpotifyAuthConfiguration.clientSecret)"
        guard let data = credentials.data(using: .utf8) else { throw SpotifyAPIError.missingCredentials }
        request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAPIError.invalidResponse
        }

        let token = try JSONDecoder().decode(SpotifyAccessToken.self, from: responseData)
        cachedToken = token
        return token.accessToken
    }
}

final class SpotifyAPIClient {
    static let shared = SpotifyAPIClient()
    private let authManager = SpotifyAuthManager.shared

    private init() {}

    func fetchFeaturedPlaylists(limit: Int = 12) async throws -> [SpotifyRemotePlaylist] {
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
        return try JSONDecoder().decode(SpotifyFeaturedPlaylistsResponse.self, from: data).playlists.items
    }

    func fetchRecommendations(limit: Int = 6) async throws -> [SpotifyTrack] {
        let token = try await authManager.validAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/recommendations")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "seed_genres", value: "pop")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAPIError.invalidResponse
        }
        return try JSONDecoder().decode(SpotifyRecommendationResponse.self, from: data).tracks
    }

    func fetchNewReleases(limit: Int = 3) async throws -> [SpotifyAlbum] {
        let token = try await authManager.validAccessToken()
        var components = URLComponents(string: "https://api.spotify.com/v1/browse/new-releases")!
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
        return try JSONDecoder().decode(SpotifyNewReleasesResponse.self, from: data).albums.items
    }

    func fetchUserPlaylists(accessToken: String, limit: Int = 50) async throws -> [SpotifyRemotePlaylist] {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/playlists")!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAPIError.invalidResponse
        }
        return try JSONDecoder().decode(SpotifyPlaylistContainer.self, from: data).items
    }

    func fetchCurrentUserProfile(accessToken: String) async throws -> SpotifyUserProfile {
        var request = URLRequest(url: URL(string: "https://api.spotify.com/v1/me")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw SpotifyAPIError.invalidResponse
        }
        return try JSONDecoder().decode(SpotifyUserProfile.self, from: data)
    }

    func fetchPlaylistTracks(id: String, accessToken: String? = nil, limit: Int = 100) async throws -> [SpotifyTrack] {
        var components = URLComponents(string: "https://api.spotify.com/v1/playlists/\(id)/tracks")!
        components.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        var request = URLRequest(url: components.url!)
        let bearer = try await token(for: accessToken)
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SpotifyAPIError.httpError(status: http.statusCode, message: message)
        }
        do {
            let decoded = try JSONDecoder().decode(SpotifyPlaylistTracksResponse.self, from: data)
            return decoded.items.compactMap { $0.track }
        } catch {
            throw SpotifyAPIError.decodingFailed
        }
    }

    private func token(for override: String?) async throws -> String {
        if let override {
            return override
        }
        return try await authManager.validAccessToken()
    }

    func fetchLikedTracks(accessToken: String, limit: Int = 50, offset: Int = 0) async throws -> SpotifySavedTracksResponse {
        var components = URLComponents(string: "https://api.spotify.com/v1/me/tracks")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset))
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SpotifyAPIError.invalidResponse
        }
        guard http.statusCode == 200 else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SpotifyAPIError.httpError(status: http.statusCode, message: message)
        }
        do {
            return try JSONDecoder().decode(SpotifySavedTracksResponse.self, from: data)
        } catch {
            throw SpotifyAPIError.decodingFailed
        }
    }
}

struct SpotifyFeaturedPlaylistsResponse: Decodable {
    let playlists: SpotifyPlaylistContainer
}

struct SpotifyPlaylistContainer: Decodable {
    let items: [SpotifyRemotePlaylist]
}

struct SpotifyImage: Decodable {
    let url: String?
    let width: Int?
    let height: Int?
}

struct SpotifyRemotePlaylist: Decodable {
    struct Owner: Decodable { let display_name: String? }
    let id: String
    let name: String
    let description: String?
    let owner: Owner
    let images: [SpotifyImage]?
}

struct SpotifyRecommendationResponse: Decodable {
    let tracks: [SpotifyTrack]
}

struct SpotifyTrack: Decodable {
    struct Artist: Decodable { let name: String }
    let id: String
    let uri: String?
    let name: String
    let artists: [Artist]
    let album: SpotifyAlbumSummary
    let duration_ms: Int
    let preview_url: String?
}

struct SpotifyAlbumSummary: Decodable {
    let name: String
    let images: [SpotifyImage]?
}

struct SpotifyNewReleasesResponse: Decodable {
    let albums: SpotifyAlbumContainer
}

struct SpotifyAlbumContainer: Decodable {
    let items: [SpotifyAlbum]
}

struct SpotifyAlbum: Decodable {
    struct Artist: Decodable { let name: String }
    let name: String
    let artists: [Artist]
    let images: [SpotifyImage]?
}

struct SpotifyPlaylistTracksResponse: Decodable {
    struct Item: Decodable {
        let track: SpotifyTrack?
    }
    let items: [Item]
}

struct SpotifySavedTracksResponse: Decodable {
    struct Item: Decodable {
        let track: SpotifyTrack?
    }
    let items: [Item]
    let total: Int
    let limit: Int
    let next: String?
    let offset: Int
}

struct SpotifyUserProfile: Decodable {
    let display_name: String?
    let images: [SpotifyUserImage]?
}

struct SpotifyUserImage: Decodable {
    let url: String?
}

@MainActor
final class SpotifyDataProvider: ObservableObject {
    @Published var heroSong: Song?
    @Published var dailyMixes: [Playlist] = []
    @Published var quickPicks: [Playlist] = []
    @Published var trendingSongs: [Song] = []
    @Published var releaseHighlight: Song?
    @Published var userPlaylists: [Playlist] = []
    @Published var likedSongs: [Song] = []
    @Published var likedSongsTotal: Int = 0

    private let api = SpotifyAPIClient.shared
    private var likedSongsNextOffset: Int?
    private var isLoadingLikedSongs = false

    init() {
        Task { await refreshHome() }
    }

    func refreshHome() async {
        do {
            async let playlistsRequest = api.fetchFeaturedPlaylists(limit: 12)
            async let recommendationsRequest = api.fetchRecommendations(limit: 6)
            async let releasesRequest = api.fetchNewReleases(limit: 3)

            let (remotePlaylists, recommendedTracks, newReleases) = try await (
                playlistsRequest, recommendationsRequest, releasesRequest
            )

            let playlists = remotePlaylists.map { $0.asPlaylist }
            dailyMixes = playlists
            if playlists.count > 1 {
                quickPicks = Array(playlists.dropFirst()).shuffled().prefix(6).map { $0 }
            } else {
                quickPicks = playlists
            }

            let recommendedSongs = recommendedTracks.map { $0.asSong }
            trendingSongs = recommendedSongs
            heroSong = recommendedSongs.first ?? newReleases.first?.asSong ?? DemoData.heroSong
            releaseHighlight = newReleases.first?.asSong ?? heroSong
        } catch {
            dailyMixes = DemoData.dailyMixes
            quickPicks = DemoData.quickPicks
            trendingSongs = DemoData.trendingSongs
            heroSong = DemoData.heroSong
            releaseHighlight = DemoData.heroSong
        }
    }

    func refreshUserContent(accessToken: String?) async {
        guard let token = accessToken else {
            userPlaylists = []
            likedSongs = []
            likedSongsTotal = 0
            likedSongsNextOffset = nil
            return
        }

        await fetchUserPlaylists(token: token)
        await loadLikedSongs(token: token, reset: true)
    }

    private func fetchUserPlaylists(token: String) async {
        do {
            let remote = try await api.fetchUserPlaylists(accessToken: token, limit: 50)
            userPlaylists = remote.map { $0.asPlaylist }
        } catch {
            userPlaylists = []
        }
    }

    func loadLikedSongs(token: String, reset: Bool) async {
        if isLoadingLikedSongs { return }
        if !reset, likedSongsNextOffset == nil { return }

        isLoadingLikedSongs = true
        defer { isLoadingLikedSongs = false }

        let offset = reset ? 0 : (likedSongsNextOffset ?? 0)

        do {
            let response = try await api.fetchLikedTracks(accessToken: token, limit: 50, offset: offset)
            let songs = response.items.compactMap { $0.track?.asSong }

            if reset {
                likedSongs = songs
            } else {
                let existingIDs = Set(likedSongs.map(\.id))
                let newSongs = songs.filter { !existingIDs.contains($0.id) }
                likedSongs.append(contentsOf: newSongs)
            }

            likedSongsTotal = response.total
            if response.next != nil {
                likedSongsNextOffset = response.offset + response.limit
            } else {
                likedSongsNextOffset = nil
            }
        } catch {
            if reset {
                likedSongs = []
                likedSongsTotal = 0
                likedSongsNextOffset = nil
            }
        }
    }

    func refreshLikedSongs(accessToken: String) async {
        await loadLikedSongs(token: accessToken, reset: true)
    }

    func loadMoreLikedSongs(accessToken: String) async {
        await loadLikedSongs(token: accessToken, reset: false)
    }

    func shouldLoadMoreLikedSongs(currentSongID: String) -> Bool {
        guard let index = likedSongs.firstIndex(where: { $0.id == currentSongID }) else { return false }
        guard likedSongsNextOffset != nil else { return false }
        guard !isLoadingLikedSongs else { return false }
        return index >= max(likedSongs.count - 5, 0)
    }
}

private extension SpotifyRemotePlaylist {
    var asPlaylist: Playlist {
        Playlist(
            spotifyID: id,
            title: name,
            subtitle: owner.display_name ?? "Spotify",
            descriptor: description ?? "Featured playlist",
            colors: ColorPalette.gradient(for: id),
            imageURL: images?.first?.url.flatMap(URL.init(string:))
        )
    }
}

extension SpotifyTrack {
    var asSong: Song {
        Song(
            id: id,
            title: name,
            artist: artists.first?.name ?? "Unknown Artist",
            tagline: album.name,
            duration: duration_ms.formattedTime,
            colors: ColorPalette.gradient(for: name),
            artworkURL: album.images?.first?.url.flatMap(URL.init(string:)),
            audioPreviewURL: preview_url.flatMap(URL.init(string:)),
            spotifyURI: uri
        )
    }
}

extension SpotifyAlbum {
    var asSong: Song {
        Song(
            title: name,
            artist: artists.first?.name ?? "Unknown Artist",
            tagline: "New release",
            duration: "4:00",
            colors: ColorPalette.gradient(for: name),
            artworkURL: images?.first?.url.flatMap(URL.init(string:))
        )
    }
}

private extension Int {
    var formattedTime: String {
        let totalSeconds = self / 1000
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
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

extension Playlist {
    func asLibraryCollection() -> LibraryCollection {
        LibraryCollection(
            title: title,
            subtitle: subtitle,
            meta: descriptor,
            icon: "music.note",
            colors: colors,
            type: .playlists,
            isPinned: false,
            imageURL: imageURL,
            playlist: self
        )
    }
}

// MARK: - User Session

final class SpotifyUserSession: ObservableObject {
    static let shared = SpotifyUserSession()

    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var expiration: Date?
    @Published private(set) var displayName: String?
    @Published private(set) var avatarURL: URL?

    var isLoggedIn: Bool { accessToken != nil }

    private let storage = UserDefaults.standard

    private init() {
        accessToken = storage.string(forKey: "spotify_access_token")
        refreshToken = storage.string(forKey: "spotify_refresh_token")
        expiration = storage.object(forKey: "spotify_token_expiration") as? Date
        displayName = storage.string(forKey: "spotify_display_name")
        if let urlString = storage.string(forKey: "spotify_avatar_url") {
            avatarURL = URL(string: urlString)
        }
    }

    func update(with response: TokenExchangeResponse) {
        accessToken = response.access_token
        refreshToken = response.refresh_token ?? refreshToken
        expiration = Date().addingTimeInterval(TimeInterval(response.expires_in))
        storage.set(accessToken, forKey: "spotify_access_token")
        storage.set(refreshToken, forKey: "spotify_refresh_token")
        storage.set(expiration, forKey: "spotify_token_expiration")
    }

    func updateProfile(_ profile: SpotifyUserProfile) {
        displayName = profile.display_name
        let urlString = profile.images?.first?.url
        avatarURL = urlString.flatMap(URL.init(string:))
        storage.set(displayName, forKey: "spotify_display_name")
        storage.set(urlString, forKey: "spotify_avatar_url")
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        expiration = nil
        storage.removeObject(forKey: "spotify_access_token")
        storage.removeObject(forKey: "spotify_refresh_token")
        storage.removeObject(forKey: "spotify_token_expiration")
        displayName = nil
        avatarURL = nil
        storage.removeObject(forKey: "spotify_display_name")
        storage.removeObject(forKey: "spotify_avatar_url")
    }

    func ensureProfileLoaded() async {
        guard (displayName == nil || avatarURL == nil),
              let token = accessToken else { return }
        do {
            let profile = try await SpotifyAPIClient.shared.fetchCurrentUserProfile(accessToken: token)
            await MainActor.run {
                self.updateProfile(profile)
            }
        } catch {
            // ignore; we'll retry on next login
        }
    }

    func validUserAccessToken() async -> String? {
        if let token = accessToken {
            if let expiration,
               expiration > Date().addingTimeInterval(60) {
                return token
            }
        }

        if let refreshed = await refreshAccessToken() {
            return refreshed
        }

        return accessToken
    }

    private func refreshAccessToken() async -> String? {
        guard let refreshToken = refreshToken else { return nil }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(SpotifyAuthConfiguration.clientID)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            let decoded = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
            await MainActor.run {
                self.update(with: decoded)
            }
            return decoded.access_token
        } catch {
            return nil
        }
    }
}
