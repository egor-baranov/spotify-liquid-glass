import SwiftUI
import AuthenticationServices
import UIKit
import Combine

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

    func startLogin(completion: @escaping (Bool) -> Void) {
        guard !isLoading else { return }
        errorMessage = nil
        guard let url = authorizeURL() else {
            errorMessage = "Unable to start authorization."
            return
        }

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

    private func authorizeURL() -> URL? {
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
                    "playlist-read-collaborative"
                ].joined(separator: " ")
            ),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        return components?.url
    }

    private func exchangeCodeForTokens(code: String) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:5001/exchange") else {
            DispatchQueue.main.async { self.errorMessage = "Exchange endpoint missing." }
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code], options: [])

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
