import SwiftUI

struct LibraryView: View {
    @State private var isPlaying = true
    @State private var isFavorite = false
    @State private var isShuffleEnabled = false
    @State private var progress = 0.41

    var body: some View {
        GeometryReader { geometry in
            let horizontalPadding: CGFloat = 28
            let availableWidth = geometry.size.width - horizontalPadding * 2
            let artworkSize = min(availableWidth, geometry.size.height * 0.44)

            ZStack {
                PlayerBackground()

                VStack(alignment: .leading, spacing: 0) {
                    playerHeader

                    Spacer(minLength: 18)

                    albumArtwork(size: artworkSize)
                        .frame(maxWidth: .infinity)

                    Spacer(minLength: 22)

                    trackDetails

                    Spacer(minLength: 18)

                    progressSection

                    Spacer(minLength: 20)

                    controls
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 18)
                .padding(.bottom, 12)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var playerHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("player.now_playing")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .tracking(0.7)
                .foregroundStyle(.white.opacity(0.72))

            HStack(spacing: 12) {
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

                Spacer()

                Button("player.queue", action: {})
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .buttonStyle(.plain)
            }
        }
    }

    private func albumArtwork(size: CGFloat) -> some View {
        Image("MistyLake")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(.white.opacity(0.38), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 20, y: 12)
            .accessibilityLabel(Text("player.artwork"))
    }

    private var trackDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("player.track_title")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)

            Text("player.artist")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.67))
                .lineLimit(1)
        }
    }

    private var progressSection: some View {
        VStack(spacing: 9) {
            PlayerProgressView(progress: $progress)
                .frame(height: 18)

            HStack {
                Text(verbatim: "1:32")
                Spacer()
                Text(verbatim: "3:48")
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
                action: {}
            )

            Spacer()

            Button {
                isPlaying.toggle()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(Color(red: 0.37, green: 0.46, blue: 0.52))
                    .frame(width: 62, height: 62)
                    .background(.white, in: Circle())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? Text("player.pause") : Text("player.play"))

            Spacer()

            PlayerControlButton(
                systemImage: "forward.fill",
                accessibilityLabel: "player.next",
                action: {}
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
        .frame(height: 84)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }
}

private struct PlayerBackground: View {
    var body: some View {
        ZStack {
            Image("MistyLake")
                .resizable()
                .scaledToFill()
                .blur(radius: 55)
                .scaleEffect(1.24)

            Color(red: 0.39, green: 0.49, blue: 0.56)
                .opacity(0.72)

            LinearGradient(
                colors: [.white.opacity(0.10), .clear, .black.opacity(0.08)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct PlayerProgressView: View {
    @Binding var progress: Double

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
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
