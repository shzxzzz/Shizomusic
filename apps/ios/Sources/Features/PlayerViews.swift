import SwiftUI

struct MiniPlayerView: View {
    @Binding var isPlaying: Bool
    let openPlayer: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openPlayer) {
                HStack(spacing: 12) {
                    ArtworkView(style: .hero)
                        .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Night Drive")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text("Neon Valley")
                            .font(.caption)
                            .foregroundStyle(ShizoPalette.textSecondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("player.open"))

            Button { isPlaying.toggle() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? Text("player.pause") : Text("player.play"))

            Button(action: {}) {
                Image(systemName: "forward.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("player.next"))
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(ShizoPalette.strokeStrong, lineWidth: 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(ShizoPalette.backgroundElevated.opacity(0.92))
    }
}

struct NowPlayingView: View {
    @Binding var isPlaying: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [ShizoPalette.accentDeep.opacity(0.45), ShizoPalette.background, ShizoPalette.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.down")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.08), in: Circle())
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Text("player.now_playing")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(ShizoPalette.textSecondary)
                        Text("track.source.local")
                            .font(.caption2)
                            .foregroundStyle(ShizoPalette.textTertiary)
                    }

                    Spacer()

                    Button(action: {}) {
                        Image(systemName: "ellipsis")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 42)
                            .background(.white.opacity(0.08), in: Circle())
                    }
                }

                Spacer(minLength: 0)

                ArtworkView(style: .hero)
                    .aspectRatio(1, contentMode: .fit)
                    .shadow(color: ShizoPalette.accent.opacity(0.22), radius: 35, y: 18)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Night Drive")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.white)
                            Text("Neon Valley")
                                .font(.body)
                                .foregroundStyle(ShizoPalette.textSecondary)
                        }

                        Spacer()

                        Button(action: {}) {
                            Image(systemName: "heart.fill")
                                .font(.title3)
                                .foregroundStyle(ShizoPalette.accent)
                        }
                    }

                    ProgressView(value: 0.46)
                        .tint(.white)
                        .padding(.top, 16)

                    HStack {
                        Text("1:42")
                        Spacer()
                        Text("−2:03")
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(ShizoPalette.textTertiary)
                }

                HStack(spacing: 0) {
                    PlayerControl(systemImage: "shuffle", size: 18)
                    Spacer()
                    PlayerControl(systemImage: "backward.fill", size: 27)
                    Spacer()

                    Button { isPlaying.toggle() } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 27, weight: .bold))
                            .foregroundStyle(ShizoPalette.ink)
                            .frame(width: 72, height: 72)
                            .background(.white, in: Circle())
                    }
                    .accessibilityLabel(isPlaying ? Text("player.pause") : Text("player.play"))

                    Spacer()
                    PlayerControl(systemImage: "forward.fill", size: 27)
                    Spacer()
                    PlayerControl(systemImage: "repeat", size: 18)
                }

                HStack {
                    Label("player.device", systemImage: "iphone")
                    Spacer()
                    Image(systemName: "list.bullet")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShizoPalette.textSecondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .preferredColorScheme(.dark)
    }
}

private struct PlayerControl: View {
    let systemImage: String
    let size: CGFloat

    var body: some View {
        Button(action: {}) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 54)
        }
    }
}
