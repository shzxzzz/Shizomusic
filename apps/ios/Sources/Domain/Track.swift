import Foundation
import GRDB

struct Track: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "track"
    var id: UUID
    var title: String
    var normalizedTitle: String
    var duration: TimeInterval
    var createdAt: Date
    var updatedAt: Date
}

struct TrackSource: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "trackSource"
    enum State: String, Codable, Sendable { case available, missing, corrupt, unsupported }

    var id: UUID
    var trackID: UUID
    var fileURL: String
    var contentHash: String
    var fileSize: Int64
    var modifiedAt: Date
    var format: String
    var state: State
    var lastSeenScanID: UUID
}

struct Artist: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "artist"
    var id: UUID
    var name: String
    var normalizedName: String
}

struct ArtistCredit: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "artistCredit"
    enum Role: String, Codable, Sendable { case primary, featured, albumArtist }

    var id: UUID
    var trackID: UUID
    var artistID: UUID
    var role: Role
    var position: Int
}

struct ArtistAlias: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "artistAlias"
    var id: UUID
    var artistID: UUID
    var name: String
    var normalizedName: String
}

struct Release: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "albumRelease"
    var id: UUID
    var title: String
    var normalizedTitle: String
    var albumArtist: String
    var normalizedAlbumArtist: String
    var artworkAssetID: UUID?
    var createdAt: Date
    var updatedAt: Date
}

struct ReleaseTrack: Codable, FetchableRecord, PersistableRecord, TableRecord, Hashable, Sendable {
    static let databaseTableName = "releaseTrack"
    var releaseID: UUID
    var trackID: UUID
    var discNumber: Int?
    var trackNumber: Int?
}

struct MediaAsset: Codable, FetchableRecord, PersistableRecord, TableRecord, Identifiable, Hashable, Sendable {
    static let databaseTableName = "mediaAsset"
    enum Kind: String, Codable, Sendable { case artwork }

    var id: UUID
    var trackID: UUID?
    var releaseID: UUID?
    var kind: Kind
    var localURL: String
    var contentHash: String
    var mimeType: String?
    var createdAt: Date
}

struct ScannedMediaFile: Hashable, Sendable {
    let fileURL: URL
    let contentHash: String
    let fileSize: Int64
    let modifiedAt: Date
    let format: String
    let title: String
    let artistDisplayName: String
    let artistNames: [String]
    let albumTitle: String?
    let albumArtist: String?
    let duration: TimeInterval
    let artworkURL: URL?
    let artworkHash: String?
}

struct LibrarySnapshot: Sendable {
    let tracks: [PlayableTrack]
    let artists: [LocalArtist]
    let releases: [LocalRelease]
}

enum LibraryTrackSort: String, CaseIterable, Sendable {
    case title, artist, album, recentlyAdded, duration
    var localizationKey: String { "library.sort_\(rawValue)" }
}
enum LibraryAvailabilityFilter: String, CaseIterable, Sendable {
    case all, available, missing
    var localizationKey: String { "library.filter_\(rawValue)" }
}

protocol TrackRepository: Sendable {
    func snapshot(sort: LibraryTrackSort, filter: LibraryAvailabilityFilter) async throws -> LibrarySnapshot
    func search(query: String) async throws -> [PlayableTrack]
    func synchronize(files: [ScannedMediaFile], scanID: UUID) async throws
    func replaceAliases(forArtistNamed name: String, aliases: [String]) async throws
    func deleteLocalSource(trackID: String) async throws -> URL?
}
