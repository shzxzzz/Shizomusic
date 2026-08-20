import Foundation
import GRDB

struct QueueSourceContext: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case adHoc, offline, release, artist, search, playlist }
    let kind: Kind
    let id: String?

    static let adHoc = QueueSourceContext(kind: .adHoc, id: nil)
    static let offline = QueueSourceContext(kind: .offline, id: nil)
    static func release(_ id: String) -> Self { .init(kind: .release, id: id) }
    static func artist(_ id: String) -> Self { .init(kind: .artist, id: id) }
    static func search(_ query: String) -> Self { .init(kind: .search, id: query) }
    static func playlist(_ id: UUID) -> Self { .init(kind: .playlist, id: id.uuidString) }
}

struct PersistedQueueItem: Identifiable, Sendable {
    enum Status: String, Sendable { case history, current, upcoming }
    let id: UUID
    let track: PlayableTrack
    let status: Status
    let position: Int
}

struct PlaybackQueueSnapshot: Sendable {
    let items: [PersistedQueueItem]
    let elapsedSeconds: Double
    let shuffleEnabled: Bool
    let repeatMode: String
    let context: QueueSourceContext
}

protocol PlaybackQueueRepository: Sendable {
    func load() async throws -> PlaybackQueueSnapshot?
    func save(
        history: [PlayableTrack],
        current: PlayableTrack?,
        upcoming: [PlayableTrack],
        elapsedSeconds: Double,
        shuffleEnabled: Bool,
        repeatMode: String,
        context: QueueSourceContext
    ) async throws
    func clear() async throws
}

actor GRDBPlaybackQueueRepository: PlaybackQueueRepository {
    private let database: LibraryDatabase
    init(database: LibraryDatabase = .shared) { self.database = database }

    func load() async throws -> PlaybackQueueSnapshot? {
        try await database.writer.read { db in
            guard let state = try Row.fetchOne(db, sql: "SELECT * FROM queueState WHERE id = 1") else { return nil }
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT qi.id AS queueItemID, qi.status, qi.position,
                           t.id, t.title, t.duration,
                           COALESCE((SELECT GROUP_CONCAT(name, ' & ') FROM (SELECT a.name AS name FROM artistCredit ac JOIN artist a ON a.id = ac.artistID WHERE ac.trackID = t.id ORDER BY ac.position)), ?) AS artistDisplay,
                           COALESCE((SELECT GROUP_CONCAT(name, char(31)) FROM (SELECT a.name AS name FROM artistCredit ac JOIN artist a ON a.id = ac.artistID WHERE ac.trackID = t.id ORDER BY ac.position)), '') AS artistNames,
                           r.id AS releaseID, r.title AS albumTitle, r.albumArtist,
                           (SELECT sx.fileURL FROM trackSource sx WHERE sx.trackID = t.id AND sx.state = 'available' ORDER BY sx.modifiedAt DESC LIMIT 1) AS fileURL,
                           COALESCE(ra.localURL, (SELECT ma.localURL FROM mediaAsset ma WHERE ma.trackID = t.id ORDER BY ma.createdAt LIMIT 1)) AS artworkURL
                    FROM queueItem qi
                    JOIN track t ON t.id = qi.trackID
                    LEFT JOIN releaseTrack rt ON rt.trackID = t.id
                    LEFT JOIN albumRelease r ON r.id = rt.releaseID
                    LEFT JOIN mediaAsset ra ON ra.id = r.artworkAssetID
                    ORDER BY qi.position
                    """,
                arguments: [String(localized: "library.unknown_artist")]
            )
            let items: [PersistedQueueItem] = rows.compactMap { row in
                let itemIDValue: String = row["queueItemID"]
                let statusValue: String = row["status"]
                let trackID: String = row["id"]
                let artistDisplay: String = row["artistDisplay"]
                let artistNamesValue: String = row["artistNames"]
                let duration: Double = row["duration"]
                let filePath: String? = row["fileURL"]
                let artworkPath: String? = row["artworkURL"]
                guard let itemID = UUID(uuidString: itemIDValue), let status = PersistedQueueItem.Status(rawValue: statusValue) else { return nil }
                return PersistedQueueItem(
                    id: itemID,
                    track: PlayableTrack(
                        id: trackID,
                        title: row["title"],
                        artist: artistDisplay,
                        artistNames: artistNamesValue.isEmpty ? [artistDisplay] : artistNamesValue.components(separatedBy: "\u{1f}"),
                        albumTitle: row["albumTitle"],
                        albumArtist: row["albumArtist"],
                        releaseID: row["releaseID"],
                        durationSeconds: max(Int(duration.rounded()), 0),
                        artworkName: "MistyLake",
                        artworkURL: artworkPath.map(URL.init(fileURLWithPath:)),
                        fileURL: filePath.map(URL.init(fileURLWithPath:))
                    ),
                    status: status,
                    position: row["position"]
                )
            }
            let contextTypeValue: String = state["contextType"]
            let context = QueueSourceContext(kind: QueueSourceContext.Kind(rawValue: contextTypeValue) ?? .adHoc, id: state["contextID"])
            return PlaybackQueueSnapshot(
                items: items,
                elapsedSeconds: state["elapsedSeconds"],
                shuffleEnabled: state["shuffleEnabled"],
                repeatMode: state["repeatMode"],
                context: context
            )
        }
    }

    func save(
        history: [PlayableTrack],
        current: PlayableTrack?,
        upcoming: [PlayableTrack],
        elapsedSeconds: Double,
        shuffleEnabled: Bool,
        repeatMode: String,
        context: QueueSourceContext
    ) async throws {
        try await database.writer.write { db in
            let existingRows = try Row.fetchAll(db, sql: "SELECT id, trackID FROM queueItem ORDER BY position")
            var stableIDs: [String: [String]] = [:]
            for row in existingRows {
                let trackID: String = row["trackID"]
                let id: String = row["id"]
                stableIDs[trackID, default: []].append(id)
            }
            try db.execute(sql: "DELETE FROM queueItem")
            let entries = history.map { ($0, PersistedQueueItem.Status.history) }
                + (current.map { [($0, PersistedQueueItem.Status.current)] } ?? [])
                + upcoming.map { ($0, PersistedQueueItem.Status.upcoming) }
            for (position, entry) in entries.enumerated() {
                let (track, status) = entry
                var ids = stableIDs[track.id] ?? []
                let id = ids.isEmpty ? UUID().uuidString : ids.removeFirst()
                stableIDs[track.id] = ids
                try db.execute(
                    sql: "INSERT INTO queueItem(id, trackID, position, status, enqueuedAt) VALUES (?, ?, ?, ?, ?)",
                    arguments: [id, track.id, position, status.rawValue, Date()]
                )
            }
            let currentItemID = try String.fetchOne(db, sql: "SELECT id FROM queueItem WHERE status = 'current' LIMIT 1")
            try db.execute(
                sql: """
                    INSERT INTO queueState(id, currentItemID, elapsedSeconds, shuffleEnabled, repeatMode, contextType, contextID, updatedAt)
                    VALUES (1, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        currentItemID = excluded.currentItemID,
                        elapsedSeconds = excluded.elapsedSeconds,
                        shuffleEnabled = excluded.shuffleEnabled,
                        repeatMode = excluded.repeatMode,
                        contextType = excluded.contextType,
                        contextID = excluded.contextID,
                        updatedAt = excluded.updatedAt
                    """,
                arguments: [currentItemID, elapsedSeconds, shuffleEnabled, repeatMode, context.kind.rawValue, context.id, Date()]
            )
        }
    }

    func clear() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM queueItem; DELETE FROM queueState;")
        }
    }
}
