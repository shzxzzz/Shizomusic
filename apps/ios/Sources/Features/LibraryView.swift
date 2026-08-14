import SwiftUI

struct LibraryView: View {
    @State private var selectedTab = AppTab.library
    @State private var isPlaying = true
    @State private var isPlayerPresented = false

    var body: some View {
        TabView(selection: $selectedTab) {
            LibraryHomeView(
                isPlaying: $isPlaying,
                openSearch: { selectedTab = .search }
            )
            .tag(AppTab.library)
            .tabItem { Label("tab.library", systemImage: "square.stack.fill") }

            SearchView()
                .tag(AppTab.search)
                .tabItem { Label("tab.search", systemImage: "magnifyingglass") }

            PlaceholderTabView(
                title: "friends.title",
                subtitle: "friends.subtitle",
                systemImage: "person.2.wave.2.fill"
            )
            .tag(AppTab.friends)
            .tabItem { Label("tab.friends", systemImage: "person.2.fill") }

            PlaceholderTabView(
                title: "stats.title",
                subtitle: "stats.subtitle",
                systemImage: "chart.bar.xaxis"
            )
            .tag(AppTab.statistics)
            .tabItem { Label("tab.statistics", systemImage: "chart.bar.fill") }
        }
        .tint(ShizoPalette.accent)
        .toolbarBackground(ShizoPalette.backgroundElevated, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.dark, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            MiniPlayerView(
                isPlaying: $isPlaying,
                openPlayer: { isPlayerPresented = true }
            )
        }
        .sheet(isPresented: $isPlayerPresented) {
            NowPlayingView(isPlaying: $isPlaying)
                .presentationDragIndicator(.visible)
                .presentationBackground(ShizoPalette.background)
        }
        .preferredColorScheme(.dark)
    }
}

private enum AppTab: Hashable {
    case library
    case search
    case friends
    case statistics
}

private struct LibraryHomeView: View {
    @Binding var isPlaying: Bool
    let openSearch: () -> Void

    private let quickAccess = QuickAccessItem.samples
    private let recentTracks = RecentTrack.samples

    var body: some View {
        NavigationStack {
            ZStack {
                ShizoPalette.background.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        header
                        searchButton
                        ContinueListeningCard(isPlaying: $isPlaying)
                        quickAccessSection
                        recentSection
                        offlineBanner
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("home.greeting")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ShizoPalette.textSecondary)

                Text("app.name")
                    .font(.system(size: 31, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }

            Spacer()

            HStack(spacing: 7) {
                Circle()
                    .fill(ShizoPalette.success)
                    .frame(width: 7, height: 7)

                Text("home.offline_ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShizoPalette.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(ShizoPalette.surface, in: Capsule())
            .overlay { Capsule().stroke(ShizoPalette.stroke, lineWidth: 1) }
        }
    }

    private var searchButton: some View {
        Button(action: openSearch) {
            HStack(spacing: 11) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                Text("home.search_prompt")
                    .font(.subheadline)
                Spacer()
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(ShizoPalette.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(ShizoPalette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(ShizoPalette.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("home.search_accessibility")
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "home.quick_access")

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(quickAccess) { item in
                    QuickAccessCard(item: item)
                }
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "home.recently_added", actionTitle: "common.all")

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 14) {
                    ForEach(recentTracks) { track in
                        RecentTrackCard(track: track)
                    }
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 25, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ShizoPalette.accent)

            VStack(alignment: .leading, spacing: 3) {
                Text("home.downloads_title")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("home.downloads_subtitle")
                    .font(.caption)
                    .foregroundStyle(ShizoPalette.textSecondary)
            }

            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(ShizoPalette.textTertiary)
        }
        .padding(16)
        .background(ShizoPalette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct ContinueListeningCard: View {
    @Binding var isPlaying: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("home.continue_listening", systemImage: "waveform")
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.78))

                Spacer()
                Text("track.source.local")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.18), in: Capsule())
            }

            HStack(spacing: 17) {
                ArtworkView(style: .hero)
                    .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 7) {
                    Text("Night Drive")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("Neon Valley")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("track.downloaded")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                }

                Spacer(minLength: 0)

                Button { isPlaying.toggle() } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(ShizoPalette.ink)
                        .frame(width: 52, height: 52)
                        .background(.white, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isPlaying ? Text("player.pause") : Text("player.play"))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.22))
                    Capsule()
                        .fill(.white)
                        .frame(width: proxy.size.width * 0.46)
                }
            }
            .frame(height: 3)

            HStack {
                Text("1:42")
                Spacer()
                Text("−2:03")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(0.64))
        }
        .padding(20)
        .background {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.96, green: 0.28, blue: 0.20), ShizoPalette.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 230)
                    .offset(x: 135, y: -95)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: ShizoPalette.accent.opacity(0.18), radius: 24, y: 12)
    }
}

private struct QuickAccessCard: View {
    let item: QuickAccessItem

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 12) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(item.tint)
                    .frame(width: 38, height: 38)
                    .background(item.tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(ShizoPalette.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ShizoPalette.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(ShizoPalette.stroke, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct RecentTrackCard: View {
    let track: RecentTrack

    var body: some View {
        Button(action: {}) {
            VStack(alignment: .leading, spacing: 10) {
                ArtworkView(style: track.artwork)
                    .frame(width: 148, height: 148)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ShizoPalette.ink)
                            .frame(width: 34, height: 34)
                            .background(.white, in: Circle())
                            .padding(9)
                            .shadow(color: .black.opacity(0.24), radius: 8, y: 4)
                    }
                Text(track.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(track.artist)
                    .font(.caption)
                    .foregroundStyle(ShizoPalette.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 148, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?

    var body: some View {
        HStack {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            if let actionTitle {
                Button(actionTitle, action: {})
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ShizoPalette.accent)
            }
        }
    }
}

private struct QuickAccessItem: Identifiable {
    let id = UUID()
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String
    let tint: Color

    static let samples = [
        QuickAccessItem(title: "quick.favorites", detail: "quick.favorites_count", systemImage: "heart.fill", tint: .pink),
        QuickAccessItem(title: "quick.downloads", detail: "quick.downloads_count", systemImage: "arrow.down", tint: ShizoPalette.accent),
        QuickAccessItem(title: "quick.playlists", detail: "quick.playlists_count", systemImage: "music.note.list", tint: .purple),
        QuickAccessItem(title: "quick.import", detail: "quick.import_detail", systemImage: "plus", tint: .cyan)
    ]
}

private struct RecentTrack: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let artwork: ArtworkStyle

    static let samples = [
        RecentTrack(title: "Falling Up", artist: "Luma", artwork: .violet),
        RecentTrack(title: "Afterglow", artist: "Stereofield", artwork: .sunset),
        RecentTrack(title: "Quiet Signals", artist: "Noah Vale", artwork: .ocean)
    ]
}
