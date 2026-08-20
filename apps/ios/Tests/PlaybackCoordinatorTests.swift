import Foundation
import Testing

@testable import ShizoMusic

struct PlaybackCoordinatorTests {
    @Test @MainActor
    func queueNavigationAndRepeatModesAreDeterministic() {
        let first = PlayableTrack(
            id: "first",
            title: "First",
            artist: "Artist",
            durationSeconds: 60,
            artworkName: "MistyLake"
        )
        let second = PlayableTrack(
            id: "second",
            title: "Second",
            artist: "Artist",
            durationSeconds: 90,
            artworkName: "MistyLake"
        )
        let playback = PlaybackCoordinator(restoresQueue: false)

        playback.play([first, second])
        #expect(playback.currentTrack.id == first.id)
        #expect(playback.upcomingTracks == [second])

        playback.next()
        #expect(playback.currentTrack.id == second.id)

        playback.previous()
        #expect(playback.currentTrack.id == first.id)

        playback.cycleRepeatMode()
        #expect(playback.repeatMode == .all)
        playback.cycleRepeatMode()
        #expect(playback.repeatMode == .one)
        playback.cycleRepeatMode()
        #expect(playback.repeatMode == .off)
    }

    @Test @MainActor
    func playNextInsertsImmediatelyAfterCurrentTrack() {
        let tracks = (1...3).map {
            PlayableTrack(
                id: "\($0)",
                title: "Track \($0)",
                artist: "Artist",
                durationSeconds: 60,
                artworkName: "MistyLake"
            )
        }
        let inserted = PlayableTrack(
            id: "inserted",
            title: "Inserted",
            artist: "Artist",
            durationSeconds: 60,
            artworkName: "MistyLake"
        )
        let playback = PlaybackCoordinator(restoresQueue: false)

        playback.play(tracks)
        playback.playNext(inserted)

        #expect(playback.upcomingTracks.first == inserted)
    }

    @Test @MainActor
    func shuffleChangesFutureQueueWithoutMovingCurrentTrack() {
        let tracks = (1...5).map {
            PlayableTrack(
                id: "shuffle-\($0)",
                title: "Track \($0)",
                artist: "Artist",
                durationSeconds: 60,
                artworkName: "MistyLake"
            )
        }
        let playback = PlaybackCoordinator(restoresQueue: false)

        playback.play(tracks)
        let originalUpcoming = playback.upcomingTracks
        playback.toggleShuffle()

        #expect(playback.currentTrack == tracks[0])
        #expect(playback.isShuffleEnabled)
        #expect(playback.upcomingTracks != originalUpcoming)
        #expect(Set(playback.upcomingTracks) == Set(originalUpcoming))
    }

    @Test @MainActor
    func historyIsSeparateFromUpcomingQueue() {
        let tracks = makeTracks(3, prefix: "history")
        let playback = PlaybackCoordinator(restoresQueue: false)

        playback.play(tracks)
        playback.next()

        #expect(playback.currentTrack == tracks[1])
        #expect(playback.playbackHistory == [tracks[0]])
        #expect(playback.upcomingTracks == [tracks[2]])

        playback.previous()
        #expect(playback.currentTrack == tracks[0])
        #expect(playback.playbackHistory.isEmpty)
    }

    @Test @MainActor
    func upcomingItemsCanBeRemovedAndCleared() {
        let tracks = makeTracks(4, prefix: "remove")
        let playback = PlaybackCoordinator(restoresQueue: false)

        playback.play(tracks)
        playback.removeUpcoming(atOffsets: IndexSet(integer: 1))
        #expect(playback.upcomingTracks == [tracks[1], tracks[3]])

        playback.clearUpcoming()
        #expect(playback.upcomingTracks.isEmpty)
        #expect(playback.currentTrack == tracks[0])
    }

    private func makeTracks(_ count: Int, prefix: String) -> [PlayableTrack] {
        (1...count).map {
            PlayableTrack(
                id: "\(prefix)-\($0)",
                title: "Track \($0)",
                artist: "Artist",
                durationSeconds: 60,
                artworkName: "MistyLake"
            )
        }
    }
}
