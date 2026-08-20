import Foundation
import Testing

@testable import ShizoMusic

struct PlaylistRepositoryTests {
    @Test func playlistPersistsDuplicatesStableItemsAndFractionalOrder() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("shizomusic-playlist-\(UUID().uuidString).sqlite").path
        let database = try LibraryDatabase(path: path)
        let tracks = GRDBTrackRepository(database: database)
        let playlists = GRDBPlaylistRepository(database: database)
        let media = ScannedMediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/playlist-track.flac"),
            contentHash: "playlist-track-hash",
            fileSize: 100,
            modifiedAt: .now,
            format: "flac",
            title: "Repeat me",
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
        let playlistID = try await playlists.create(title: "Original", coverStyle: .violet)
        let firstID = try await playlists.add(trackID: track.id, to: playlistID)
        let secondID = try await playlists.add(trackID: track.id, to: playlistID)

        var allPlaylists = try await playlists.fetchAll()
        var snapshot = try #require(allPlaylists.first)
        #expect(snapshot.items.map(\.id) == [firstID, secondID])
        #expect(snapshot.items.map(\.track.id) == [track.id, track.id])

        try await playlists.move(itemID: secondID, to: 0)
        try await playlists.rename(id: playlistID, title: "Renamed")
        try await playlists.changeCover(id: playlistID, coverStyle: .sunset)
        allPlaylists = try await playlists.fetchAll()
        snapshot = try #require(allPlaylists.first)
        #expect(snapshot.items.map(\.id) == [secondID, firstID])
        #expect(snapshot.items[0].rank < snapshot.items[1].rank)
        #expect(snapshot.title == "Renamed")
        #expect(snapshot.coverStyle == .sunset)

        try await playlists.delete(id: playlistID)
        allPlaylists = try await playlists.fetchAll()
        #expect(allPlaylists.isEmpty)
    }
}
