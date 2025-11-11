//
//  ContentView.swift
//  spotify-liquid-glass
//
//  Created by Egor Baranov on 11/11/2025.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var homePath = NavigationPath()
    @State private var libraryPath = NavigationPath()
    @State private var nowPlaying: Song?
    @State private var showPlayerFullScreen = false
    @State private var playerDetent: PresentationDetent = .fraction(1.0)

    var body: some View {
        ZStack(alignment: .bottom) {
            LiquidGlassBackground()

            TabView(selection: $selectedTab) {
                NavigationStack(path: $homePath) {
                    HomeView(
                        onPlaylistSelect: pushPlaylist,
                        onSongSelect: handleSongSelection
                    )
                    .navigationDestination(for: PlaylistDetail.self) { detail in
                        PlaylistDetailScreen(
                            detail: detail,
                            onSongSelect: { song in
                                handleSongSelection(song)
                            }
                        )
                    }
                }
                .tabItem {
                    Image(systemName: AppTab.home.icon)
                    Text(AppTab.home.title)
                }
                .tag(AppTab.home)

                SearchView()
                    .tabItem {
                        Image(systemName: AppTab.search.icon)
                        Text(AppTab.search.title)
                    }
                    .tag(AppTab.search)

                NavigationStack(path: $libraryPath) {
                    LibraryView(onCollectionSelect: handleLibraryCollectionSelection)
                        .navigationDestination(for: PlaylistDetail.self) { detail in
                            PlaylistDetailScreen(
                                detail: detail,
                                onSongSelect: { song in
                                    handleSongSelection(song)
                                }
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

            if let song = nowPlaying {
                MiniPlayerView(
                    song: song,
                    onExpand: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        showPlayerFullScreen = true
                    },
                    onClose: {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                            nowPlaying = nil
                            showPlayerFullScreen = false
                        }
                    }
                )
                .padding(.horizontal, 24)
                .padding(.bottom, miniPlayerBottomPadding)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showPlayerFullScreen) {
            if let song = nowPlaying {
                PlayerFullScreenView(song: song) {
                    showPlayerFullScreen = false
                }
                .presentationDetents([.fraction(1.0), .fraction(0.85)], selection: $playerDetent)
                .presentationDragIndicator(.visible)
                .onAppear {
                    playerDetent = .fraction(1.0)
                }
            }
        }
    }

    private func pushPlaylist(_ playlist: Playlist) {
        let detail = PlaylistDetail(
            playlist: playlist,
            songs: DemoData.playlistTracks(for: playlist)
        )

        switch selectedTab {
        case .library:
            libraryPath.append(detail)
        default:
            homePath.append(detail)
        }
    }

    private func handleSongSelection(_ song: Song) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            nowPlaying = song
        }
    }

    private func handleLibraryCollectionSelection(_ collection: LibraryCollection) {
        let playlist = Playlist(
            title: collection.title,
            subtitle: collection.subtitle,
            descriptor: collection.meta,
            colors: collection.colors
        )
        pushPlaylist(playlist)
    }
    private var miniPlayerBottomPadding: CGFloat {
        max(safeAreaBottomInset + 56, 70)
    }

    private var safeAreaBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
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
    let onPlaylistSelect: (Playlist) -> Void
    let onSongSelect: (Song) -> Void

    private let hero = DemoData.heroSong
    private let mixes = DemoData.dailyMixes
    private let quick = DemoData.quickPicks
    private let trending = DemoData.trendingSongs

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                GreetingHeader(title: "Good evening", subtitle: "Hand-picked mixes to keep you in flow.")
                NowPlayingCard(song: hero)

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
    }
}

struct SearchView: View {
    @State private var query = ""
    private let categories = DemoData.searchCategories

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 32) {
                GreetingHeader(title: "Search", subtitle: "Find artists, songs or podcasts.")
                LiquidSearchField(text: $query)

                SectionHeader(title: "Browse all", subtitle: "Genres & moods")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 18), count: 2), spacing: 18) {
                    ForEach(categories) { category in
                        SearchCategoryCard(category: category)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 54)
            .padding(.bottom, 160)
        }
    }
}

struct LibraryView: View {
    let onCollectionSelect: (LibraryCollection) -> Void
    @State private var selectedFilter: LibraryFilter = .all
    @State private var layoutStyle: LibraryLayout = .grid

    private var orderedCollections: [LibraryCollection] {
        DemoData.libraryCollections.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned {
                return lhs.isPinned && !rhs.isPinned
            }
            return lhs.title < rhs.title
        }
    }

    private var filteredCollections: [LibraryCollection] {
        guard selectedFilter != .all else { return orderedCollections }
        return orderedCollections.filter { $0.type == selectedFilter }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                LibraryTopBar(
                    title: "Your Library",
                    subtitle: "Everything you've saved and downloaded."
                )

                LibraryFilters(selected: $selectedFilter)

                HStack {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Label("Recents", systemImage: "arrow.up.arrow.down")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        layoutStyle.toggle()
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
            .padding(.top, 0)
            .padding(.bottom, 160)
        }
    }
}

// MARK: - Shared UI

struct GreetingHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.largeTitle.bold())
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.72))
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
        VStack(alignment: .leading, spacing: 12) {
            Text(playlist.title)
                .font(.headline.weight(.semibold))
            Text(playlist.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(2)
            Spacer()
            Label(playlist.descriptor, systemImage: "sparkles")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(24)
        .frame(width: 220, height: 180, alignment: .leading)
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
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(playlist.gradient)
                .frame(height: 120)
                .overlay(
                    Image(systemName: "music.note.waveform")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.92))
                )
                .shadow(color: .black.opacity(0.2), radius: 12, y: 8)

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
    let detail: PlaylistDetail
    let onSongSelect: (Song) -> Void

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
                    PlaylistHeader(detail: detail)
                    PlaylistActionRow()

                    VStack(spacing: 18) {
                        ForEach(Array(detail.songs.enumerated()), id: \.element.id) { index, song in
                            PlaylistSongRow(position: index + 1, song: song) {
                                onSongSelect(song)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(detail.playlist.gradient)
                .frame(width: coverSize, height: coverSize)
                .overlay(
                    Image(systemName: "music.note")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                )
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.bottom, 24)

            Text(detail.playlist.title)
                .font(.largeTitle.bold())
                .padding(.bottom, 4)

            HStack(spacing: 12) {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text("F1")
                            .font(.caption.bold())
                    )

                VStack(alignment: .leading, spacing: 0) {
                    Text(detail.playlist.subtitle)
                        .font(.subheadline.weight(.semibold))
                    Text("Album • \(DateFormatter.playlistFormatter.string(from: Date()))")
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
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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
                Text(String(format: "%02d", position))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))

                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(song.gradient)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundStyle(.white.opacity(0.85))
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
    let song: Song
    let onExpand: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(song.gradient)
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "waveform.path.ecg")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white.opacity(0.9))
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
                // placeholder for playback toggle
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "play.fill")
                    .font(.headline.weight(.bold))
            }

            Button(action: onClose) {
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

struct PlayerFullScreenView: View {
    let song: Song
    let onClose: () -> Void
    @State private var progress: Double = 0.25

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

                Spacer()

                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 320)
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: 64, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.4))
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

                VStack(spacing: 18) {
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(height: 6)
                        .padding(.horizontal, 12)
                        .overlay(
                            Capsule()
                                .fill(Color.white)
                                .frame(width: 200, height: 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        )

                    HStack {
                        Text(timeString(progress * 240))
                        Spacer()
                        Text(timeString(240))
                    }
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                }
                .padding(.horizontal, 36)

                HStack(spacing: 28) {
                    GlassControlButton(systemName: "backward.fill")
                    GlassControlButton(systemName: progress > 0.01 ? "pause.fill" : "play.fill", isPrimary: true)
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

    private func timeString(_ seconds: Double) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct GlassControlButton: View {
    let systemName: String
    var size: CGFloat = 64
    var isPrimary: Bool = false

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
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

struct LibraryRow: View {
    let collection: LibraryCollection

    var body: some View {
        HStack(spacing: 16) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(collection.gradient)
                .frame(width: 58, height: 58)
                .overlay(
                    Image(systemName: collection.icon)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
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
                    .frame(width: 48, height: 48)
                    .overlay(
                        Text("EB")
                            .font(.headline.weight(.bold))
                    )
                Spacer()

                HStack(spacing: 16) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.title3.weight(.semibold))
                    }

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(.top, 28)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(collection.gradient)
                .frame(height: 140)
                .overlay(
                    VStack {
                        if collection.isPinned {
                            Image(systemName: "heart.fill")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                        } else {
                            Image(systemName: collection.icon)
                                .font(.title.weight(.bold))
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }
                )

            Text(collection.title)
                .font(.headline)

            Text(collection.subtitle)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
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


// MARK: - Data Models

struct Song: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String
    let tagline: String
    let duration: String
    let colors: [Color]

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
    let title: String
    let subtitle: String
    let descriptor: String
    let colors: [Color]

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
            isPinned: true
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
            isPinned: false
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
            isPinned: false
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
            isPinned: false
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
            isPinned: false
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
            isPinned: false
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
            isPinned: false
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
            isPinned: false
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
