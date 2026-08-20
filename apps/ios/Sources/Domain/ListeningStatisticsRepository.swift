import Foundation
import GRDB

actor GRDBListeningStatisticsRepository: ListeningStatisticsRepository {
    private let database: LibraryDatabase

    init(database: LibraryDatabase = .shared) {
        self.database = database
    }

    func record(_ event: ListeningEventDraft) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO listeningEvent(
                        id, sessionID, trackID, eventType, occurredAt, position,
                        fromPosition, toPosition, listenedSeconds, contextType, contextID
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    event.id.uuidString,
                    event.sessionID.uuidString,
                    event.trackID,
                    event.kind.rawValue,
                    event.occurredAt,
                    max(event.position, 0),
                    event.fromPosition,
                    event.toPosition,
                    max(event.listenedSeconds, 0),
                    event.context.kind.rawValue,
                    event.context.id
                ]
            )
        }
    }

    func snapshot(period: StatisticsPeriod) async throws -> ListeningStatisticsSnapshot {
        let start = period.startDate()
        return try await database.writer.read { db in
            let summary = try Row.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(listenedSeconds), 0) AS listened,
                           SUM(CASE WHEN eventType = 'qualified' THEN 1 ELSE 0 END) AS qualified,
                           SUM(CASE WHEN eventType = 'completed' THEN 1 ELSE 0 END) AS completed,
                           SUM(CASE WHEN eventType = 'skip' THEN 1 ELSE 0 END) AS skipped
                    FROM listeningEvent WHERE occurredAt >= ?
                    """,
                arguments: [start]
            )
            let topTracks = try Self.trackRanks(db: db, start: start)
            let topArtists = try Self.artistRanks(db: db, start: start)
            let topReleases = try Self.releaseRanks(db: db, start: start)
            let history = try Self.history(db: db, start: start)
            let totalListeningSeconds: Double = summary?["listened"] ?? 0
            let qualifiedPlays: Int = summary?["qualified"] ?? 0
            let completedPlays: Int = summary?["completed"] ?? 0
            let skippedPlays: Int = summary?["skipped"] ?? 0
            return ListeningStatisticsSnapshot(
                totalListeningSeconds: totalListeningSeconds,
                qualifiedPlays: qualifiedPlays,
                completedPlays: completedPlays,
                skippedPlays: skippedPlays,
                topTracks: topTracks,
                topArtists: topArtists,
                topReleases: topReleases,
                history: history,
                daily: try Self.aggregates(db: db, start: start, format: "%Y-%m-%d"),
                monthly: try Self.aggregates(db: db, start: start, format: "%Y-%m")
            )
        }
    }

    private static func totalsCTE() -> String {
        """
        WITH totals AS (
            SELECT trackID,
                   SUM(listenedSeconds) AS listened,
                   SUM(CASE WHEN eventType = 'qualified' THEN 1 ELSE 0 END) AS qualified
            FROM listeningEvent WHERE occurredAt >= ? GROUP BY trackID
        )
        """
    }

    private static func trackRanks(db: Database, start: Date) throws -> [ListeningRank] {
        let rows = try Row.fetchAll(
            db,
            sql: totalsCTE() + """
                SELECT totals.trackID AS id, t.title, totals.listened, totals.qualified,
                       COALESCE((SELECT GROUP_CONCAT(a.name, ' & ') FROM artistCredit ac JOIN artist a ON a.id = ac.artistID WHERE ac.trackID = t.id), '') AS subtitle,
                       COALESCE(ra.localURL, (SELECT ma.localURL FROM mediaAsset ma WHERE ma.trackID = t.id ORDER BY ma.createdAt LIMIT 1)) AS artworkURL
                FROM totals JOIN track t ON t.id = totals.trackID
                LEFT JOIN releaseTrack rt ON rt.trackID = t.id
                LEFT JOIN albumRelease r ON r.id = rt.releaseID
                LEFT JOIN mediaAsset ra ON ra.id = r.artworkAssetID
                ORDER BY totals.listened DESC LIMIT 20
                """,
            arguments: [start]
        )
        return rows.map(Self.rank)
    }

    private static func artistRanks(db: Database, start: Date) throws -> [ListeningRank] {
        let rows = try Row.fetchAll(
            db,
            sql: totalsCTE() + """
                SELECT a.id, a.name AS title, NULL AS subtitle,
                       SUM(totals.listened) AS listened, SUM(totals.qualified) AS qualified,
                       (SELECT ma.localURL FROM artistCredit ac2 JOIN mediaAsset ma ON ma.trackID = ac2.trackID WHERE ac2.artistID = a.id ORDER BY ma.createdAt LIMIT 1) AS artworkURL
                FROM totals
                JOIN artistCredit ac ON ac.trackID = totals.trackID
                JOIN artist a ON a.id = ac.artistID
                GROUP BY a.id, a.name ORDER BY listened DESC LIMIT 20
                """,
            arguments: [start]
        )
        return rows.map(Self.rank)
    }

    private static func releaseRanks(db: Database, start: Date) throws -> [ListeningRank] {
        let rows = try Row.fetchAll(
            db,
            sql: totalsCTE() + """
                SELECT r.id, r.title, r.albumArtist AS subtitle,
                       SUM(totals.listened) AS listened, SUM(totals.qualified) AS qualified,
                       ra.localURL AS artworkURL
                FROM totals
                JOIN releaseTrack rt ON rt.trackID = totals.trackID
                JOIN albumRelease r ON r.id = rt.releaseID
                LEFT JOIN mediaAsset ra ON ra.id = r.artworkAssetID
                GROUP BY r.id, r.title, r.albumArtist, ra.localURL
                ORDER BY listened DESC LIMIT 20
                """,
            arguments: [start]
        )
        return rows.map(Self.rank)
    }

    private static func rank(_ row: Row) -> ListeningRank {
        let artworkPath: String? = row["artworkURL"]
        return ListeningRank(
            id: row["id"],
            title: row["title"],
            subtitle: row["subtitle"],
            artworkURL: artworkPath.map(URL.init(fileURLWithPath:)),
            listenedSeconds: row["listened"],
            qualifiedPlays: row["qualified"]
        )
    }

    private static func history(db: Database, start: Date) throws -> [ListeningHistoryItem] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT sessionID, trackID, MIN(occurredAt) AS startedAt, MAX(occurredAt) AS endedAt,
                       SUM(listenedSeconds) AS listened,
                       MAX(CASE WHEN eventType = 'completed' THEN 1 ELSE 0 END) AS completed
                FROM listeningEvent WHERE occurredAt >= ?
                GROUP BY sessionID, trackID ORDER BY endedAt DESC LIMIT 100
                """,
            arguments: [start]
        )
        let ids = rows.map { row -> String in row["trackID"] }
        let tracks = try GRDBTrackRepository.fetchPlayableTracks(db: db, matchingTrackIDs: ids, sort: .title, filter: .all)
        let byID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        return rows.compactMap { row in
            let sessionValue: String = row["sessionID"]
            let trackID: String = row["trackID"]
            guard let id = UUID(uuidString: sessionValue), let track = byID[trackID] else { return nil }
            let completed: Int = row["completed"]
            return ListeningHistoryItem(
                id: id,
                track: track,
                startedAt: row["startedAt"],
                endedAt: row["endedAt"],
                listenedSeconds: row["listened"],
                completed: completed != 0
            )
        }
    }

    private static func aggregates(db: Database, start: Date, format: String) throws -> [ListeningAggregate] {
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT strftime(?, occurredAt, 'localtime') AS bucket,
                       SUM(listenedSeconds) AS listened,
                       SUM(CASE WHEN eventType = 'qualified' THEN 1 ELSE 0 END) AS qualified,
                       SUM(CASE WHEN eventType = 'completed' THEN 1 ELSE 0 END) AS completed
                FROM listeningEvent WHERE occurredAt >= ?
                GROUP BY bucket ORDER BY bucket DESC LIMIT 31
                """,
            arguments: [format, start]
        )
        return rows.compactMap { row in
            guard let bucket: String = row["bucket"] else { return nil }
            return ListeningAggregate(
                id: bucket,
                label: bucket,
                listenedSeconds: row["listened"],
                qualifiedPlays: row["qualified"],
                completedPlays: row["completed"]
            )
        }
    }
}
