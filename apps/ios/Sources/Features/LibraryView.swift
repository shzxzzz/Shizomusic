import SwiftUI

struct LibraryView: View {
    @State private var selectedTab: AppTab = .player
    @StateObject private var playback = MockPlaybackState()

    var body: some View {
        TabView(selection: $selectedTab) {
            PlayerScreen()
                .tag(AppTab.player)
                .tabItem {
                    Label("tab.player", systemImage: "play.circle.fill")
                }

            MusicLibraryView(onOpenPlayer: { selectedTab = .player })
                .tag(AppTab.library)
                .tabItem {
                    Label("tab.library", systemImage: "square.stack.fill")
                }
        }
        .tint(.white)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .preferredColorScheme(.dark)
        .environmentObject(playback)
    }
}

private enum AppTab: Hashable {
    case player
    case library
}

private struct PlayerScreen: View {
    @EnvironmentObject private var playback: MockPlaybackState

    @State private var isFavorite = false
    @State private var isShuffleEnabled = false
    @State private var progress = 0.41

    var body: some View {
        ZStack {
            PlayerBackground(artworkName: playback.currentTrack.artworkName)

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
        }
        .animation(.easeInOut(duration: 0.45), value: playback.currentTrack.id)
        .onChange(of: playback.currentTrack.id) {
            progress = 0.08
            isFavorite = false
        }
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
                Button("player.queue", action: {})
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .buttonStyle(.plain)
            }

            Button(action: {}) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 13, weight: .semibold))

                    Text("player.playlist")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private func albumArtwork(size: CGFloat) -> some View {
        ZStack {
            Image(playback.currentTrack.artworkName)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .id(playback.currentTrack.artworkName)
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
            PlayerProgressView(progress: $progress)
                .frame(height: 18)

            HStack {
                Text(verbatim: formattedTime(Int(Double(playback.currentTrack.durationSeconds) * progress)))
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
                systemImage: isFavorite ? "heart.fill" : "heart",
                accessibilityLabel: "player.favorite",
                isActive: isFavorite,
                action: { isFavorite.toggle() }
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
                systemImage: "shuffle",
                accessibilityLabel: "player.shuffle",
                isActive: isShuffleEnabled,
                action: { isShuffleEnabled.toggle() }
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

private struct PlayerBackground: View {
    let artworkName: String

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.16)
                    .blur(radius: 52)
                    .id(artworkName)
                    .transition(.opacity)

                Color(red: 0.34, green: 0.43, blue: 0.49)
                    .opacity(0.58)

                LinearGradient(
                    colors: [.white.opacity(0.09), .clear, .black.opacity(0.16)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .ignoresSafeArea()
    }
}

private struct PlayerProgressView: View {
    @Binding var progress: Double

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
                        progress = min(max(value.location.x / width, 0), 1)
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
                .foregroundStyle(isActive ? .white : .white.opacity(0.84))
                .frame(width: 34, height: 48)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
