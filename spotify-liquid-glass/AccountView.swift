import SwiftUI

struct AccountView: View {
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Sign in to Spotify")
                    .font(.title.bold())

                Text("Connect your Spotify account to sync playlists, liked songs and more.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    // TODO: integrate real Spotify auth
                } label: {
                    HStack {
                        Image(systemName: "music.note")
                        Text("Continue with Spotify")
                            .fontWeight(.semibold)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.green, in: Capsule())
                    .foregroundStyle(.black)
                }

                Button("Maybe later") {
                    onDismiss()
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
