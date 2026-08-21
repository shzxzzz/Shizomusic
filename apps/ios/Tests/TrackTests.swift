import Foundation
import Testing

@testable import ShizoMusic

struct TrackTests {
    @Test func domainTrackHasStableLogicalIdentity() {
        let id = UUID()
        let track = Track(
            id: id,
            title: "Local track",
            normalizedTitle: "local track",
            duration: 120,
            createdAt: .now,
            updatedAt: .now
        )
        #expect(track.id == id)
        #expect(track.title == "Local track")
    }

    @Test func collaborativeTracksShareOneRelease() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("shizomusic-\(UUID().uuidString).sqlite").path
        let database = try LibraryDatabase(path: path)
        let repository = GRDBTrackRepository(database: database)
        let coverHash = "same-cover"
        let files = [
            media(title: "Solo", artist: "Main Artist", artists: ["Main Artist"], album: "One Album", coverHash: coverHash),
            media(title: "Collaboration", artist: "Main Artist & Guest", artists: ["Main Artist", "Guest"], album: "One Album", coverHash: "alternate-track-cover")
        ]

        try await repository.synchronize(files: files, scanID: UUID())
        let snapshot = try await repository.snapshot(sort: .title, filter: .available)

        #expect(snapshot.releases.count == 1)
        #expect(snapshot.releases[0].tracks.count == 2)
        #expect(snapshot.releases[0].artist == "Main Artist")
        #expect(snapshot.artists.map(\.name).contains("Guest"))
        let guestResults = try await repository.search(query: "Guest")
        let albumResults = try await repository.search(query: "One Alb")
        try await repository.replaceAliases(forArtistNamed: "Main Artist", aliases: ["Main Alias"])
        let aliasResults = try await repository.search(query: "Main Ali")
        #expect(guestResults.map(\.title) == ["Collaboration"])
        #expect(albumResults.count == 2)
        #expect(aliasResults.count == 2)
    }

    @Test func repeatedFileBecomesAnotherSourceOfTheSameLogicalTrack() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("shizomusic-\(UUID().uuidString).sqlite").path
        let database = try LibraryDatabase(path: path)
        let repository = GRDBTrackRepository(database: database)
        let original = media(title: "Stable", artist: "Artist", artists: ["Artist"], album: "Album", coverHash: "cover", contentHash: "audio-hash")
        let rediscovered = ScannedMediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/moved-stable.flac"),
            contentHash: original.contentHash,
            fileSize: original.fileSize,
            modifiedAt: .now,
            format: original.format,
            title: original.title,
            artistDisplayName: original.artistDisplayName,
            artistNames: original.artistNames,
            albumTitle: original.albumTitle,
            albumArtist: original.albumArtist,
            duration: original.duration,
            artworkURL: original.artworkURL,
            artworkHash: original.artworkHash
        )

        try await repository.synchronize(files: [original], scanID: UUID())
        let originalID = try await repository.snapshot(sort: .title, filter: .available).tracks.first?.id
        try await repository.synchronize(files: [rediscovered], scanID: UUID())
        let rediscoveredTracks = try await repository.snapshot(sort: .title, filter: .available).tracks

        #expect(rediscoveredTracks.count == 1)
        #expect(rediscoveredTracks.first?.id == originalID)
    }

    @Test func remoteCatalogTrackDoesNotEnterOfflineSnapshot() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("shizomusic-\(UUID().uuidString).sqlite").path
        let database = try LibraryDatabase(path: path)
        let repository = GRDBTrackRepository(database: database)
        let catalog = CatalogRepository(database: database)
        let remoteID = UUID()
        try await catalog.merge([APICatalogTrack(
            id: remoteID, contentHash: String(repeating: "a", count: 64), byteSize: "100",
            mimeType: "audio/mpeg", filename: "remote.mp3", status: "ready", title: "Remote only",
            artist: "Friend", album: nil, albumArtist: nil, duration: 60, format: "mp3", codec: "mp3",
            addedBy: .init(id: UUID(), displayName: "Friend"), streamPath: "/catalog/files/hash",
            artworkPath: nil, createdAt: ISO8601DateFormatter().string(from: .now)
        )], baseURL: URL(string: "https://example.test")!)

        let snapshot = try await repository.snapshot(sort: .title, filter: .available)
        let search = try await repository.search(query: "Remote")
        #expect(snapshot.tracks.isEmpty)
        #expect(search.isEmpty)
    }

    private func media(title: String, artist: String, artists: [String], album: String, coverHash: String, contentHash: String? = nil) -> ScannedMediaFile {
        let id = UUID().uuidString
        return ScannedMediaFile(
            fileURL: URL(fileURLWithPath: "/tmp/\(id).flac"),
            contentHash: contentHash ?? id,
            fileSize: 100,
            modifiedAt: .now,
            format: "flac",
            title: title,
            artistDisplayName: artist,
            artistNames: artists,
            albumTitle: album,
            albumArtist: nil,
            duration: 180,
            artworkURL: URL(fileURLWithPath: "/tmp/\(coverHash).image"),
            artworkHash: coverHash
        )
    }
}
