import SwiftUI

struct LibraryView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .player
    @StateObject private var playback = PlaybackCoordinator()
    @StateObject private var localLibrary = LocalMediaLibrary()
    @StateObject private var playlistStore = PlaylistStore()

    var body: some View {
        TabView(selection: $selectedTab) {
            PlayerNavigationRoot(onOpenLibrary: { selectedTab = .library })
                .tag(AppTab.player)
                .tabItem {
                    Label("tab.player", systemImage: "play.circle.fill")
                }

            NonPlayerTabShell(onOpenPlayer: { selectedTab = .player }) {
                MusicLibraryView()
            }
                .tag(AppTab.library)
                .tabItem {
                    Label("tab.library", systemImage: "square.stack.fill")
                }

            NonPlayerTabShell(onOpenPlayer: { selectedTab = .player }) {
                SearchScreen()
            }
                .tag(AppTab.search)
                .tabItem {
                    Label("tab.search", systemImage: "magnifyingglass")
                }

            NonPlayerTabShell(onOpenPlayer: { selectedTab = .player }) {
                FriendsScreen()
            }
                .tag(AppTab.friends)
                .tabItem {
                    Label("tab.friends", systemImage: "person.2.fill")
                }
        }
        .tint(.white)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
        .environmentObject(playback)
        .environmentObject(localLibrary)
        .environmentObject(playlistStore)
        .task {
            await localLibrary.scan()
            await playlistStore.load()
            playback.replaceLibrary(localLibrary.tracks)
        }
        .onChange(of: localLibrary.tracks) {
            playback.replaceLibrary(localLibrary.tracks)
            Task { await playlistStore.load() }
        }
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await localLibrary.scan() }
        }
        .sheet(
            item: Binding(
                get: { localLibrary.lastImportReport },
                set: { if $0 == nil { localLibrary.dismissImportReport() } }
            )
        ) { report in
            ImportReportView(report: report)
        }
    }
}

private struct PlayerNavigationRoot: View {
    let onOpenLibrary: () -> Void

    var body: some View {
        NavigationStack {
            PlayerScreen(onOpenLibrary: onOpenLibrary)
                .navigationDestination(for: CollectionDetailDestination.self) { destination in
                    CollectionDetailScreen(destination: destination)
                }
                .navigationDestination(for: ArtistDetailDestination.self) { destination in
                    ArtistDetailScreen(destination: destination)
                }
        }
    }
}

private struct NonPlayerTabShell<Content: View>: View {
    @EnvironmentObject private var playback: PlaybackCoordinator
    let onOpenPlayer: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if playback.hasCurrentTrack {
                    AppMiniPlayer(onOpenPlayer: onOpenPlayer)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 6)
                }
            }
    }
}

private enum AppTab: Hashable {
    case player
    case library
    case search
    case friends
}

private struct PlayerScreen: View {
    @EnvironmentObject private var playback: PlaybackCoordinator
    let onOpenLibrary: () -> Void

    @State private var showsQueue = false

    var body: some View {
        ZStack {
            PlayerBackground(
                artworkName: playback.currentTrack.artworkName,
                artworkURL: playback.currentTrack.artworkURL
            )

            if playback.hasCurrentTrack {
                GeometryReader { geometry in
                let compactLayout = geometry.size.height < 700
                let horizontalPadding: CGFloat = 24
                let contentWidth = min(geometry.size.width - horizontalPadding * 2, 420)
                let artworkRatio = compactLayout ? 0.34 : 0.39
                let artworkSize = min(contentWidth, geometry.size.height * artworkRatio)

                playerContent(
                    contentWidth: contentWidth,
                    artworkSize: artworkSize,
                    compactLayout: compactLayout,
                    availableHeight: geometry.size.height
                )
                .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else {
                EmptyPlayerView(onOpenLibrary: onOpenLibrary)
            }
        }
        .animation(.easeInOut(duration: 0.45), value: playback.currentTrack.id)
        .sheet(isPresented: $showsQueue) {
            PlaybackQueueScreen()
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func playerContent(
        contentWidth: CGFloat,
        artworkSize: CGFloat,
        compactLayout: Bool,
        availableHeight: CGFloat
    ) -> some View {
        let headerGap: CGFloat = compactLayout ? 14 : 20
        let detailsGap: CGFloat = compactLayout ? 16 : 22
        let progressGap: CGFloat = compactLayout ? 14 : 20

        return VStack(alignment: .leading, spacing: 0) {
            playerHeader

            VStack(alignment: .leading, spacing: 0) {
                albumArtwork(size: artworkSize)
                    .frame(maxWidth: .infinity)

                trackDetails
                    .padding(.top, detailsGap)

                progressSection
                    .padding(.top, progressGap)

                if let error = playback.playbackError {
                    PlaybackErrorBanner(message: error, onDismiss: playback.clearPlaybackError)
                        .padding(.top, 10)
                }

                controls
                    .padding(.top, progressGap)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.top, headerGap)
        }
        .frame(width: contentWidth)
        .padding(.top, compactLayout ? 6 : 10)
        .padding(.bottom, compactLayout ? 6 : 10)
        .frame(height: availableHeight, alignment: .top)
    }

    private var playerHeader: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("player.now_playing")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white.opacity(0.72))
                Spacer()
                Button("player.queue", action: { showsQueue = true })
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .buttonStyle(.plain)
            }

            NavigationLink(value: currentPlaylistDestination) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .semibold))

                    Text(verbatim: playback.currentTrack.albumTitle ?? String(localized: "library.offline"))
                        .font(.system(size: 17, weight: .semibold, design: .rounded))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var currentPlaylistDestination: CollectionDetailDestination {
        if let id = playback.currentTrack.releaseID,
           let album = playback.currentTrack.albumTitle,
           !album.isEmpty {
            return .release(id: id, title: album, artist: playback.currentTrack.albumArtist ?? playback.currentTrack.artist)
        }
        return .offline
    }

    private var currentPlaylistArtwork: CollectionHeroArtwork {
        switch playback.currentTrack.artworkName {
        case "MistyLake": .mistyLake
        case "AuroraShore": .sunset
        default: .violet
        }
    }

    private func albumArtwork(size: CGFloat) -> some View {
        ZStack {
            TrackArtworkView(
                artworkURL: playback.currentTrack.artworkURL,
                fallbackName: playback.currentTrack.artworkName
            )
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .id(playback.currentTrack.artworkURL?.absoluteString ?? playback.currentTrack.artworkName)
                .transition(.opacity.combined(with: .scale(scale: 0.985)))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(.white.opacity(0.34), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.26), radius: 18, y: 10)
        .accessibilityLabel(Text("player.artwork"))
    }

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: playback.currentTrack.title)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .id(playback.currentTrack.title)

            Text(verbatim: playback.currentTrack.artist)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.67))
                .lineLimit(1)
                .id(playback.currentTrack.artist)
        }
        .transition(.opacity)
    }

    private var progressSection: some View {
        VStack(spacing: 8) {
            PlayerProgressView(
                progress: playback.progress,
                onSeek: playback.seek(toProgress:)
            )
                .frame(height: 18)

            HStack {
                Text(verbatim: formattedTime(Int(playback.elapsedSeconds)))
                Spacer()
                Text(verbatim: formattedTime(playback.currentTrack.durationSeconds))
            }
            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(.white.opacity(0.68))
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            PlayerControlButton(
                systemImage: "shuffle",
                accessibilityLabel: "player.shuffle",
                isActive: playback.isShuffleEnabled,
                action: playback.toggleShuffle
            )

            Spacer()

            PlayerControlButton(
                systemImage: "backward.fill",
                accessibilityLabel: "player.previous",
                action: playback.previous
            )

            Spacer()

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.34, green: 0.44, blue: 0.50))
                    .frame(width: 60, height: 60)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? Text("player.pause") : Text("player.play"))

            Spacer()

            PlayerControlButton(
                systemImage: "forward.fill",
                accessibilityLabel: "player.next",
                action: playback.next
            )

            Spacer()

            PlayerControlButton(
                systemImage: playback.repeatMode.systemImage,
                accessibilityLabel: "player.repeat",
                isActive: playback.repeatMode != .off,
                action: playback.cycleRepeatMode
            )
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .frame(height: 82)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }

    private func formattedTime(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return "\(minutes):\(remainingSeconds < 10 ? "0" : "")\(remainingSeconds)"
    }
}

private struct EmptyPlayerView: View {
    let onOpenLibrary: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "music.note.house")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.white.opacity(0.8))
            Text("player.empty_title")
                .font(.title2.weight(.semibold))
            Text("player.empty_detail")
                .font(.body)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            Button("player.open_library", action: onOpenLibrary)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .padding(32)
        .frame(maxWidth: 440)
    }
}

private struct PlaybackErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(verbatim: message).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDismiss) { Image(systemName: "xmark") }
                .accessibilityLabel(Text("player.dismiss_error"))
        }
        .foregroundStyle(.white)
        .padding(12)
        .background(.red.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct PlayerBackground: View {
    let artworkName: String
    let artworkURL: URL?
    @State private var palette = ArtworkPalette.fallback

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                TrackArtworkView(artworkURL: artworkURL, fallbackName: artworkName)
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.16)
                    .blur(radius: 64)
                    .opacity(0.34)
                    .saturation(1.35)
                    .id(artworkURL?.absoluteString ?? artworkName)
                    .transition(.opacity)

                palette.base.color.opacity(0.82)

                RadialGradient(
                    colors: [palette.primary.color.opacity(0.74), .clear],
                    center: .topLeading,
                    startRadius: 10,
                    endRadius: geometry.size.height * 0.78
                )

                RadialGradient(
                    colors: [palette.secondary.color.opacity(0.60), .clear],
                    center: .bottomTrailing,
                    startRadius: 20,
                    endRadius: geometry.size.height * 0.72
                )

                LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .black.opacity(0.34)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .task(id: artworkURL?.absoluteString ?? artworkName) {
            let extracted = await ArtworkPaletteExtractor.palette(artworkURL: artworkURL, fallbackName: artworkName)
            withAnimation(.easeInOut(duration: 0.55)) { palette = extracted }
        }
    }
}

private struct PlayerProgressView: View {
    let progress: Double
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            let width = max(geometry.size.width, 1)
            let clampedProgress = min(max(progress, 0), 1)
            let thumbOffset = max(0, min(width - 12, width * clampedProgress - 6))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.24))
                    .frame(height: 3)

                Capsule()
                    .fill(.white)
                    .frame(width: width * clampedProgress, height: 3)

                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                    .offset(x: thumbOffset)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek(min(max(value.location.x / width, 0), 1))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(Text("player.progress"))
        .accessibilityValue(Text("\(Int(progress * 100))%"))
    }
}

private struct PlayerControlButton: View {
    let systemImage: String
    let accessibilityLabel: LocalizedStringKey
    var isActive = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(isActive ? Color.cyan : Color.white.opacity(0.84))
                .frame(width: 34, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
