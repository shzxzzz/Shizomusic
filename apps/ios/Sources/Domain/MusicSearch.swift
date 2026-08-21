import Foundation
import GRDB

enum MusicSourceCapability: String, Codable, Hashable, Sendable {
    case search, stream, acquire
}

enum ExternalEntityType: String, Codable, Hashable, Sendable { case track, artist, release }
enum ExternalAcquisitionMethod: String, Codable, Hashable, Sendable { case direct, ytDlp = "yt_dlp", spotdl, unavailable }

struct ExternalEntityReference: Hashable, Sendable {
    let provider: String
    let entityType: ExternalEntityType
    let externalID: String
    let canonicalURL: URL?
}

enum MusicSourceFailureKind: String, Codable, Sendable {
    case authentication, rateLimit = "rate_limit", geoRestricted = "geo_restricted", temporary, unavailable, malformedResponse = "malformed_response"
}

struct MusicSearchResult: Identifiable, Hashable, Sendable {
    let id: String
    let entityType: ExternalEntityType
    let reference: ExternalEntityReference
    let metadataProvider: String
    let audioProvider: String?
    let acquisitionMethod: ExternalAcquisitionMethod
    let canAcquire: Bool
    let title: String
    let artist: String?
    let release: String?
    let duration: TimeInterval
    let artworkURL: URL?
    let streamURL: URL?
    let attribution: String
    let localTrack: PlayableTrack?

    var provider: String { metadataProvider }
    var album: String? { release }
    var webpageURL: URL? { reference.canonicalURL }
    var capabilities: Set<MusicSourceCapability> {
        var value: Set<MusicSourceCapability> = [.search]
        if streamURL != nil { value.insert(.stream) }
        if canAcquire { value.insert(.acquire) }
        return value
    }
    var stableID: String { "\(reference.provider):\(entityType.rawValue):\(reference.externalID)" }
    var playableTrack: PlayableTrack? {
        if let localTrack { return localTrack }
        guard entityType == .track, let streamURL else { return nil }
        return PlayableTrack(
            id: stableID, title: title, artist: artist ?? String(localized: "track.unknown_artist"), artistNames: artist.map { [$0] } ?? [], albumTitle: release,
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

struct ExternalArtistLibrary: Sendable {
    let artist: MusicSearchResult
    let releases: [MusicSearchResult]
    let tracks: [MusicSearchResult]
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
    let capabilities: Set<MusicSourceCapability> = [.search, .stream]
    private let repository: any TrackRepository
    init(repository: any TrackRepository = GRDBTrackRepository()) { self.repository = repository }
    func search(query: String) async throws -> MusicSourceBatch {
        let tracks = try await repository.search(query: query)
        return MusicSourceBatch(results: tracks.map { track in
            MusicSearchResult(id: track.id, entityType: .track,
                              reference: .init(provider: id, entityType: .track, externalID: track.id, canonicalURL: nil),
                              metadataProvider: id, audioProvider: id, acquisitionMethod: .direct, canAcquire: false,
                              title: track.title, artist: track.artist, release: track.albumTitle, duration: TimeInterval(track.durationSeconds),
                              artworkURL: track.artworkURL, streamURL: track.fileURL, attribution: String(localized: "search.source_offline"), localTrack: track)
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
                    INSERT INTO providerSearchResult(provider,externalID,title,artist,album,duration,artworkURL,webpageURL,streamURL,capabilities,attribution,query,updatedAt,entityType,canonicalURL,metadataProvider,audioProvider,acquisitionMethod)
                    VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
                    ON CONFLICT(provider,entityType,externalID) DO UPDATE SET title=excluded.title,artist=excluded.artist,album=excluded.album,
                      duration=excluded.duration,artworkURL=excluded.artworkURL,webpageURL=excluded.webpageURL,
                      streamURL=excluded.streamURL,capabilities=excluded.capabilities,attribution=excluded.attribution,
                      query=excluded.query,updatedAt=excluded.updatedAt,entityType=excluded.entityType,canonicalURL=excluded.canonicalURL,
                      metadataProvider=excluded.metadataProvider,audioProvider=excluded.audioProvider,acquisitionMethod=excluded.acquisitionMethod
                    """, arguments: [item.reference.provider, item.reference.externalID, item.title, item.artist, item.release, item.duration,
                                      item.artworkURL?.absoluteString, item.reference.canonicalURL?.absoluteString,
                                      item.streamURL?.absoluteString, capabilityValue, item.attribution, encodedQuery, Date(),
                                      item.entityType.rawValue, item.reference.canonicalURL?.absoluteString, item.metadataProvider,
                                      item.audioProvider, item.acquisitionMethod.rawValue])
            }
        }
    }
}
