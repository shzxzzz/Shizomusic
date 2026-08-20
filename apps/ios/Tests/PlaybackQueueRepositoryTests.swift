import Foundation
import Testing

@testable import ShizoMusic

struct PlaybackQueueRepositoryTests {
    @Test func persistsStableItemIdentityAndQueueContext() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("shizomusic-queue-\(UUID().uuidString).sqlite").path
        let database = try LibraryDatabase(path: path)
        let tracks = GRDBTrackRepository(database: database)
        let queue = GRDBPlaybackQueueRepository(database: database)
        let media = ScannedMediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/queue-track.flac"),
            contentHash: "queue-track-hash",
            fileSize: 100,
            modifiedAt: .now,
            format: "flac",
            title: "Queued track",
            artistDisplayName: "Artist",
            artistNames: ["Artist"],
            albumTitle: "Album",
            albumArtist: "Artist",
            duration: 120,
            artworkURL: nil,
            artworkHash: nil
        )
        try await tracks.synchronize(files: [media], scanID: UUID())
        let librarySnapshot = try await tracks.snapshot(sort: .title, filter: .available)
        let track = try #require(librarySnapshot.tracks.first)

        try await queue.save(
            history: [],
            current: track,
            upcoming: [],
            elapsedSeconds: 23,
            shuffleEnabled: true,
            repeatMode: "all",
            context: .release(track.releaseID ?? "release")
        )
        let firstSnapshot = try await queue.load()
        let first = try #require(firstSnapshot)
        let itemID = try #require(first.items.first?.id)

        try await queue.save(
            history: [track],
            current: nil,
            upcoming: [],
            elapsedSeconds: 0,
            shuffleEnabled: false,
            repeatMode: "off",
            context: .offline
        )
        let secondSnapshot = try await queue.load()
        let second = try #require(secondSnapshot)

        #expect(second.items.first?.id == itemID)
        #expect(second.items.first?.status == .history)
        #expect(first.context.kind == .release)
        #expect(first.elapsedSeconds == 23)
    }
}
