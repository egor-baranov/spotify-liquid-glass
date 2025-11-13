import Foundation

func debugLog(_ message: String) {
    #if DEBUG
    print("[SpotifyDebug] \(message)")
    #endif
}

