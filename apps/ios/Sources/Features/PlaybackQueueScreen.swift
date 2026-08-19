import SwiftUI

struct PlaybackQueueScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: MockPlaybackState

    var body: some View {
        NavigationStack {
            List {
                Section("queue.now_playing") {
                    QueueTrackRow(
                        track: playback.currentTrack,
                        isCurrent: true,
                        onTap: nil
                    )
                }

                Section("queue.up_next") {
                    if playback.upcomingTracks.isEmpty {
                        Text("queue.empty")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(playback.upcomingTracks) { track in
                            QueueTrackRow(
                                track: track,
                                isCurrent: false,
                                onTap: { playback.play(track) }
                            )
                        }
                        .onMove(perform: playback.moveUpcoming)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(QueueBackground())
            .environment(\.editMode, .constant(.active))
            .navigationTitle("queue.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("queue.done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct QueueTrackRow: View {
    let track: MockPlayableTrack
    let isCurrent: Bool
    let onTap: (() -> Void)?

    var body: some View {
        Group {
            if let onTap {
                Button(action: onTap) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }
        }
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.white.opacity(0.08))
        .accessibilityLabel(
            Text(verbatim: "\(track.title), \(track.artist), \(formattedDuration(track.durationSeconds))")
        )
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            if isCurrent {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(width: 16)
                    .accessibilityHidden(true)
            }

            TrackArtworkView(artworkURL: track.artworkURL, fallbackName: track.artworkName)
                .scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: track.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? .green : .white)
                    .lineLimit(1)

                Text(verbatim: track.artist)
                    .font(.system(size: 11, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(verbatim: formattedDuration(track.durationSeconds))
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.52))
        }
        .contentShape(Rectangle())
        .frame(minHeight: 60)
    }

    private func formattedDuration(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}

private struct QueueBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.026, green: 0.028, blue: 0.036)
            LinearGradient(
                colors: [.purple.opacity(0.12), .clear, .black.opacity(0.18)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

#Preview("Playback queue") {
    PlaybackQueueScreen()
        .environmentObject(MockPlaybackState())
}
