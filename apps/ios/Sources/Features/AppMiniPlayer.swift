import SwiftUI

struct AppMiniPlayer: View {
    @EnvironmentObject private var playback: MockPlaybackState

    let onOpenPlayer: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onOpenPlayer) {
                HStack(spacing: 10) {
                    Image(playback.currentTrack.artworkName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: playback.currentTrack.title)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        Text(verbatim: playback.currentTrack.artist)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.54))
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("mini_player.open"))

            Spacer(minLength: 4)

            Button(action: {}) {
                Image(systemName: "heart")
                    .frame(width: 30, height: 44)
            }
            .accessibilityLabel(Text("player.favorite"))

            Button(action: playback.togglePlayPause) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 30, height: 44)
            }
            .accessibilityLabel(playback.isPlaying ? Text("player.pause") : Text("player.play"))

            Button(action: playback.next) {
                Image(systemName: "forward.fill")
                    .frame(width: 30, height: 44)
            }
            .accessibilityLabel(Text("player.next"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .frame(height: 64)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }
}
