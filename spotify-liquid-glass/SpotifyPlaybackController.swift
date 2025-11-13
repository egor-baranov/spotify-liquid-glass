import Foundation
import Combine
import UIKit
#if canImport(SpotifyiOS)
import SpotifyiOS
#endif

@MainActor
final class SpotifyPlaybackController: NSObject, ObservableObject {
    static let shared = SpotifyPlaybackController()

    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var playbackPosition: Double = 0
    @Published private(set) var trackDuration: Double = 0
    @Published private(set) var currentArtwork: UIImage?

#if canImport(SpotifyiOS)
    private let configuration: SPTConfiguration
    private let appRemote: SPTAppRemote
    private var pendingURI: String?
    private var lastAccessToken: String?
    private var isConnecting = false
    private var awaitingAuthorization = false
    private var currentTrackURI: String?

    private override init() {
        let redirectURL = URL(string: SpotifyAuthConfiguration.redirectURI)!
        configuration = SPTConfiguration(clientID: SpotifyAuthConfiguration.clientID, redirectURL: redirectURL)
        configuration.playURI = nil
        appRemote = SPTAppRemote(configuration: configuration, logLevel: .error)
        super.init()
        appRemote.delegate = self
    }
#else
    private override init() {}
#endif

    func playIfPossible(song: Song, accessToken: String?) async -> Bool {
#if canImport(SpotifyiOS)
        guard let uri = song.spotifyURI,
              let token = accessToken else {
            debugLog("Remote playback skipped for \(song.title): missing URI or user token.")
            return false
        }

        if let spotifyURL = URL(string: "spotify://"), !UIApplication.shared.canOpenURL(spotifyURL) {
            debugLog("Spotify app not installed/whitelisted; cannot use App Remote.")
            return false
        }

        pendingURI = uri
        currentSong = song
        isPlaying = true
        playbackPosition = 0
        trackDuration = 0
        currentArtwork = nil
        currentTrackURI = nil
        lastAccessToken = token
        appRemote.connectionParameters.accessToken = token

        if appRemote.isConnected {
            debugLog("App Remote already connected, playing URI \(uri).")
            appRemote.playerAPI?.play(uri, callback: nil)
        } else if awaitingAuthorization {
            debugLog("Awaiting Spotify authorization callback before connecting.")
        } else if isConnecting {
            debugLog("Spotify App Remote connection already in progress.")
        } else {
            isConnecting = true
            debugLog("Connecting to Spotify App Remote…")
            appRemote.connect()
        }

        return true
#else
        return false
#endif
    }

    func disconnect() {
#if canImport(SpotifyiOS)
        if appRemote.isConnected {
            debugLog("Disconnecting App Remote session.")
            appRemote.disconnect()
        }
        isConnecting = false
        awaitingAuthorization = false
#endif
        currentSong = nil
        pendingURI = nil
        isPlaying = false
        playbackPosition = 0
        trackDuration = 0
        currentArtwork = nil
        currentTrackURI = nil
    }

    func togglePlayPause() {
#if canImport(SpotifyiOS)
        guard appRemote.isConnected else { return }
        if isPlaying {
            debugLog("Sending pause to App Remote.")
            appRemote.playerAPI?.pause(nil)
        } else {
            debugLog("Sending resume to App Remote.")
            appRemote.playerAPI?.resume(nil)
        }
#endif
    }

    func skipToNext() {
#if canImport(SpotifyiOS)
        guard appRemote.isConnected else { return }
        debugLog("Skipping to next track via App Remote.")
        appRemote.playerAPI?.skip(toNext: nil)
#endif
    }

    func skipToPrevious() {
#if canImport(SpotifyiOS)
        guard appRemote.isConnected else { return }
        debugLog("Skipping to previous track via App Remote.")
        appRemote.playerAPI?.skip(toPrevious: nil)
#endif
    }

    func seek(toProgress progress: Double) {
#if canImport(SpotifyiOS)
        guard appRemote.isConnected,
              trackDuration > 0 else { return }
        let clamped = min(max(progress, 0), 1)
        let targetSeconds = clamped * trackDuration
        playbackPosition = targetSeconds
        let milliseconds = Int(targetSeconds * 1000)
        debugLog("Seeking App Remote playback to \(milliseconds)ms.")
        appRemote.playerAPI?.seek(toPosition: milliseconds, callback: nil)
#endif
    }

    func reconnectIfNeeded() {
#if canImport(SpotifyiOS)
        guard currentSong != nil,
              !appRemote.isConnected,
              let token = lastAccessToken else { return }
        debugLog("Attempting App Remote reconnect…")
        appRemote.connectionParameters.accessToken = token
        appRemote.connect()
#endif
    }

    func handleDidEnterBackground() {
#if canImport(SpotifyiOS)
        if awaitingAuthorization {
            debugLog("Background entry during Spotify authorization handoff; preserving state.")
            return
        }
        guard !isConnecting else {
            debugLog("Skipping App Remote disconnect; handshake in progress.")
            return
        }
        if appRemote.isConnected {
            debugLog("App entering background, disconnecting App Remote.")
            appRemote.disconnect()
        }
        awaitingAuthorization = false
        isConnecting = false
#endif
        pendingURI = nil
        currentSong = nil
        isPlaying = false
        playbackPosition = 0
        trackDuration = 0
        currentArtwork = nil
        currentTrackURI = nil
    }

    func handleIncomingURL(_ url: URL) -> Bool {
#if canImport(SpotifyiOS)
        guard let parameters = appRemote.authorizationParameters(from: url) else { return false }
        if let token = parameters[SPTAppRemoteAccessTokenKey] {
            debugLog("Received App Remote token from Spotify callback.")
            lastAccessToken = token
            appRemote.connectionParameters.accessToken = token
            awaitingAuthorization = false
            reconnectAfterAuthorization()
            return true
        } else if let errorDescription = parameters[SPTAppRemoteErrorDescriptionKey] {
            debugLog("App Remote authorization error: \(errorDescription)")
            awaitingAuthorization = false
        }
#endif
        return false
    }

    private func reconnectAfterAuthorization() {
#if canImport(SpotifyiOS)
        guard !appRemote.isConnected else { return }
        isConnecting = true
        debugLog("Connecting to Spotify App Remote after authorization callback…")
        appRemote.connect()
#endif
    }

    private func launchSpotifyForAuthorization(using uri: String) {
#if canImport(SpotifyiOS)
        guard !awaitingAuthorization else {
            debugLog("Already awaiting Spotify authorization handoff.")
            return
        }
        awaitingAuthorization = true
        DispatchQueue.main.async {
            self.appRemote.authorizeAndPlayURI(uri)
        }
#endif
    }

    private func fetchArtworkIfNeeded(for track: SPTAppRemoteTrack) {
#if canImport(SpotifyiOS)
        guard let imageAPI = appRemote.imageAPI else { return }
        let identifier = track.uri ?? track.name
        if currentTrackURI == identifier, currentArtwork != nil {
            return
        }
        currentTrackURI = identifier
        imageAPI.fetchImage(forItem: track, with: CGSize(width: 640, height: 640)) { [weak self] image, error in
            guard let self = self else { return }
            if let uiImage = image as? UIImage {
                DispatchQueue.main.async {
                    self.currentArtwork = uiImage
                }
            } else if let error {
                debugLog("App Remote artwork fetch failed: \(error.localizedDescription)")
            }
        }
#endif
    }
}

#if canImport(SpotifyiOS)
extension SpotifyPlaybackController: SPTAppRemoteDelegate, SPTAppRemotePlayerStateDelegate {
    func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        isConnecting = false
        awaitingAuthorization = false
        appRemote.playerAPI?.delegate = self
        if let uri = pendingURI {
            debugLog("App Remote connected, playing pending URI \(uri).")
            appRemote.playerAPI?.play(uri, callback: nil)
        } else {
            appRemote.playerAPI?.getPlayerState { [weak self] _, state in
                guard
                    let state = state as? SPTAppRemotePlayerState,
                    let self = self
                else { return }
                debugLog("App Remote connected, pulled current player state.")
                let positionSeconds = Double(state.playbackPosition) / 1000
                self.playbackPosition = positionSeconds
                self.trackDuration = Double(state.track.duration) / 1000
                self.updateSong(from: state.track, isPaused: state.isPaused, position: positionSeconds)
            }
        }
    }

    func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        debugLog("App Remote disconnected: \(error?.localizedDescription ?? "nil").")
        isConnecting = false
        awaitingAuthorization = false
        isPlaying = false
        pendingURI = nil
        currentSong = nil
        playbackPosition = 0
        trackDuration = 0
        currentArtwork = nil
        currentTrackURI = nil
    }

    func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        debugLog("App Remote connection failed: \(error?.localizedDescription ?? "nil").")
        isConnecting = false
        isPlaying = false
        if appRemote.isConnected == false, let uri = pendingURI {
            debugLog("Attempting Spotify handoff for App Remote authorization.")
            launchSpotifyForAuthorization(using: uri)
            return
        }
        pendingURI = nil
        currentSong = nil
        playbackPosition = 0
        trackDuration = 0
        currentArtwork = nil
        currentTrackURI = nil
    }

    func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        isPlaying = !playerState.isPaused
        debugLog("App Remote state change: track=\(playerState.track.name) paused=\(playerState.isPaused)")
        let positionSeconds = Double(playerState.playbackPosition) / 1000
        playbackPosition = positionSeconds
        trackDuration = Double(playerState.track.duration) / 1000
        updateSong(from: playerState.track, isPaused: playerState.isPaused, position: positionSeconds)
    }

    private func updateSong(from track: SPTAppRemoteTrack, isPaused: Bool, position: Double? = nil) {
        let gradientSeed = track.uri ?? track.name
        let colors = ColorPalette.gradient(for: gradientSeed)
        let durationText = Int(track.duration / 1000).asTimeString()
        debugLog("Now playing via App Remote: \(track.name) by \(track.artist.name ?? "unknown")")
        currentSong = Song(
            id: track.uri ?? UUID().uuidString,
            title: track.name,
            artist: track.artist.name ?? "Spotify",
            tagline: track.album.name ?? "",
            duration: durationText,
            colors: colors,
            artworkURL: nil,
            audioPreviewURL: nil,
            spotifyURI: track.uri
        )
        isPlaying = !isPaused
        trackDuration = Double(track.duration) / 1000
        if let position {
            playbackPosition = position
        }
        fetchArtworkIfNeeded(for: track)
    }
}
#endif
