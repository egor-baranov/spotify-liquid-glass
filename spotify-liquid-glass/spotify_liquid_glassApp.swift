//
//  spotify_liquid_glassApp.swift
//  spotify-liquid-glass
//
//  Created by Egor Baranov on 11/11/2025.
//

import SwiftUI
import UIKit

@main
struct spotify_liquid_glassApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func applicationDidBecomeActive(_ application: UIApplication) {
        SpotifyPlaybackController.shared.reconnectIfNeeded()
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        SpotifyPlaybackController.shared.handleDidEnterBackground()
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
        return SpotifyPlaybackController.shared.handleIncomingURL(url)
    }
}
