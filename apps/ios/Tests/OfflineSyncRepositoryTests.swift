import Foundation
import Testing

@testable import ShizoMusic

struct OfflineSyncRepositoryTests {
    @Test func playlistChangesCreateAtomicOutboxAndRemoteChangesApply() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("shizomusic-sync-\(UUID().uuidString).sqlite").path
        let database = try LibraryDatabase(path: path)
        let tracks = GRDBTrackRepository(database: database)
        let playlists = GRDBPlaylistRepository(database: database)
        let sync = GRDBOfflineSyncRepository(database: database)
        let media = ScannedMediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/sync-track.flac"), contentHash: "sync-track-hash",
            fileSize: 100, modifiedAt: .now, format: "flac", title: "Synced track",
            artistDisplayName: "Artist", artistNames: ["Artist"], albumTitle: "Release",
            albumArtist: "Artist", duration: 90, artworkURL: nil, artworkHash: nil
        )
        try await tracks.synchronize(files: [media], scanID: UUID())
        let track = try #require(try await tracks.snapshot(sort: .title, filter: .available).tracks.first)

        let playlistID = try await playlists.create(title: "Offline title", coverStyle: .violet)
        let itemID = try await playlists.add(trackID: track.id, to: playlistID)
        let batch = try await sync.readyBatch(limit: 50)
        #expect(batch.map(\.operationType) == [.playlistUpsert, .playlistItemInsert])
        #expect(Set(batch.map(\.id)).count == 2)
        let itemOperation = try #require(batch.first { $0.operationType == .playlistItemInsert })
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let itemPayload = try decoder.decode(PlaylistItemSyncPayload.self, from: Data(itemOperation.payload.utf8))
        #expect(itemPayload.trackId == media.contentHash)
        var overview = try await sync.overview()
        #expect(overview.pendingCount == 2)

        try await sync.markFailed(ids: batch.map(\.id), message: "offline", now: .now)
        overview = try await sync.overview()
        #expect(overview.failedCount == 2)
        try await sync.retryAll()
        overview = try await sync.overview()
        #expect(overview.pendingCount == 2)
        try await sync.markAccepted(ids: batch.map(\.id))

        let updated = Date()
        let payload = PlaylistSyncPayload(
            id: playlistID, title: "Remote winner", coverStyle: PlaylistCoverStyle.sunset.rawValue,
            customCoverData: nil, createdAt: updated.addingTimeInterval(-60), updatedAt: updated, deletedAt: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let change = RemoteSyncChange(
            id: UUID(), cursor: "9", actorDeviceId: UUID(), entityType: .playlist,
            entityId: playlistID.uuidString, operationType: .playlistUpsert,
            payload: String(decoding: try encoder.encode(payload), as: UTF8.self), clientTimestamp: updated
        )
        try await sync.apply(changes: [change], cursor: 9)
        let result = try #require(try await playlists.fetchAll().first)
        #expect(result.title == "Remote winner")
        #expect(result.coverStyle == .sunset)
        #expect(result.syncStatus == .synced)
        #expect(result.items.first?.id == itemID)
        overview = try await sync.overview()
        #expect(overview.cursor == 9)

        let deferredItemID = UUID()
        let deferredPayload = PlaylistItemSyncPayload(
            id: deferredItemID, playlistId: playlistID, trackId: "later-track-hash", rank: 2_048,
            createdAt: updated, updatedAt: updated, deletedAt: nil
        )
        let deferredChangeID = UUID()
        let deferredChange = RemoteSyncChange(
            id: deferredChangeID, cursor: "10", actorDeviceId: UUID(), entityType: .playlistItem,
            entityId: deferredItemID.uuidString, operationType: .playlistItemInsert,
            payload: String(decoding: try encoder.encode(deferredPayload), as: UTF8.self), clientTimestamp: updated
        )
        try await sync.apply(changes: [deferredChange], cursor: 10)
        overview = try await sync.overview()
        #expect(overview.conflictCount == 1)

        let laterMedia = ScannedMediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/later-track.flac"), contentHash: "later-track-hash",
            fileSize: 200, modifiedAt: .now, format: "flac", title: "Later track",
            artistDisplayName: "Artist", artistNames: ["Artist"], albumTitle: "Release",
            albumArtist: "Artist", duration: 120, artworkURL: nil, artworkHash: nil
        )
        try await tracks.synchronize(files: [media, laterMedia], scanID: UUID())
        try await sync.retryDeferredChanges()
        let refreshed = try #require(try await playlists.fetchAll().first)
        #expect(refreshed.items.contains { $0.id == deferredItemID && $0.track.title == laterMedia.title })
        overview = try await sync.overview()
        #expect(overview.conflictCount == 0)
    }
}
