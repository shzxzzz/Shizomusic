import Foundation
import Testing

@testable import ShizoMusic

struct ListeningStatisticsRepositoryTests {
    @Test func recordsHistoryQualificationCompletionAndAggregates() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("shizomusic-statistics-\(UUID().uuidString).sqlite").path
        let database = try LibraryDatabase(path: path)
        let tracks = GRDBTrackRepository(database: database)
        let statistics = GRDBListeningStatisticsRepository(database: database)
        let media = ScannedMediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/statistics-track.flac"),
            contentHash: "statistics-track-hash",
            fileSize: 100,
            modifiedAt: .now,
            format: "flac",
            title: "Statistics track",
            artistDisplayName: "Statistics artist",
            artistNames: ["Statistics artist"],
            albumTitle: "Statistics release",
            albumArtist: "Statistics artist",
            duration: 60,
            artworkURL: nil,
            artworkHash: nil
        )
        try await tracks.synchronize(files: [media], scanID: UUID())
        let snapshot = try await tracks.snapshot(sort: .title, filter: .available)
        let track = try #require(snapshot.tracks.first)
        let sessionID = UUID()
        try await statistics.record(.init(sessionID: sessionID, trackID: track.id, kind: .started, position: 0, context: .offline))
        try await statistics.record(.init(sessionID: sessionID, trackID: track.id, kind: .qualified, position: 30, listenedSeconds: 30, context: .offline))
        try await statistics.record(.init(sessionID: sessionID, trackID: track.id, kind: .completed, position: 60, listenedSeconds: 30, context: .offline))

        let result = try await statistics.snapshot(period: .all)
        #expect(result.totalListeningSeconds == 60)
        #expect(result.qualifiedPlays == 1)
        #expect(result.completedPlays == 1)
        #expect(result.history.first?.completed == true)
        #expect(result.topTracks.first?.title == track.title)
        #expect(!result.daily.isEmpty)
        #expect(!result.monthly.isEmpty)
    }
}
