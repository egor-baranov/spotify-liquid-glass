import SwiftUI
import AuthenticationServices
import UIKit
import Combine
import CryptoKit
import Security

struct AccountView: View {
    let onDismiss: () -> Void
    @StateObject private var viewModel = AccountViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if viewModel.isLoggedIn {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)
                        Text("You're signed in")
                            .font(.title3.bold())
                        Text("Your Spotify account is connected.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Sign in to Spotify")
                        .font(.title.bold())
                    Text("Connect your Spotify account to sync playlists, liked songs and more.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)

                    Button {
                        viewModel.startLogin { success in
                            if success { onDismiss() }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "music.note")
                            Text(viewModel.isLoading ? "Connecting…" : "Continue with Spotify")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.green.opacity(viewModel.isLoading ? 0.5 : 1.0), in: Capsule())
                        .foregroundStyle(.black)
                    }
                    .disabled(viewModel.isLoading)
                }

                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button(viewModel.isLoggedIn ? "Sign out" : "Maybe later") {
                    if viewModel.isLoggedIn { viewModel.logout() } else { onDismiss() }
                }
                .padding(.top, 16)
            }
            .padding()
            .navigationTitle("Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onDismiss)
                }
            }
        }
    }
}

final class AccountViewModel: NSObject, ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var isLoggedIn: Bool = SpotifyUserSession.shared.isLoggedIn

    private let userSession = SpotifyUserSession.shared
    private var authSession: ASWebAuthenticationSession?
    private var codeVerifier: String?

    func startLogin(completion: @escaping (Bool) -> Void) {
        guard !isLoading else { return }
        errorMessage = nil
        guard let (url, verifier) = authorizeURL() else {
            errorMessage = "Unable to start authorization."
            return
        }
        codeVerifier = verifier

        isLoading = true
        let callbackScheme = URL(string: SpotifyAuthConfiguration.redirectURI)?.scheme
        authSession = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            guard let self = self else { return }
            DispatchQueue.main.async { self.isLoading = false }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    completion(false)
                }
                return
            }

            guard let callbackURL,
                  let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "code" })?.value else {
                DispatchQueue.main.async {
                    self.errorMessage = "Authorization code missing."
                    completion(false)
                }
                return
            }

            Task {
                let success = await self.exchangeCodeForTokens(code: code)
                DispatchQueue.main.async {
                    self.isLoggedIn = self.userSession.isLoggedIn
                    completion(success)
                }
                if success, let token = self.userSession.accessToken {
                    await self.fetchProfile(accessToken: token)
                }
            }
        }

        authSession?.presentationContextProvider = self
        authSession?.prefersEphemeralWebBrowserSession = true
        authSession?.start()
    }

    func logout() {
        userSession.logout()
        isLoggedIn = false
    }

    private func authorizeURL() -> (URL, String)? {
        let verifier = generateCodeVerifier()
        guard let challenge = codeChallenge(for: verifier) else { return nil }

        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: SpotifyAuthConfiguration.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: SpotifyAuthConfiguration.redirectURI),
            URLQueryItem(
                name: "scope",
                value: [
                    "user-read-email",
                    "user-read-private",
                    "user-library-read",
                    "playlist-read-private",
                    "playlist-read-collaborative",
                    "app-remote-control",
                    "streaming"
                ].joined(separator: " ")
            ),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        guard let url = components?.url else { return nil }
        return (url, verifier)
    }

    private func exchangeCodeForTokens(code: String) async -> Bool {
        guard let verifier = codeVerifier else {
            DispatchQueue.main.async { self.errorMessage = "Missing PKCE verifier." }
            return false
        }

        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = [
            "grant_type=authorization_code",
            "code=\(code)",
            "redirect_uri=\(SpotifyAuthConfiguration.redirectURI)",
            "client_id=\(SpotifyAuthConfiguration.clientID)",
            "code_verifier=\(verifier)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                DispatchQueue.main.async { self.errorMessage = "Token exchange failed." }
                return false
            }
            let decoded = try JSONDecoder().decode(TokenExchangeResponse.self, from: data)
            DispatchQueue.main.async {
                self.userSession.update(with: decoded)
            }
            return true
        } catch {
            DispatchQueue.main.async { self.errorMessage = error.localizedDescription }
            return false
        }
    }

    private func fetchProfile(accessToken: String) async {
        do {
            let profile = try await SpotifyAPIClient.shared.fetchCurrentUserProfile(accessToken: accessToken)
            await MainActor.run {
                self.userSession.updateProfile(profile)
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Failed to load profile info."
            }
        }
    }
}

extension AccountViewModel: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first { $0.isKeyWindow } }
            .first ?? ASPresentationAnchor()
    }
}

// MARK: - PKCE Helpers

private func generateCodeVerifier(length: Int = 64) -> String {
    var bytes = [UInt8](repeating: 0, count: length)
    _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
    let data = Data(bytes)
    return data.base64URLEncodedString()
}

private func codeChallenge(for verifier: String) -> String? {
    guard let data = verifier.data(using: .ascii) else { return nil }
    let hashed = SHA256.hash(data: data)
    return Data(hashed).base64URLEncodedString()
}

private extension Data {
    func base64URLEncodedString() -> String {
        return self.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
