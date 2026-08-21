import Foundation
import GRDB

enum MusicSourceCapability: String, Codable, Hashable, Sendable {
    case search, stream, download
}

enum MusicSourceFailureKind: String, Codable, Sendable {
    case authentication, rateLimit = "rate_limit", geoRestricted = "geo_restricted", temporary, unavailable
}

struct MusicSearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let provider: String
    let title: String
    let artist: String
    let album: String?
    let duration: TimeInterval
    let artworkURL: URL?
    let webpageURL: URL?
    let streamURL: URL?
    let capabilities: Set<MusicSourceCapability>
    let attribution: String?
    let localTrack: PlayableTrack?

    var stableID: String { "\(provider):\(id)" }
    var playableTrack: PlayableTrack? {
        if let localTrack { return localTrack }
        guard capabilities.contains(.stream), let streamURL else { return nil }
        return PlayableTrack(
            id: stableID, title: title, artist: artist, artistNames: [artist], albumTitle: album,
            albumArtist: artist, releaseID: nil, durationSeconds: max(Int(duration.rounded()), 0),
            artworkName: "MistyLake", artworkURL: artworkURL, fileURL: streamURL, addedByName: attribution
        )
    }
}

struct MusicSourceFailure: Identifiable, Hashable, Sendable {
    var id: String { provider }
    let provider: String
    let kind: MusicSourceFailureKind
    let message: String
    let retryAfterSeconds: Int?
}

struct MusicSourceBatch: Sendable {
    let results: [MusicSearchResult]
    let failures: [MusicSourceFailure]
}

@MainActor
protocol MusicSourceAdapter: AnyObject {
    var id: String { get }
    var capabilities: Set<MusicSourceCapability> { get }
    func search(query: String) async throws -> MusicSourceBatch
}

@MainActor
final class LocalFTSMusicSourceAdapter: MusicSourceAdapter {
    let id = "offline"
    let capabilities: Set<MusicSourceCapability> = [.search, .stream, .download]
    private let repository: any TrackRepository
    init(repository: any TrackRepository = GRDBTrackRepository()) { self.repository = repository }
    func search(query: String) async throws -> MusicSourceBatch {
        let tracks = try await repository.search(query: query)
        return MusicSourceBatch(results: tracks.map { track in
            MusicSearchResult(id: track.id, provider: id, title: track.title, artist: track.artist,
                              album: track.albumTitle, duration: TimeInterval(track.durationSeconds),
                              artworkURL: track.artworkURL, webpageURL: nil, streamURL: track.fileURL,
                              capabilities: capabilities, attribution: nil, localTrack: track)
        }, failures: [])
    }
}

actor ProviderSearchCache {
    private let database: LibraryDatabase
    init(database: LibraryDatabase = .shared) { self.database = database }

    func save(_ results: [MusicSearchResult], query: String) async throws {
        let encodedQuery = query.libraryNormalized
        try await database.writer.write { db in
            for item in results where item.provider != "offline" {
                let capabilityValue = item.capabilities.map(\.rawValue).sorted().joined(separator: ",")
                try db.execute(sql: """
                    INSERT INTO providerSearchResult(provider,externalID,title,artist,album,duration,artworkURL,webpageURL,streamURL,capabilities,attribution,query,updatedAt)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(provider,externalID) DO UPDATE SET title=excluded.title,artist=excluded.artist,album=excluded.album,
                      duration=excluded.duration,artworkURL=excluded.artworkURL,webpageURL=excluded.webpageURL,
                      streamURL=excluded.streamURL,capabilities=excluded.capabilities,attribution=excluded.attribution,
                      query=excluded.query,updatedAt=excluded.updatedAt
                    """, arguments: [item.provider, item.id, item.title, item.artist, item.album, item.duration,
                                      item.artworkURL?.absoluteString, item.webpageURL?.absoluteString,
                                      item.streamURL?.absoluteString, capabilityValue, item.attribution, encodedQuery, Date()])
            }
        }
    }
}
