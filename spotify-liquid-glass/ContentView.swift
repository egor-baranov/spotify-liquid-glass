//
//  ContentView.swift
//  spotify-liquid-glass
//
//  Created by Egor Baranov on 11/11/2025.
//

import SwiftUI
import UIKit
import CoreHaptics
import Combine
import AVFoundation

private let likedSongsGradientColors: [Color] = [
    Color(red: 0.54, green: 0.32, blue: 0.98),
    Color(red: 0.3, green: 0.08, blue: 0.42)
]

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @StateObject private var playbackManager = PlaybackManager.shared
    @State private var showPlayerFullScreen = false
    @State private var playerDetent: PresentationDetent = .fraction(1.0)
    @StateObject private var dataProvider = SpotifyDataProvider()
    @State private var showingAccount = false
    @StateObject private var userSession = SpotifyUserSession.shared
    @StateObject private var remotePlayback = SpotifyPlaybackController.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            LiquidGlassBackground()

            TabView(selection: $selectedTab) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        dataProvider: dataProvider,
                        onProfileTap: { showingAccount = true },
                        onPlaylistSelect: pushPlaylist,
                        onSongSelect: handleSongSelection,
                        onRefresh: { await refreshAllData() }
                    )
                    .navigationDestination(for: PlaylistDetail.self) { detail in
                        PlaylistDetailScreen(
                            detail: detail,
                            likedSongsCount: detail.playlist.isLikedSongs ? dataProvider.likedSongsTotal : nil,
                            onSongSelect: { song in
                                handleSongSelection(song)
                            },
                            onSongAppear: detail.playlist.isLikedSongs ? { handleLikedSongRowAppear($0) } : nil
                        )
                    }
                }
                .tabItem {
                    Image(systemName: AppTab.home.icon)
                    Text(AppTab.home.title)
                }
                .tag(AppTab.home)

                SearchView(
                    dataProvider: dataProvider,
                    onProfileTap: { showingAccount = true },
                    onPlaylistSelect: pushPlaylist,
                    onRefresh: { await refreshUserData() }
                )
                    .tabItem {
                        Image(systemName: AppTab.search.icon)
                        Text(AppTab.search.title)
                    }
                    .tag(AppTab.search)

                NavigationStack(path: $libraryPath) {
                    LibraryView(
                        onProfileTap: { showingAccount = true },
                        userCollections: libraryCollections,
                        onCollectionSelect: handleLibraryCollectionSelection,
                        onRefresh: { await refreshUserData() }
                    )
                        .navigationDestination(for: PlaylistDetail.self) { detail in
                            PlaylistDetailScreen(
                                detail: detail,
                                likedSongsCount: detail.playlist.isLikedSongs ? dataProvider.likedSongsTotal : nil,
                                onSongSelect: { song in
                                    handleSongSelection(song)
                                },
                                onSongAppear: detail.playlist.isLikedSongs ? { handleLikedSongRowAppear($0) } : nil
                            )
                        }
                }
                .tabItem {
                    Image(systemName: AppTab.library.icon)
                    Text(AppTab.library.title)
                }
                .tag(AppTab.library)
            }
            .tint(.white)
            .toolbarBackground(.visible, for: .tabBar)
            .toolbarBackground(.ultraThinMaterial, for: .tabBar)
            .toolbarColorScheme(.dark, for: .tabBar)

            if remotePlayback.currentSong != nil {
                RemoteMiniPlayerView(
                    remote: remotePlayback,
                    onExpand: {
                        Haptics.impact(.light)
                        showPlayerFullScreen = true
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            remotePlayback.disconnect()
                            showPlayerFullScreen = false
                        }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, miniPlayerBottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if playbackManager.currentSong != nil {
                MiniPlayerView(
                    playback: playbackManager,
                    onExpand: {
                        Haptics.impact(.light)
                        showPlayerFullScreen = true
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            showPlayerFullScreen = false
                        }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, miniPlayerBottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .environmentObject(userSession)
        .environmentObject(dataProvider)
        .task {
            await userSession.ensureProfileLoaded()
            let token = await userSession.validUserAccessToken()
            await dataProvider.refreshUserContent(accessToken: token)
        }
        .onChange(of: userSession.accessToken) { token in
            Task {
                await userSession.ensureProfileLoaded()
                if token != nil {
                    let fresh = await userSession.validUserAccessToken()
                    await dataProvider.refreshUserContent(accessToken: fresh)
                } else {
                    await dataProvider.refreshUserContent(accessToken: nil)
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPlayerFullScreen) {
            sheetContentForPlayer()
        }
        .sheet(isPresented: $showingAccount) {
            AccountView {
                showingAccount = false
            }
            .environmentObject(userSession)
        }
    }

    @ViewBuilder
    private func sheetContentForPlayer() -> some View {
        Group {
            if remotePlayback.currentSong != nil {
                RemotePlayerFullScreenView(remote: remotePlayback) {
                    showPlayerFullScreen = false
                }
            } else {
                PlayerFullScreenView(playback: playbackManager) {
                    showPlayerFullScreen = false
                }
            }
        }
        .presentationDetents([.fraction(1.0), .fraction(0.85)], selection: $playerDetent)
        .presentationDragIndicator(.visible)
        .onAppear {
            playerDetent = .fraction(1.0)
        }
    }

    private func pushPlaylist(_ playlist: Playlist) {
        let destinationTab = selectedTab
        Task {
            let detail = await buildPlaylistDetail(for: playlist)
            await MainActor.run {
                switch destinationTab {
                case .library:
                    libraryPath.append(detail)
                default:
                    homePath.append(detail)
                }
            }
        }
    }

    private func handleSongSelection(_ song: Song) {
        debugLog("User tapped song '\(song.title)' URI=\(song.spotifyURI ?? "nil")")
        Task {
            let token = userSession.accessToken
            let playedRemotely = await remotePlayback.playIfPossible(song: song, accessToken: token)
            debugLog(playedRemotely ? "Handed off to Spotify App Remote." : "App Remote unavailable, using preview playback.")
            if !playedRemotely {
                await playbackManager.play(song: song)
            } else {
                await MainActor.run {
                    playbackManager.stop()
                }
            }
        }
    }

    private func handleLibraryCollectionSelection(_ collection: LibraryCollection) {
        if let playlist = collection.playlist {
            pushPlaylist(playlist)
            return
        }
        let playlist = Playlist(
            spotifyID: collection.playlist?.spotifyID,
            title: collection.title,
            subtitle: collection.subtitle,
            descriptor: collection.meta,
            colors: collection.colors,
            imageURL: collection.imageURL ?? collection.playlist?.imageURL,
            isLikedSongs: collection.playlist?.isLikedSongs ?? false
        )
        pushPlaylist(playlist)
    }

    private func buildPlaylistDetail(for playlist: Playlist) async -> PlaylistDetail {
        let tracks = await fetchSongs(for: playlist)
        return PlaylistDetail(playlist: playlist, songs: tracks)
    }

    private func fetchSongs(for playlist: Playlist) async -> [Song] {
        if playlist.isLikedSongs {
            let cached = await MainActor.run { dataProvider.likedSongs }
            if !cached.isEmpty {
                debugLog("Using cached liked songs (\(cached.count))")
                return cached
            }

            guard let token = await userSession.validUserAccessToken() ?? userSession.accessToken else {
                debugLog("Liked songs fetch aborted: missing user token.")
                return cached
            }

            await dataProvider.loadLikedSongs(token: token, reset: true)
            debugLog("Fetched liked songs from Spotify (\(dataProvider.likedSongs.count)).")
            return await MainActor.run { dataProvider.likedSongs }
        }

        if let spotifyID = playlist.spotifyID {
            if let token = await userSession.validUserAccessToken() {
                if let tracks = try? await SpotifyAPIClient.shared.fetchPlaylistTracks(
                    id: spotifyID,
                    accessToken: token,
                    limit: 100
                ) {
                    return tracks.map { $0.asSong }
                }
            }

            if let tracks = try? await SpotifyAPIClient.shared.fetchPlaylistTracks(id: spotifyID, limit: 100) {
                return tracks.map { $0.asSong }
            }

            return DemoData.playlistTracks(for: playlist)
        }
        return DemoData.playlistTracks(for: playlist)
    }

    private func handleLikedSongRowAppear(_ song: Song) {
        guard dataProvider.shouldLoadMoreLikedSongs(currentSongID: song.id) else { return }
        Task {
            guard let token = await userSession.validUserAccessToken() ?? userSession.accessToken else { return }
            await dataProvider.loadMoreLikedSongs(accessToken: token)
        }
    }
    private var miniPlayerBottomPadding: CGFloat {
        max(safeAreaBottomInset + 56, 70)
    }

    private var safeAreaBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
    }

    private var libraryCollections: [LibraryCollection] {
        var collections = dataProvider.userPlaylists.map { $0.asLibraryCollection() }
        if let liked = likedSongsCollection {
            collections.insert(liked, at: 0)
        }
        return collections
    }

    private var likedSongsCollection: LibraryCollection? {
        guard let playlist = likedSongsPlaylist else { return nil }
        return LibraryCollection(
            title: playlist.title,
            subtitle: playlist.subtitle,
            meta: playlist.descriptor,
            icon: "heart.fill",
            colors: playlist.colors,
            type: .playlists,
            isPinned: true,
            imageURL: playlist.imageURL,
            playlist: playlist
        )
    }

    private var likedSongsPlaylist: Playlist? {
        guard userSession.isLoggedIn else { return nil }
        let subtitle = dataProvider.likedSongs.isEmpty
            ? "Your favorites"
            : "\(dataProvider.likedSongs.count) liked tracks"
        return Playlist(
            title: "Liked Songs",
            subtitle: subtitle,
            descriptor: "Saved tracks",
            colors: likedSongsGradientColors,
            imageURL: dataProvider.likedSongs.first?.artworkURL,
            isLikedSongs: true
        )
    }

    @MainActor
    private func refreshAllData() async {
        await dataProvider.refreshHome()
        let token = await userSession.validUserAccessToken()
        await dataProvider.refreshUserContent(accessToken: token)
    }

    @MainActor
    private func refreshUserData() async {
        let token = await userSession.validUserAccessToken()
        await dataProvider.refreshUserContent(accessToken: token)
    }
}

// MARK: - Tabs

enum AppTab: String, CaseIterable, Identifiable {
    case home, search, library

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .search: return "Search"
        case .library: return "Library"
        }
    }

    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .library: return "rectangle.stack.fill"
        }
    }

    private var gradientColors: [Color] {
        switch self {
        case .home:
            return [
                Color(red: 0.93, green: 0.34, blue: 0.63),
                Color(red: 0.49, green: 0.22, blue: 0.98)
            ]
        case .search:
            return [
                Color(red: 0.21, green: 0.74, blue: 0.96),
                Color(red: 0.03, green: 0.35, blue: 0.89)
            ]
        case .library:
            return [
                Color(red: 0.18, green: 0.9, blue: 0.69),
                Color(red: 0.08, green: 0.58, blue: 0.34)
            ]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accent: Color {
        gradientColors.first ?? .white
    }
}

// MARK: - Background

struct LiquidGlassBackground: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.01, green: 0.02, blue: 0.05),
                    Color(red: 0.03, green: 0.04, blue: 0.08),
                    Color(red: 0.01, green: 0.01, blue: 0.03)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            GeometryReader { proxy in
                let size = proxy.size

                ZStack {
                    Circle()
                        .fill(Color(red: 0.93, green: 0.34, blue: 0.93).opacity(0.55))
                        .frame(width: size.width * 0.9)
                        .blur(radius: 140)
                        .offset(
                            x: animate ? -size.width * 0.2 : size.width * 0.25,
                            y: animate ? -size.height * 0.3 : -size.height * 0.05
                        )
                        .animation(.easeInOut(duration: 14).repeatForever(autoreverses: true), value: animate)

                    Circle()
                        .fill(Color(red: 0.19, green: 0.64, blue: 1).opacity(0.45))
                        .frame(width: size.width * 0.85)
                        .blur(radius: 150)
                        .offset(
                            x: animate ? size.width * 0.3 : -size.width * 0.15,
                            y: animate ? size.height * 0.25 : size.height * 0.1
                        )
                        .animation(.easeInOut(duration: 18).repeatForever(autoreverses: true), value: animate)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .blendMode(.screen)
                .ignoresSafeArea()
                .opacity(0.8)
        }
        .onAppear { animate = true }
    }
}

// MARK: - Screens

struct HomeView: View {
    @ObservedObject var dataProvider: SpotifyDataProvider
    @EnvironmentObject private var userSession: SpotifyUserSession
    let onProfileTap: () -> Void
    let onPlaylistSelect: (Playlist) -> Void
    let onSongSelect: (Song) -> Void
    let onRefresh: () async -> Void

    @State private var selectedCategory = "All"
    private let categories = ["All", "Music", "Podcasts", "Audiobooks"]

    private var likedSongsPlaceholder: Playlist {
        let total = max(dataProvider.likedSongsTotal, dataProvider.likedSongs.count)
        let subtitle = total > 0 ? "\(total) liked tracks" : "Your favorites"
        return Playlist(
            title: "Liked Songs",
            subtitle: subtitle,
            descriptor: "Saved tracks",
            colors: likedSongsGradientColors,
            imageURL: nil,
            isLikedSongs: true
        )
    }

    private var personalPlaylists: [Playlist] {
        if !dataProvider.userPlaylists.isEmpty {
            return dataProvider.userPlaylists
        }
        let remote = dataProvider.dailyMixes
        return remote.isEmpty ? DemoData.dailyMixes : remote
    }

    private var mixes: [Playlist] {
        personalPlaylists
    }

    private var gridPlaylists: [Playlist] {
        var source = personalPlaylists
        if source.isEmpty {
            source = DemoData.dailyMixes
        }
        let fillers = DemoData.quickPicks + DemoData.dailyMixes
        var fillerIndex = 0
        while source.count < 7 {
            source.append(fillers[fillerIndex % fillers.count])
            fillerIndex += 1
        }
        let likedCard = likedSongsPlaceholder
        return [likedCard] + Array(source.prefix(7))
    }

    private var quick: [Playlist] {
        if !dataProvider.userPlaylists.isEmpty {
            return Array(dataProvider.userPlaylists.shuffled().prefix(6))
        }
        return dataProvider.quickPicks.isEmpty ? DemoData.quickPicks : dataProvider.quickPicks
    }

    private var trending: [Song] {
        dataProvider.trendingSongs.isEmpty ? DemoData.trendingSongs : dataProvider.trendingSongs
    }

    private var releaseHighlight: Song? {
        dataProvider.releaseHighlight ?? trending.first
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                HomeProfileHeader(onTap: onProfileTap)
                HomeCategoryBar(categories: categories, selection: $selectedCategory)

                HomePlaylistGrid(playlists: gridPlaylists) { playlist in
                    onPlaylistSelect(playlist)
                }

                if let featuredRelease = releaseHighlight {
                    HomeReleaseCard(song: featuredRelease) {
                        onSongSelect(featuredRelease)
                    }
                }

                SectionHeader(title: "Daily mixes", subtitle: "Curated for you")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 20) {
                        ForEach(mixes) { mix in
                            Button {
                                onPlaylistSelect(mix)
                            } label: {
                                DailyMixCard(playlist: mix)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.trailing, 6)
                }

                SectionHeader(title: "Quick picks", subtitle: "Jump back in")
                QuickPickGrid(playlists: quick, onSelect: onPlaylistSelect)

                SectionHeader(title: "Trending now", subtitle: "Global top mixes")
                VStack(spacing: 16) {
                    ForEach(trending) { song in
                        TrendingRow(song: song) {
                            onSongSelect(song)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
        .refreshable {
            await onRefresh()
        }
    }
}

struct SearchView: View {
    @ObservedObject var dataProvider: SpotifyDataProvider
    @State private var query = ""
    let onProfileTap: () -> Void
    let onPlaylistSelect: (Playlist) -> Void
    let onRefresh: () async -> Void
    private let categories = DemoData.searchCategories

    private var personalPlaylists: [Playlist] {
        dataProvider.userPlaylists.isEmpty ? DemoData.dailyMixes : dataProvider.userPlaylists
    }

    private var featuredMixes: [Playlist] {
        dataProvider.dailyMixes.isEmpty ? DemoData.dailyMixes : dataProvider.dailyMixes
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                GreetingHeader(
                    title: "Search",
                    subtitle: "Find artists, songs or podcasts.",
                    onProfileTap: onProfileTap
                )
                LiquidSearchField(text: $query)

                if !personalPlaylists.isEmpty {
                    SectionHeader(title: "Your playlists", subtitle: "Jump back in")
                    SearchPlaylistGrid(playlists: personalPlaylists, onSelect: onPlaylistSelect)
                }

                if !featuredMixes.isEmpty {
                    SectionHeader(title: "Featured mixes", subtitle: "Handpicked for you")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(featuredMixes) { playlist in
                                Button {
                                    onPlaylistSelect(playlist)
                                } label: {
                                    DailyMixCard(playlist: playlist)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.trailing, 6)
                    }
                }

                SectionHeader(title: "Browse all", subtitle: "Genres & moods")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 2), spacing: 18) {
                    ForEach(categories) { category in
                        SearchCategoryCard(category: category)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
        .refreshable {
            await onRefresh()
        }
    }
}

struct LibraryView: View {
    let onProfileTap: () -> Void
    let userCollections: [LibraryCollection]
    let onCollectionSelect: (LibraryCollection) -> Void
    let onRefresh: () async -> Void
    @State private var selectedFilter: LibraryFilter = .all
    @State private var layoutStyle: LibraryLayout = .grid

    private var baseCollections: [LibraryCollection] {
        userCollections.isEmpty ? DemoData.libraryCollections : userCollections
    }

    private var filteredCollections: [LibraryCollection] {
        let collections = baseCollections
        guard selectedFilter != .all else { return collections }
        return collections.filter { $0.type == selectedFilter }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                LibraryTopBar(
                    title: "Your Library",
                    subtitle: "Everything you've saved and downloaded.",
                    onProfileTap: onProfileTap
                )

                LibraryFilters(selected: $selectedFilter)

                HStack {
                    Button {
                        Haptics.impact(.light)
                    } label: {
                        Label("Recents", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        layoutStyle.toggle()
                        Haptics.impact(.soft)
                    } label: {
                        Image(systemName: layoutStyle == .grid ? "list.bullet" : "square.grid.2x2")
                            .font(.title3.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(.white.opacity(0.85))

                if layoutStyle == .grid {
                    LibraryGridView(collections: filteredCollections, onCollectionSelect: onCollectionSelect)
                } else {
                    VStack(spacing: 20) {
                        ForEach(filteredCollections) { item in
                            Button {
                                onCollectionSelect(item)
                            } label: {
                                LibraryRow(collection: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 160)
        }
        .refreshable {
            await onRefresh()
        }
    }
}

// MARK: - Shared UI

struct GreetingHeader: View {
    let title: String
    let subtitle: String
    var onProfileTap: (() -> Void)? = nil
    @EnvironmentObject private var userSession: SpotifyUserSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let onProfileTap {
                HStack {
                    ProfileBubble(size: 34, action: onProfileTap)
                    Spacer()
                }
                .padding(.top, -4)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.65))
                Text(subtitle)
                    .font(.title2.weight(.semibold))
            }
            Spacer()
        }
    }
}

struct NowPlayingCard: View {
    let song: Song

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Now playing")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
                .textCase(.uppercase)

            Text(song.title)
                .font(.title.bold())

            Text(song.artist)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))

            Text(song.tagline)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))

            HStack {
                GlassButton(title: "Play", icon: "play.fill")
                GlassButton(title: "Shuffle", icon: "shuffle")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(song.gradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .fill(
                            LinearGradient(colors: [.white.opacity(0.25), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .blendMode(.screen)
                        .blur(radius: 8)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: song.accent.opacity(0.5), radius: 30, y: 12)
    }
}

struct DailyMixCard: View {
    let playlist: Playlist

    var body: some View {
        HStack(spacing: 16) {
            CoverImageView(
                imageURL: playlist.imageURL,
                size: 96,
                cornerRadius: 26,
                gradient: playlist.gradient
            )
            VStack(alignment: .leading, spacing: 8) {
                Text(playlist.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(playlist.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
                Text(playlist.descriptor)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
        .padding(20)
        .frame(width: 260, height: 140, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(playlist.gradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: playlist.colors.first?.opacity(0.4) ?? .black.opacity(0.4), radius: 20, y: 10)
    }
}

struct QuickPickGrid: View {
    let playlists: [Playlist]
    let onSelect: (Playlist) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(playlists) { playlist in
                Button {
                    onSelect(playlist)
                } label: {
                    QuickPickCard(playlist: playlist)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct QuickPickCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CoverImageView(
                imageURL: playlist.imageURL,
                size: 140,
                cornerRadius: 28,
                gradient: playlist.gradient
            )
            VStack(alignment: .leading, spacing: 6) {
                Text(playlist.title)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(playlist.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                Text(playlist.descriptor)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassSurface(cornerRadius: 28)
    }
}

struct TrendingRow: View {
    let song: Song
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(song.gradient)
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: "waveform")
                            .foregroundStyle(.white.opacity(0.9))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.headline)
                    Text(song.artist)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                    Text(song.tagline)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }

                Spacer()

                Text(song.duration)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.all, 16)
            .glassSurface(cornerRadius: 28)
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistDetailScreen: View {
    @EnvironmentObject private var dataProvider: SpotifyDataProvider
    let detail: PlaylistDetail
    let likedSongsCount: Int?
    let onSongSelect: (Song) -> Void
    var onSongAppear: ((Song) -> Void)? = nil

    private var displayedSongs: [Song] {
        if detail.playlist.isLikedSongs {
            return dataProvider.likedSongs
        }
        return detail.songs
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.07, blue: 0.09),
                    Color(red: 0.01, green: 0.01, blue: 0.02)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    PlaylistHeader(detail: detail, likedSongsCount: likedSongsCount)
                    PlaylistActionRow()

                    VStack(spacing: 18) {
                        ForEach(Array(displayedSongs.enumerated()), id: \.element.id) { index, song in
                            PlaylistSongRow(position: index + 1, song: song) {
                                onSongSelect(song)
                            }
                            .onAppear {
                                onSongAppear?(song)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 160)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PlaylistHeader: View {
    let detail: PlaylistDetail
    private let coverSize: CGFloat = 250
    var likedSongsCount: Int? = nil

    private var likedSongsSubtitle: String {
        let count = likedSongsCount ?? 0
        if count > 0 {
            return "\(count) liked tracks"
        }
        return detail.playlist.subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if detail.playlist.isLikedSongs {
                CoverImageView(
                    imageURL: nil,
                    size: coverSize,
                    cornerRadius: 32,
                    gradient: LinearGradient(
                        colors: likedSongsGradientColors,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    overlayIcon: "heart.fill"
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 24)
            } else {
                CoverImageView(
                    imageURL: detail.playlist.imageURL,
                    size: coverSize,
                    cornerRadius: 32,
                    gradient: detail.playlist.gradient,
                    overlayIcon: detail.playlist.imageURL == nil ? "music.note" : nil
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 24)
            }

            Text(detail.playlist.title)
                .font(.largeTitle.bold())
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.playlist.isLikedSongs ? likedSongsSubtitle : detail.playlist.subtitle)
                        .font(.subheadline.weight(.semibold))
                    Text(detail.playlist.isLikedSongs ? "Playlist • Saved tracks" : "Playlist • \(detail.playlist.descriptor)")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct PlaylistActionRow: View {
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 18) {
                CircleIconButton(systemName: "plus")
                CircleIconButton(systemName: "arrow.down.circle")
                CircleIconButton(systemName: "ellipsis")
            }

            Spacer()

            HStack(spacing: 14) {
                CircleIconButton(systemName: "shuffle")
                CircleIconButton(systemName: "play.fill")
            }
        }
    }
}

struct CircleIconButton: View {
    let systemName: String
    var size: CGFloat = 48
    var isSolid: Bool = false

    var body: some View {
        Button {
            Haptics.impact(.light)
        } label: {
            Circle()
                .fill(isSolid ? Color.white.opacity(0.25) : Color.white.opacity(0.08))
                .frame(width: size, height: size)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                .overlay(
                    Image(systemName: systemName)
                        .font(.system(size: isSolid ? 20 : 18, weight: .semibold))
                        .foregroundStyle(isSolid ? Color.black : Color.white)
                )
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistSongRow: View {
    let position: Int
    let song: Song
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                CoverImageView(
                    imageURL: song.artworkURL,
                    size: 48,
                    cornerRadius: 14,
                    gradient: song.gradient,
                    overlayIcon: song.artworkURL == nil ? "music.note" : nil
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.headline)
                    Text(song.artist)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                Spacer()

                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct MiniPlayerView: View {
    @ObservedObject var playback: PlaybackManager
    let onExpand: () -> Void
    let onClose: () -> Void

    private var song: Song? { playback.currentSong }

    var body: some View {
        if let song {
            HStack(spacing: 12) {
                CoverImageView(
                    imageURL: song.artworkURL,
                    size: 44,
                    cornerRadius: 12,
                    gradient: song.gradient,
                    overlayIcon: song.artworkURL == nil ? "music.note" : nil
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    playback.togglePlayPause()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline.weight(.bold))
                }

                Button {
                    playback.stop()
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            .onTapGesture {
                onExpand()
            }
        }
    }
}

struct RemoteMiniPlayerView: View {
    @ObservedObject var remote: SpotifyPlaybackController
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        if let song = remote.currentSong {
            HStack(spacing: 12) {
                CoverImageView(
                    imageURL: song.artworkURL,
                    uiImage: remote.currentArtwork,
                    size: 44,
                    cornerRadius: 12,
                    gradient: song.gradient,
                    overlayIcon: (song.artworkURL == nil && remote.currentArtwork == nil) ? "music.note" : nil
                )
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    remote.togglePlayPause()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: remote.isPlaying ? "pause.fill" : "play.fill")
                        .font(.headline.weight(.bold))
                }
                Button {
                    remote.disconnect()
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 8)
            .onTapGesture {
                onExpand()
            }
        }
    }
}

struct PlayerFullScreenView: View {
    @ObservedObject var playback: PlaybackManager
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.28, green: 0.29, blue: 0.32),
                    Color(red: 0.14, green: 0.15, blue: 0.18)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 88, height: 5)
                    .padding(.top, 14)

                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                if let song = playback.currentSong {
                    CoverImageView(
                        imageURL: song.artworkURL,
                        size: 320,
                        cornerRadius: 40,
                        gradient: song.gradient,
                        overlayIcon: song.artworkURL == nil ? "music.note" : nil
                    )
                    VStack(spacing: 8) {
                        Text(song.title)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(song.artist)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 10)
                } else {
                    Spacer().frame(height: 320)
                }

                VStack(spacing: 18) {
                    Slider(
                        value: Binding(
                            get: { playback.progress },
                            set: { playback.seek(to: $0) }
                        ),
                        in: 0...1
                    )
                    .accentColor(.white)
                    .padding(.horizontal, 16)
                    .disabled(playback.duration == 0)
                    .opacity(playback.duration == 0 ? 0.5 : 1)

                    HStack {
                        Text(playback.elapsedText)
                        Spacer()
                        Text(playback.durationText)
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 36)

                HStack(spacing: 28) {
                    GlassControlButton(systemName: "backward.fill")
                    GlassControlButton(systemName: playback.isPlaying ? "pause.fill" : "play.fill", isPrimary: true) {
                        playback.togglePlayPause()
                    }
                    GlassControlButton(systemName: "forward.fill")
                }
                .padding(.top, 16)

                HStack(spacing: 28) {
                    GlassControlButton(systemName: "bubble.left.and.bubble.right", size: 56)
                    GlassControlButton(systemName: "airplayaudio", size: 56)
                    GlassControlButton(systemName: "list.bullet", size: 56)
                }
                .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
        }
    }
}

struct RemotePlayerFullScreenView: View {
    @ObservedObject var remote: SpotifyPlaybackController
    let onClose: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.16, green: 0.16, blue: 0.18),
                    Color(red: 0.05, green: 0.05, blue: 0.07)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Capsule()
                    .fill(Color.white.opacity(0.3))
                    .frame(width: 88, height: 5)
                    .padding(.top, 14)
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16)

                Spacer()

                if let song = remote.currentSong {
                    CoverImageView(
                        imageURL: song.artworkURL,
                        uiImage: remote.currentArtwork,
                        size: 320,
                        cornerRadius: 40,
                        gradient: song.gradient,
                        overlayIcon: (song.artworkURL == nil && remote.currentArtwork == nil) ? "music.note" : nil
                    )
                    VStack(spacing: 8) {
                        Text(song.title)
                            .font(.title2.weight(.semibold))
                        Text(song.artist)
                            .font(.body)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(.top, 10)
                } else {
                    Spacer().frame(height: 320)
                }

                VStack(spacing: 18) {
                    Slider(
                        value: Binding(
                            get: {
                                guard remote.trackDuration > 0 else { return 0 }
                                return remote.playbackPosition / max(remote.trackDuration, 0.001)
                            },
                            set: { remote.seek(toProgress: $0) }
                        ),
                        in: 0...1
                    )
                    .accentColor(.white)
                    .padding(.horizontal, 16)
                    .disabled(remote.trackDuration == 0)
                    .opacity(remote.trackDuration == 0 ? 0.5 : 1)

                    HStack {
                        Text(remote.playbackPosition.asTimeString())
                        Spacer()
                        Text(remote.trackDuration.asTimeString())
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 36)

                HStack(spacing: 28) {
                    GlassControlButton(systemName: "backward.fill") {
                        remote.skipToPrevious()
                    }
                    GlassControlButton(systemName: remote.isPlaying ? "pause.fill" : "play.fill", isPrimary: true) {
                        remote.togglePlayPause()
                    }
                    GlassControlButton(systemName: "forward.fill") {
                        remote.skipToNext()
                    }
                }
                .padding(.top, 16)

                Spacer()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 52)
        }
    }
}

struct GlassControlButton: View {
    let systemName: String
    var size: CGFloat = 64
    var isPrimary: Bool = false
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            Haptics.impact(.light)
            action?()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: isPrimary ? 26 : 20, weight: .bold))
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(isPrimary ? Color.white : Color.white.opacity(0.08))
                        .overlay(
                            Circle()
                                .stroke(Color.white.opacity(isPrimary ? 0.6 : 0.25), lineWidth: 1)
                        )
                )
                .foregroundStyle(isPrimary ? Color.black : Color.white.opacity(0.85))
                .shadow(color: .black.opacity(0.4), radius: isPrimary ? 16 : 8, y: 6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Playback

final class PlaybackManager: ObservableObject {
    static let shared = PlaybackManager()

    @Published private(set) var currentSong: Song?
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0

    @MainActor private var player: AVPlayer?
    @MainActor private var timeObserver: Any?
    @MainActor private var playbackEndObserver: NSObjectProtocol?

    deinit {
        removeTimeObserver()
        removePlaybackEndObserver()
    }

    var elapsedText: String {
        currentTime.asTimeString()
    }

    var durationText: String {
        duration.asTimeString()
    }

    @MainActor
    func play(song: Song) async {
        guard let url = await resolvePreviewURL(for: song) else {
            debugLog("Preview playback unavailable for \(song.title)")
            return
        }
        debugLog("Starting preview playback for \(song.title) @ \(url.absoluteString)")

        if currentSong?.id != song.id {
            preparePlayer(with: url)
            currentSong = song
        }

        player?.play()
        isPlaying = true
    }

    @MainActor
    func togglePlayPause() {
        guard player != nil else { return }
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }

    @MainActor
    func stop() {
        player?.pause()
        removeTimeObserver()
        removePlaybackEndObserver()
        player = nil
        currentSong = nil
        isPlaying = false
        progress = 0
        currentTime = 0
        duration = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    @MainActor
    func seek(to progress: Double) {
        guard let player = player, duration > 0 else { return }
        let seconds = progress * duration
        let time = CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player.seek(to: time)
        currentTime = seconds
        self.progress = progress
    }

    private func resolvePreviewURL(for song: Song) async -> URL? {
        if let direct = song.audioPreviewURL {
            return direct
        }
        return await PreviewResolver.shared.resolvePreviewURL(for: song)
    }

    private func preparePlayer(with url: URL) {
        removeTimeObserver()
        removePlaybackEndObserver()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        duration = item.asset.duration.seconds.isFinite ? item.asset.duration.seconds : 0
        currentTime = 0
        progress = 0
        addTimeObserver()
        playbackEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player?.seek(to: .zero)
            self?.isPlaying = false
            self?.progress = 0
            self?.currentTime = 0
        }
    }

    private func addTimeObserver() {
        guard let player = player else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            let seconds = time.seconds
            self.currentTime = seconds
            if self.duration > 0 {
                self.progress = seconds / self.duration
            } else {
                self.progress = 0
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func removePlaybackEndObserver() {
        if let observer = playbackEndObserver {
            NotificationCenter.default.removeObserver(observer)
            playbackEndObserver = nil
        }
    }
}


private extension Double {
    func asTimeString() -> String {
        guard self.isFinite else { return "0:00" }
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension Int {
    func asTimeString() -> String {
        let minutes = self / 60
        let seconds = self % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

actor PreviewResolver {
    static let shared = PreviewResolver()

    private var cache: [String: URL] = [:]

    func resolvePreviewURL(for song: Song) async -> URL? {
        if let cached = cache[song.id] {
            return cached
        }

        let query = "\(song.artist) \(song.title)"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://itunes.apple.com/search?term=\(encoded)&limit=1&media=music") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            let result = try JSONDecoder().decode(ITunesSearchResponse.self, from: data)
            guard let previewString = result.results.first?.previewUrl,
                  let previewURL = URL(string: previewString) else {
                return nil
            }
            cache[song.id] = previewURL
            return previewURL
        } catch {
            return nil
        }
    }
}

private struct ITunesSearchResponse: Decodable {
    struct Result: Decodable {
        let previewUrl: String?
    }
    let results: [Result]
}


struct LiquidSearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(.white.opacity(0.8))
            TextField("Artists, songs, podcasts...", text: $text)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .foregroundStyle(.white)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .glassSurface(cornerRadius: 30)
    }
}

struct SearchCategoryCard: View {
    let category: SearchCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: category.icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.9))
            Spacer()
            Text(category.name)
                .font(.headline)
            Text(category.tagline)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(20)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(category.gradient)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
}

struct SearchPlaylistGrid: View {
    let playlists: [Playlist]
    let onSelect: (Playlist) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(playlists.prefix(8)) { playlist in
                Button {
                    onSelect(playlist)
                } label: {
                    SearchPlaylistCard(playlist: playlist)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SearchPlaylistCard: View {
    let playlist: Playlist

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CoverImageView(
                imageURL: playlist.imageURL,
                size: 150,
                cornerRadius: 28,
                gradient: playlist.gradient
            )
            Text(playlist.title)
                .font(.headline)
                .lineLimit(2)
            Text(playlist.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }
}

struct LibraryRow: View {
    let collection: LibraryCollection

    var body: some View {
        HStack(spacing: 16) {
            CoverImageView(
                imageURL: collection.imageURL ?? collection.playlist?.imageURL,
                size: 58,
                cornerRadius: 18,
                gradient: collection.gradient,
                overlayIcon: (collection.imageURL ?? collection.playlist?.imageURL) == nil ? collection.icon : nil
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(collection.title)
                    .font(.headline)
                Text(collection.subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text(collection.meta)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.all, 16)
        .glassSurface(cornerRadius: 28)
    }
}

struct LibraryTopBar: View {
    let title: String
    let subtitle: String
    let onProfileTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 18) {
                ProfileBubble(size: 34, action: onProfileTap)

                Spacer()

                HStack(spacing: 16) {
                    Button {
                        Haptics.impact(.light)
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.headline.weight(.semibold))
                    }

                    Button {
                        Haptics.impact(.light)
                    } label: {
                        Image(systemName: "plus")
                            .font(.headline.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }
}

struct LibraryFilters: View {
    @Binding var selected: LibraryFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                ForEach(LibraryFilter.allCases) { filter in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            selected = filter
                        }
                    } label: {
                        Text(filter.title)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selected == filter ? Color.white.opacity(0.9) : Color.white.opacity(0.08))
                            )
                            .foregroundStyle(selected == filter ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct LibraryGridView: View {
    let collections: [LibraryCollection]
    let onCollectionSelect: (LibraryCollection) -> Void
    private let columns = [
        GridItem(.flexible(), spacing: 18),
        GridItem(.flexible(), spacing: 18)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 18) {
            ForEach(collections) { item in
                Button {
                    onCollectionSelect(item)
                } label: {
                    LibraryGridCard(collection: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct LibraryGridCard: View {
    let collection: LibraryCollection
    private let cardHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImageView(
                imageURL: collection.imageURL ?? collection.playlist?.imageURL,
                size: 140,
                cornerRadius: 22,
                gradient: collection.gradient,
                overlayIcon: (collection.imageURL ?? collection.playlist?.imageURL) == nil ? (collection.isPinned ? "heart.fill" : collection.icon) : nil
            )

            Text(collection.title)
                .font(.headline)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(collection.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .top)
        .padding(14)
        .glassSurface(cornerRadius: 26)
    }
}

struct GlassButton: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
            Text(title)
                .font(.headline.weight(.semibold))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
        )
    }
}

struct ProfileBubble: View {
    @EnvironmentObject private var userSession: SpotifyUserSession
    let size: CGFloat
    let action: () -> Void

    private var initials: String {
        guard let displayName = userSession.displayName, !displayName.isEmpty else {
            return "EB"
        }
        let parts = displayName.split(separator: " ")
        let firstLetters = parts.prefix(2).compactMap { $0.first }
        return firstLetters.map { String($0) }.joined().uppercased()
    }

    var body: some View {
        Button(action: action) {
            if let url = userSession.avatarURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Circle().fill(Color.white.opacity(0.1))
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
            } else {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.93, green: 0.34, blue: 0.63),
                                Color(red: 0.3, green: 0.08, blue: 0.42)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(.caption.weight(.bold))
                    )
            }
        }
        .buttonStyle(.plain)
    }
}


// MARK: - Data Models

struct Song: Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let tagline: String
    let duration: String
    let colors: [Color]
    let artworkURL: URL?
    let audioPreviewURL: URL?
    let spotifyURI: String?

    init(
        id: String = UUID().uuidString,
        title: String,
        artist: String,
        tagline: String,
        duration: String,
        colors: [Color],
        artworkURL: URL? = nil,
        audioPreviewURL: URL? = nil,
        spotifyURI: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.tagline = tagline
        self.duration = duration
        self.colors = colors
        self.artworkURL = artworkURL
        self.audioPreviewURL = audioPreviewURL
        self.spotifyURI = spotifyURI
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var accent: Color {
        colors.first ?? .white
    }

    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct Playlist: Identifiable, Hashable {
    let id = UUID()
    let spotifyID: String?
    let title: String
    let subtitle: String
    let descriptor: String
    let colors: [Color]
    let imageURL: URL?
    let isLikedSongs: Bool

    init(
        spotifyID: String? = nil,
        title: String,
        subtitle: String,
        descriptor: String,
        colors: [Color],
        imageURL: URL? = nil,
        isLikedSongs: Bool = false
    ) {
        self.spotifyID = spotifyID
        self.title = title
        self.subtitle = subtitle
        self.descriptor = descriptor
        self.colors = colors
        self.imageURL = imageURL
        self.isLikedSongs = isLikedSongs
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct PlaylistDetail: Identifiable, Hashable {
    let id = UUID()
    let playlist: Playlist
    let songs: [Song]

    static func == (lhs: PlaylistDetail, rhs: PlaylistDetail) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct SearchCategory: Identifiable {
    let id = UUID()
    let name: String
    let tagline: String
    let icon: String
    let colors: [Color]

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

struct LibraryCollection: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let meta: String
    let icon: String
    let colors: [Color]
    let type: LibraryFilter
    let isPinned: Bool
    let imageURL: URL?
    let playlist: Playlist?

    init(
        title: String,
        subtitle: String,
        meta: String,
        icon: String,
        colors: [Color],
        type: LibraryFilter,
        isPinned: Bool,
        imageURL: URL? = nil,
        playlist: Playlist? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.meta = meta
        self.icon = icon
        self.colors = colors
        self.type = type
        self.isPinned = isPinned
        self.imageURL = imageURL
        self.playlist = playlist
    }

    var gradient: LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, playlists, albums, podcasts, artists, downloads

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

enum LibraryLayout {
    case grid, list

    mutating func toggle() {
        self = self == .grid ? .list : .grid
    }
}

enum DemoData {
    static let heroSong = Song(
        title: "Midnight City (Live 2026)",
        artist: "M83, Caroline Polachek",
        tagline: "Because you liked Dreamwave Nights",
        duration: "4:03",
        colors: [
            Color(red: 0.91, green: 0.26, blue: 0.65),
            Color(red: 0.41, green: 0.11, blue: 0.9)
        ]
    )

    static let dailyMixes: [Playlist] = [
        Playlist(
            title: "Daily Mix 1",
            subtitle: "ODESZA, Flume, Fred again..",
            descriptor: "Neon electronica",
            colors: [
                Color(red: 0.77, green: 0.36, blue: 0.97),
                Color(red: 0.36, green: 0.15, blue: 0.68)
            ]
        ),
        Playlist(
            title: "Daily Mix 2",
            subtitle: "Khruangbin, Men I Trust, Parcels",
            descriptor: "Laidback groove",
            colors: [
                Color(red: 0.11, green: 0.63, blue: 0.89),
                Color(red: 0.04, green: 0.28, blue: 0.61)
            ]
        ),
        Playlist(
            title: "Daily Mix 3",
            subtitle: "The Weeknd, Drake, SZA",
            descriptor: "Future R&B",
            colors: [
                Color(red: 0.98, green: 0.47, blue: 0.4),
                Color(red: 0.75, green: 0.17, blue: 0.29)
            ]
        )
    ]

    static let quickPicks: [Playlist] = [
        Playlist(
            title: "Hyperfocus",
            subtitle: "Deep tech + minimal beats",
            descriptor: "Stay productive",
            colors: [
                Color(red: 0.23, green: 0.91, blue: 0.57),
                Color(red: 0.12, green: 0.55, blue: 0.31)
            ]
        ),
        Playlist(
            title: "Neon Yoga",
            subtitle: "Ambient, Bonobo, Tycho",
            descriptor: "Mindful energy",
            colors: [
                Color(red: 0.11, green: 0.66, blue: 0.92),
                Color(red: 0.08, green: 0.3, blue: 0.64)
            ]
        ),
        Playlist(
            title: "Fresh Finds",
            subtitle: "Indie radar every Friday",
            descriptor: "New music",
            colors: [
                Color(red: 0.96, green: 0.55, blue: 0.25),
                Color(red: 0.81, green: 0.19, blue: 0.27)
            ]
        ),
        Playlist(
            title: "Synth Run",
            subtitle: "Justice, Kavinsky, Röyksopp",
            descriptor: "Night drive",
            colors: [
                Color(red: 0.59, green: 0.39, blue: 0.94),
                Color(red: 0.28, green: 0.11, blue: 0.46)
            ]
        )
    ]

    static let trendingSongs: [Song] = [
        Song(
            title: "Mirrors",
            artist: "Fred again.. & Romy",
            tagline: "New at #1 • Global",
            duration: "3:31",
            colors: [
                Color(red: 0.21, green: 0.73, blue: 0.94),
                Color(red: 0.12, green: 0.32, blue: 0.91)
            ]
        ),
        Song(
            title: "Desert Bloom",
            artist: "Khruangbin",
            tagline: "Trending in your Library",
            duration: "4:48",
            colors: [
                Color(red: 0.98, green: 0.52, blue: 0.4),
                Color(red: 0.75, green: 0.16, blue: 0.42)
            ]
        ),
        Song(
            title: "Eclipse Kids",
            artist: "Magdalena Bay",
            tagline: "Fans of Future Nostalgia",
            duration: "3:22",
            colors: [
                Color(red: 0.78, green: 0.45, blue: 0.98),
                Color(red: 0.34, green: 0.15, blue: 0.62)
            ]
        ),
        Song(
            title: "Lost Signal",
            artist: "ODESZA",
            tagline: "Because you played Summer's Gone",
            duration: "4:05",
            colors: [
                Color(red: 0.28, green: 0.91, blue: 0.82),
                Color(red: 0.12, green: 0.55, blue: 0.78)
            ]
        )
    ]

    static let additionalSongs: [Song] = [
        Song(
            title: "Photon Trails",
            artist: "Tycho",
            tagline: "Instrumental focus",
            duration: "5:14",
            colors: [
                Color(red: 0.52, green: 0.79, blue: 0.98),
                Color(red: 0.21, green: 0.36, blue: 0.67)
            ]
        ),
        Song(
            title: "Crystal Skies",
            artist: "Bonobo",
            tagline: "Downtempo essentials",
            duration: "4:44",
            colors: [
                Color(red: 0.94, green: 0.59, blue: 0.35),
                Color(red: 0.66, green: 0.3, blue: 0.12)
            ]
        ),
        Song(
            title: "Velvet Pulse",
            artist: "Charlotte de Witte",
            tagline: "Peak hour techno",
            duration: "3:48",
            colors: [
                Color(red: 0.89, green: 0.27, blue: 0.5),
                Color(red: 0.27, green: 0.07, blue: 0.28)
            ]
        ),
        Song(
            title: "Sunset Kids",
            artist: "Roosevelt",
            tagline: "Nu-disco glow",
            duration: "4:12",
            colors: [
                Color(red: 0.99, green: 0.74, blue: 0.34),
                Color(red: 0.82, green: 0.34, blue: 0.18)
            ]
        )
    ]

    static let searchCategories: [SearchCategory] = [
        SearchCategory(
            name: "Made for you",
            tagline: "Personal mixes & blends",
            icon: "person.2.wave.2.fill",
            colors: [
                Color(red: 0.95, green: 0.27, blue: 0.55),
                Color(red: 0.57, green: 0.19, blue: 0.74)
            ]
        ),
        SearchCategory(
            name: "Charts",
            tagline: "Top 50 + viral hits",
            icon: "chart.bar.fill",
            colors: [
                Color(red: 0.17, green: 0.78, blue: 0.9),
                Color(red: 0.06, green: 0.37, blue: 0.83)
            ]
        ),
        SearchCategory(
            name: "Live events",
            tagline: "Shows near you",
            icon: "sparkles.tv.fill",
            colors: [
                Color(red: 0.98, green: 0.62, blue: 0.24),
                Color(red: 0.85, green: 0.2, blue: 0.11)
            ]
        ),
        SearchCategory(
            name: "Podcasts",
            tagline: "Stories & talk",
            icon: "dot.radiowaves.left.and.right",
            colors: [
                Color(red: 0.28, green: 0.91, blue: 0.58),
                Color(red: 0.08, green: 0.56, blue: 0.38)
            ]
        ),
        SearchCategory(
            name: "Wellness",
            tagline: "Meditation & calm",
            icon: "leaf.fill",
            colors: [
                Color(red: 0.4, green: 0.71, blue: 0.98),
                Color(red: 0.21, green: 0.33, blue: 0.84)
            ]
        ),
        SearchCategory(
            name: "Discover",
            tagline: "Fresh weekly finds",
            icon: "globe.europe.africa.fill",
            colors: [
                Color(red: 0.95, green: 0.3, blue: 0.79),
                Color(red: 0.5, green: 0.17, blue: 0.63)
            ]
        )
    ]

    static let libraryCollections: [LibraryCollection] = [
        LibraryCollection(
            title: "Liked Songs",
            subtitle: "Playlist · 432 songs",
            meta: "Updated today",
            icon: "heart.fill",
            colors: [
                Color(red: 0.9, green: 0.35, blue: 0.78),
                Color(red: 0.39, green: 0.09, blue: 0.65)
            ],
            type: .playlists,
            isPinned: true,
            playlist: nil
        ),
        LibraryCollection(
            title: "Neon Drive",
            subtitle: "Playlist · Synthwave",
            meta: "Updated yesterday",
            icon: "music.note.list",
            colors: [
                Color(red: 0.98, green: 0.47, blue: 0.43),
                Color(red: 0.58, green: 0.12, blue: 0.4)
            ],
            type: .playlists,
            isPinned: false,
            playlist: nil
        ),
        LibraryCollection(
            title: "Midnight City",
            subtitle: "Album · M83",
            meta: "23 songs",
            icon: "sparkles",
            colors: [
                Color(red: 0.43, green: 0.16, blue: 0.94),
                Color(red: 0.15, green: 0.08, blue: 0.34)
            ],
            type: .albums,
            isPinned: false,
            playlist: nil
        ),
        LibraryCollection(
            title: "Offline",
            subtitle: "Downloads · 28 items",
            meta: "Available offline",
            icon: "arrow.down.circle.fill",
            colors: [
                Color(red: 0.22, green: 0.77, blue: 0.96),
                Color(red: 0.1, green: 0.34, blue: 0.82)
            ],
            type: .downloads,
            isPinned: false,
            playlist: nil
        ),
        LibraryCollection(
            title: "Wave Breaker",
            subtitle: "Podcast · 112 episodes",
            meta: "New episode",
            icon: "mic.fill",
            colors: [
                Color(red: 0.08, green: 0.58, blue: 0.84),
                Color(red: 0.03, green: 0.26, blue: 0.5)
            ],
            type: .podcasts,
            isPinned: false,
            playlist: nil
        ),
        LibraryCollection(
            title: "Future Tense",
            subtitle: "Album · Magdalena Bay",
            meta: "2025",
            icon: "circle.hexagonpath",
            colors: [
                Color(red: 0.78, green: 0.45, blue: 0.98),
                Color(red: 0.34, green: 0.15, blue: 0.62)
            ],
            type: .albums,
            isPinned: false,
            playlist: nil
        ),
        LibraryCollection(
            title: "Nu Jazz Daily",
            subtitle: "Playlist · 56 songs",
            meta: "Refreshed weekly",
            icon: "guitars.fill",
            colors: [
                Color(red: 0.29, green: 0.91, blue: 0.79),
                Color(red: 0.08, green: 0.54, blue: 0.7)
            ],
            type: .playlists,
            isPinned: false,
            playlist: nil
        ),
        LibraryCollection(
            title: "Artist Mix",
            subtitle: "Artist · Modular Dreams",
            meta: "Following",
            icon: "person.crop.circle.badge.checkmark",
            colors: [
                Color(red: 0.96, green: 0.55, blue: 0.22),
                Color(red: 0.68, green: 0.2, blue: 0.12)
            ],
            type: .artists,
            isPinned: false,
            playlist: nil
        )
    ]

    static func playlistTracks(for playlist: Playlist) -> [Song] {
        let pool = (trendingSongs + additionalSongs).shuffled()
        return Array(pool.prefix(8))
    }
}

extension DateFormatter {
    static let playlistFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter
    }()
}

// MARK: - Modifiers

struct GlassCardModifier: ViewModifier {
    var cornerRadius: CGFloat = 28

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 20, y: 16)
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCardModifier(cornerRadius: cornerRadius))
    }
}

#Preview {
    ContentView()
}

struct HomeProfileHeader: View {
    let onTap: () -> Void

    var body: some View {
        ProfileBubble(size: 34, action: onTap)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeCategoryBar: View {
    let categories: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selection = category
                    } label: {
                        Text(category)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(selection == category ? Color.white : Color.white.opacity(0.08))
                            )
                            .foregroundStyle(selection == category ? Color.black : Color.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct HomePlaylistGrid: View {
    let playlists: [Playlist]
    let onSelect: (Playlist) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        let displayed = Array(playlists.prefix(8))

        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(displayed) { playlist in
                let isLiked = playlist.isLikedSongs
                Button {
                    onSelect(playlist)
                } label: {
                    HStack(spacing: 10) {
                        CoverImageView(
                            imageURL: playlist.imageURL,
                            size: 48,
                            cornerRadius: 14,
                            gradient: playlist.gradient,
                            overlayIcon: isLiked ? "heart.fill" : nil
                        )
                        Text(isLiked ? "Liked Songs" : playlist.title)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 54)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct CoverImageView: View {
    let imageURL: URL?
    var uiImage: UIImage? = nil
    let size: CGFloat
    let cornerRadius: CGFloat
    let gradient: LinearGradient
    var overlayIcon: String? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(gradient)

            if let uiImage {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Color.clear
                    case .empty:
                        Color.white.opacity(0.05)
                    @unknown default:
                        Color.clear
                    }
                }
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }

            if let overlayIcon {
                Image(systemName: overlayIcon)
                    .font(.system(size: size * 0.35, weight: .bold))
                    .foregroundStyle(.white)
                    .shadow(radius: 6)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.8)
        )
    }
}

enum Haptics {
    #if os(iOS)
    private static let supportsHaptics: Bool = {
        if #available(iOS 13.0, *) {
            return CHHapticEngine.capabilitiesForHardware().supportsHaptics
        }
        return false
    }()
    #else
    private static let supportsHaptics = false
    #endif

    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if os(iOS)
        guard supportsHaptics else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
        #endif
    }
}

struct HomeReleaseCard: View {
    let song: Song
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("New release from")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
            Text(song.artist)
                .font(.title3.bold())

            Button(action: action) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(song.gradient)
                    .frame(height: 140)
                    .overlay(
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(song.title)
                                    .font(.headline.bold())
                                Text(song.tagline)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.title2)
                                .padding()
                                .background(Color.white.opacity(0.2), in: Circle())
                        }
                        .padding()
                    )
            }
            .buttonStyle(.plain)
        }
    }
}
