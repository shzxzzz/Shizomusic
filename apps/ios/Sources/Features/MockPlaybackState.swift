import SwiftUI

struct MockPlayableTrack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let durationSeconds: Int
    let artworkName: String
}

@MainActor
final class MockPlaybackState: ObservableObject {
    @Published private(set) var currentTrack: MockPlayableTrack
    @Published private(set) var queue: [MockPlayableTrack]
    @Published var isPlaying = true

    init() {
        let initialQueue = [
            MockPlayableTrack(
                id: "pulse-of-silence",
                title: "Пульс тишины",
                artist: "Эхо Внутри",
                durationSeconds: 228,
                artworkName: "MistyLake"
            ),
            MockPlayableTrack(
                id: "northern-light",
                title: "Северный свет",
                artist: "Северное течение",
                durationSeconds: 264,
                artworkName: "AuroraShore"
            ),
            MockPlayableTrack(
                id: "dancing-in-flames",
                title: "Dancing In The Flames",
                artist: "The Weeknd",
                durationSeconds: 242,
                artworkName: "ArtistHero"
            ),
            MockPlayableTrack(
                id: "rumble",
                title: "Rumble",
                artist: "Skrillex, Fred again..",
                durationSeconds: 146,
                artworkName: "AuroraShore"
            ),
            MockPlayableTrack(
                id: "open-hearts",
                title: "Open Hearts",
                artist: "The Weeknd",
                durationSeconds: 229,
                artworkName: "MistyLake"
            ),
            MockPlayableTrack(
                id: "in-your-eyes",
                title: "In Your Eyes",
                artist: "The Weeknd",
                durationSeconds: 237,
                artworkName: "ArtistHero"
            )
        ]

        self.queue = initialQueue
        self.currentTrack = initialQueue[0]
    }

    func play(_ track: MockPlayableTrack) {
        if !queue.contains(where: { $0.id == track.id }) {
            queue.append(track)
        }

        currentTrack = track
        isPlaying = true
    }

    func togglePlayPause() {
        isPlaying.toggle()
    }

    func next() {
        guard let index = queue.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        currentTrack = queue[(index + 1) % queue.count]
        isPlaying = true
    }

    func previous() {
        guard let index = queue.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        currentTrack = queue[(index - 1 + queue.count) % queue.count]
        isPlaying = true
    }

    var upcomingTracks: [MockPlayableTrack] {
        guard let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id }) else {
            return queue
        }

        let nextIndex = queue.index(after: currentIndex)
        guard nextIndex < queue.endIndex else { return [] }
        return Array(queue[nextIndex...])
    }

    func moveUpcoming(fromOffsets source: IndexSet, toOffset destination: Int) {
        guard let currentIndex = queue.firstIndex(where: { $0.id == currentTrack.id }) else { return }
        let startIndex = queue.index(after: currentIndex)
        guard startIndex < queue.endIndex else { return }

        var upcoming = Array(queue[startIndex...])
        upcoming.move(fromOffsets: source, toOffset: destination)
        queue.replaceSubrange(startIndex..., with: upcoming)
    }
}
