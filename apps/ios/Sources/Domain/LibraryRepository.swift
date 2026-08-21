import Foundation
import GRDB

final class GRDBTrackRepository: TrackRepository, @unchecked Sendable {
    private let database: LibraryDatabase

    init(database: LibraryDatabase = .shared) { self.database = database }

    func snapshot(sort: LibraryTrackSort, filter: LibraryAvailabilityFilter) async throws -> LibrarySnapshot {
        let tracks = try await database.writer.read { db in
            try Self.fetchPlayableTracks(db: db, matchingTrackIDs: nil, sort: sort, filter: filter)
        }
        return LibrarySnapshot(tracks: tracks, artists: tracks.localArtists, releases: tracks.localReleases)
    }

    func search(query: String) async throws -> [PlayableTrack] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return try await snapshot(sort: .title, filter: .available).tracks
        }
        let pattern = normalized.split(whereSeparator: \Character.isWhitespace)
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"*" }
            .joined(separator: " AND ")
        return try await database.writer.read { db in
            let ids = try String.fetchAll(
                db,
                sql: "SELECT trackID FROM libraryFTS WHERE libraryFTS MATCH ? ORDER BY bm25(libraryFTS)",
                arguments: [pattern]
            )
            return try Self.fetchPlayableTracks(db: db, matchingTrackIDs: ids, sort: .title, filter: .available)
        }
    }

    func synchronize(files: [ScannedMediaFile], scanID: UUID) async throws {
        let releaseArtists = Self.inferReleaseArtists(files)
        try await database.writer.write { db in
            // Offline is defined by physical files inside Documents/Music. Downloaded
            // sources live there as well, so a scan must invalidate both kinds before
            // marking the files that are actually present as available again.
            try db.execute(sql: "UPDATE trackSource SET state = 'missing' WHERE sourceKind IN ('local','downloaded')")
            for file in files {
                let albumArtist = file.albumTitle.flatMap { _ in
                    file.albumArtist ?? releaseArtists[Self.releaseInferenceKey(file)] ?? file.artistNames.first
                }
                try Self.upsert(file: file, albumArtist: albumArtist, scanID: scanID, db: db)
            }
            try db.execute(sql: "DELETE FROM albumRelease WHERE id NOT IN (SELECT DISTINCT releaseID FROM releaseTrack)")
        }
    }

    func replaceAliases(forArtistNamed name: String, aliases: [String]) async throws {
        try await database.writer.write { db in
            guard let artistID = try String.fetchOne(
                db,
                sql: "SELECT id FROM artist WHERE normalizedName = ?",
                arguments: [name.libraryNormalized]
            ) else { return }
            try db.execute(sql: "DELETE FROM artistAlias WHERE artistID = ?", arguments: [artistID])
            for alias in aliases {
                let trimmed = alias.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                try db.execute(
                    sql: "INSERT OR IGNORE INTO artistAlias(id, artistID, name, normalizedName) VALUES (?, ?, ?, ?)",
                    arguments: [UUID().uuidString, artistID, trimmed, trimmed.libraryNormalized]
                )
            }
            let trackIDs = try String.fetchAll(db, sql: "SELECT trackID FROM artistCredit WHERE artistID = ?", arguments: [artistID])
            for trackID in trackIDs { try Self.rebuildFTS(trackID: trackID, db: db) }
        }
    }

    func deleteLocalSource(trackID: String) async throws -> URL? {
        try await database.writer.write { db in
            guard let path = try String.fetchOne(
                db,
                sql: "SELECT fileURL FROM trackSource WHERE trackID = ? AND state = 'available' AND sourceKind IN ('local','downloaded') ORDER BY modifiedAt DESC LIMIT 1",
                arguments: [trackID]
            ) else { return nil }
            let url = URL(fileURLWithPath: path)
            try FileManager.default.removeItem(at: url)
            try db.execute(sql: "DELETE FROM trackSource WHERE trackID = ? AND fileURL = ?", arguments: [trackID, path])
            return url
        }
    }

    private static func upsert(file: ScannedMediaFile, albumArtist: String?, scanID: UUID, db: Database) throws {
        let normalizedTitle = file.title.libraryNormalized
        let normalizedAlbum = file.albumTitle?.libraryNormalized
        let normalizedAlbumArtist = albumArtist?.libraryNormalized
        let now = Date()

        var trackID = try String.fetchOne(
            db,
            sql: "SELECT trackID FROM trackSource WHERE fileURL = ? ORDER BY state = 'available' DESC LIMIT 1",
            arguments: [file.fileURL.path]
        )
        if trackID == nil {
            trackID = try String.fetchOne(
                db,
                sql: "SELECT trackID FROM trackSource WHERE contentHash = ? LIMIT 1",
                arguments: [file.contentHash]
            )
        }
        if trackID == nil {
            trackID = try String.fetchOne(
                db,
                sql: """
                    SELECT t.id
                    FROM track t
                    LEFT JOIN releaseTrack rt ON rt.trackID = t.id
                    LEFT JOIN albumRelease r ON r.id = rt.releaseID
                    WHERE t.normalizedTitle = ?
                      AND ABS(t.duration - ?) <= 2.0
                      AND COALESCE(r.normalizedTitle, '') = COALESCE(?, '')
                      AND COALESCE(r.normalizedAlbumArtist, '') = COALESCE(?, '')
                    LIMIT 1
                    """,
                arguments: [normalizedTitle, file.duration, normalizedAlbum, normalizedAlbumArtist]
            )
        }
        let resolvedTrackID = trackID ?? UUID().uuidString

        try db.execute(
            sql: """
                INSERT INTO track(id, title, normalizedTitle, duration, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    title = excluded.title,
                    normalizedTitle = excluded.normalizedTitle,
                    duration = excluded.duration,
                    updatedAt = excluded.updatedAt
                """,
            arguments: [resolvedTrackID, file.title, normalizedTitle, file.duration, now, now]
        )

        let existingSourceID = try String.fetchOne(db, sql: "SELECT id FROM trackSource WHERE fileURL = ?", arguments: [file.fileURL.path])
        try db.execute(
            sql: """
                INSERT INTO trackSource(id, trackID, fileURL, contentHash, fileSize, modifiedAt, format, state, lastSeenScanID)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'available', ?)
                ON CONFLICT(fileURL) DO UPDATE SET
                    trackID = excluded.trackID,
                    contentHash = excluded.contentHash,
                    fileSize = excluded.fileSize,
                    modifiedAt = excluded.modifiedAt,
                    format = excluded.format,
                    state = 'available',
                    lastSeenScanID = excluded.lastSeenScanID
                """,
            arguments: [existingSourceID ?? UUID().uuidString, resolvedTrackID, file.fileURL.path, file.contentHash, file.fileSize, file.modifiedAt, file.format, scanID.uuidString]
        )

        try db.execute(sql: "DELETE FROM artistCredit WHERE trackID = ?", arguments: [resolvedTrackID])
        for (position, artistName) in file.artistNames.enumerated() {
            let artistID = try upsertArtist(name: artistName, db: db)
            try db.execute(
                sql: "INSERT INTO artistCredit(id, trackID, artistID, role, position) VALUES (?, ?, ?, ?, ?)",
                arguments: [UUID().uuidString, resolvedTrackID, artistID, position == 0 ? "primary" : "featured", position]
            )
        }

        try db.execute(sql: "DELETE FROM releaseTrack WHERE trackID = ?", arguments: [resolvedTrackID])
        var releaseID: String?
        if let albumTitle = file.albumTitle, let albumArtist {
            releaseID = try upsertRelease(
                title: albumTitle,
                albumArtist: albumArtist,
                now: now,
                db: db
            )
            try db.execute(
                sql: "INSERT OR REPLACE INTO releaseTrack(releaseID, trackID, discNumber, trackNumber) VALUES (?, ?, NULL, NULL)",
                arguments: [releaseID, resolvedTrackID]
            )
        }

        if let artworkURL = file.artworkURL, let artworkHash = file.artworkHash {
            let assetID = try upsertAsset(
                trackID: resolvedTrackID,
                releaseID: releaseID,
                localURL: artworkURL.path,
                hash: artworkHash,
                now: now,
                db: db
            )
            if let releaseID {
                try db.execute(
                    sql: "UPDATE albumRelease SET artworkAssetID = ?, updatedAt = ? WHERE id = ?",
                    arguments: [assetID, now, releaseID]
                )
            }
        }
        try rebuildFTS(trackID: resolvedTrackID, db: db)
    }

    private static func upsertArtist(name: String, db: Database) throws -> String {
        let normalized = name.libraryNormalized
        if let id = try String.fetchOne(db, sql: "SELECT id FROM artist WHERE normalizedName = ?", arguments: [normalized]) {
            return id
        }
        let id = UUID().uuidString
        try db.execute(sql: "INSERT INTO artist(id, name, normalizedName) VALUES (?, ?, ?)", arguments: [id, name, normalized])
        return id
    }

    private static func upsertRelease(
        title: String,
        albumArtist: String,
        now: Date,
        db: Database
    ) throws -> String {
        let normalizedTitle = title.libraryNormalized
        let normalizedArtist = albumArtist.libraryNormalized
        if let id = try String.fetchOne(
            db,
            sql: "SELECT id FROM albumRelease WHERE normalizedTitle = ? AND normalizedAlbumArtist = ?",
            arguments: [normalizedTitle, normalizedArtist]
        ) {
            try db.execute(sql: "UPDATE albumRelease SET title = ?, albumArtist = ?, updatedAt = ? WHERE id = ?", arguments: [title, albumArtist, now, id])
            return id
        }
        let id = UUID().uuidString
        try db.execute(
            sql: "INSERT INTO albumRelease(id, title, normalizedTitle, albumArtist, normalizedAlbumArtist, artworkAssetID, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?, NULL, ?, ?)",
            arguments: [id, title, normalizedTitle, albumArtist, normalizedArtist, now, now]
        )
        return id
    }

    private static func upsertAsset(
        trackID: String,
        releaseID: String?,
        localURL: String,
        hash: String,
        now: Date,
        db: Database
    ) throws -> String {
        if let id = try String.fetchOne(
            db,
            sql: "SELECT id FROM mediaAsset WHERE contentHash = ? AND COALESCE(releaseID, '') = COALESCE(?, '') LIMIT 1",
            arguments: [hash, releaseID]
        ) {
            try db.execute(
                sql: "UPDATE mediaAsset SET localURL = ?, trackID = COALESCE(trackID, ?) WHERE id = ?",
                arguments: [localURL, trackID, id]
            )
            return id
        }
        let id = UUID().uuidString
        try db.execute(
            sql: "INSERT INTO mediaAsset(id, trackID, releaseID, kind, localURL, contentHash, mimeType, createdAt) VALUES (?, ?, ?, 'artwork', ?, ?, NULL, ?)",
            arguments: [id, trackID, releaseID, localURL, hash, now]
        )
        return id
    }

    private static func rebuildFTS(trackID: String, db: Database) throws {
        try db.execute(sql: "DELETE FROM libraryFTS WHERE trackID = ?", arguments: [trackID])
        try db.execute(
            sql: """
                INSERT INTO libraryFTS(trackID, title, artists, album, aliases)
                SELECT t.id,
                       t.title,
                       COALESCE((SELECT GROUP_CONCAT(a.name, ' ') FROM artistCredit ac JOIN artist a ON a.id = ac.artistID WHERE ac.trackID = t.id), ''),
                       COALESCE((SELECT r.title FROM releaseTrack rt JOIN albumRelease r ON r.id = rt.releaseID WHERE rt.trackID = t.id LIMIT 1), ''),
                       COALESCE((SELECT GROUP_CONCAT(aa.name, ' ') FROM artistCredit ac JOIN artistAlias aa ON aa.artistID = ac.artistID WHERE ac.trackID = t.id), '')
                FROM track t WHERE t.id = ?
                """,
            arguments: [trackID]
        )
    }

    static func fetchPlayableTracks(
        db: Database,
        matchingTrackIDs: [String]?,
        sort: LibraryTrackSort,
        filter: LibraryAvailabilityFilter
    ) throws -> [PlayableTrack] {
        if let matchingTrackIDs, matchingTrackIDs.isEmpty { return [] }
        var predicates: [String] = []
        var arguments: StatementArguments = [String(localized: "library.unknown_artist")]
        if let matchingTrackIDs {
            predicates.append("t.id IN (\(matchingTrackIDs.map { _ in "?" }.joined(separator: ",")))")
            arguments += StatementArguments(matchingTrackIDs)
        }
        switch filter {
        case .all:
            // Used by playlists and queue restoration: include logical tracks with
            // remote sources so another device can stream or download them.
            break
        case .available:
            predicates.append("EXISTS (SELECT 1 FROM trackSource sx WHERE sx.trackID = t.id AND sx.sourceKind IN ('local','downloaded') AND sx.state = 'available')")
        case .missing:
            predicates.append("EXISTS (SELECT 1 FROM trackSource sx WHERE sx.trackID = t.id AND sx.sourceKind IN ('local','downloaded')) AND NOT EXISTS (SELECT 1 FROM trackSource sx WHERE sx.trackID = t.id AND sx.sourceKind IN ('local','downloaded') AND sx.state = 'available')")
        }
        let order: String = switch sort {
        case .title: "t.normalizedTitle, artistDisplay"
        case .artist: "artistDisplay, t.normalizedTitle"
        case .album: "albumTitle, t.normalizedTitle"
        case .recentlyAdded: "t.createdAt DESC"
        case .duration: "t.duration DESC, t.normalizedTitle"
        }
        let whereSQL = predicates.isEmpty ? "" : "WHERE " + predicates.joined(separator: " AND ")
        let rows = try Row.fetchAll(
            db,
            sql: """
                SELECT t.id, t.title, t.duration,
                       COALESCE((SELECT GROUP_CONCAT(name, ' & ') FROM (SELECT a.name AS name FROM artistCredit ac JOIN artist a ON a.id = ac.artistID WHERE ac.trackID = t.id ORDER BY ac.position)), ?) AS artistDisplay,
                       COALESCE((SELECT GROUP_CONCAT(name, char(31)) FROM (SELECT a.name AS name FROM artistCredit ac JOIN artist a ON a.id = ac.artistID WHERE ac.trackID = t.id ORDER BY ac.position)), '') AS artistNames,
                       r.id AS releaseID, r.title AS albumTitle, r.albumArtist,
                       (SELECT COALESCE(sx.remoteURL, sx.fileURL) FROM trackSource sx
                        WHERE sx.trackID = t.id AND sx.state = 'available'
                        ORDER BY CASE sx.sourceKind WHEN 'local' THEN 0 WHEN 'downloaded' THEN 1 ELSE 2 END, sx.modifiedAt DESC LIMIT 1) AS fileURL,
                       (SELECT sx.addedByName FROM trackSource sx WHERE sx.trackID=t.id AND sx.sourceKind='remote' LIMIT 1) AS addedByName,
                       COALESCE(ra.localURL, (SELECT ma.localURL FROM mediaAsset ma WHERE ma.trackID = t.id
                        ORDER BY CASE WHEN ma.localURL LIKE 'http://%' OR ma.localURL LIKE 'https://%' THEN 1 ELSE 0 END,
                        ma.createdAt DESC LIMIT 1)) AS artworkURL
                FROM track t
                LEFT JOIN releaseTrack rt ON rt.trackID = t.id
                LEFT JOIN albumRelease r ON r.id = rt.releaseID
                LEFT JOIN mediaAsset ra ON ra.id = r.artworkAssetID
                \(whereSQL)
                ORDER BY \(order)
                """,
            arguments: arguments
        )
        return rows.map { row in
            let id: String = row["id"]
            let title: String = row["title"]
            let artist: String = row["artistDisplay"]
            let artistNamesValue: String = row["artistNames"]
            let duration: Double = row["duration"]
            let albumTitle: String? = row["albumTitle"]
            let albumArtist: String? = row["albumArtist"]
            let releaseID: String? = row["releaseID"]
            let artworkPath: String? = row["artworkURL"]
            let filePath: String? = row["fileURL"]
            return PlayableTrack(
                id: id,
                title: title,
                artist: artist,
                artistNames: artistNamesValue.isEmpty ? [artist] : artistNamesValue.components(separatedBy: "\u{1f}"),
                albumTitle: albumTitle,
                albumArtist: albumArtist,
                releaseID: releaseID,
                durationSeconds: max(Int(duration.rounded()), 0),
                artworkName: "MistyLake",
                artworkURL: artworkPath.map(\.mediaSourceURL),
                fileURL: filePath.map(\.mediaSourceURL),
                addedByName: row["addedByName"]
            )
        }
    }

    private static func inferReleaseArtists(_ files: [ScannedMediaFile]) -> [String: String] {
        Dictionary(grouping: files.filter { $0.albumTitle != nil }, by: releaseInferenceKey)
            .compactMapValues { group in
                let explicit = mostFrequent(group.compactMap(\.albumArtist))
                return explicit ?? mostFrequent(group.compactMap { $0.artistNames.first })
            }
    }

    private static func releaseInferenceKey(_ file: ScannedMediaFile) -> String {
        file.albumTitle?.libraryNormalized ?? ""
    }

    private static func mostFrequent(_ values: [String]) -> String? {
        var grouped: [String: (displayName: String, count: Int)] = [:]
        for value in values {
            let normalized = value.libraryNormalized
            if let existing = grouped[normalized] {
                grouped[normalized] = (existing.displayName, existing.count + 1)
            } else {
                grouped[normalized] = (value, 1)
            }
        }
        let orderedKeys = grouped.keys.sorted { lhs, rhs in
            guard let left = grouped[lhs], let right = grouped[rhs] else { return lhs < rhs }
            if left.count != right.count { return left.count > right.count }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        guard let key = orderedKeys.first else { return nil }
        return grouped[key]?.displayName
    }
}

extension String {
    var libraryNormalized: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    var mediaSourceURL: URL {
        if let url = URL(string: self), url.scheme != nil { return url }
        return URL(fileURLWithPath: self)
    }
}
