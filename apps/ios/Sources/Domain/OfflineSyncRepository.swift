import Foundation
import GRDB

enum SyncOutbox {
    static func enqueue<Payload: Encodable>(
        _ db: Database,
        entityType: SyncEntityType,
        entityID: String,
        operationType: SyncOperationType,
        payload: Payload,
        playlistID: String,
        createdAt: Date
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let payloadValue = String(decoding: try encoder.encode(payload), as: UTF8.self)
        try db.execute(
            sql: """
                INSERT INTO syncOperation(id, entityType, entityID, operationType, payload, createdAt, nextAttemptAt, state)
                VALUES (?, ?, ?, ?, ?, ?, ?, 'pending')
                """,
            arguments: [UUID().uuidString, entityType.rawValue, entityID, operationType.rawValue, payloadValue, createdAt, createdAt]
        )
        try db.execute(sql: "UPDATE playlist SET syncStatus = 'pending' WHERE id = ?", arguments: [playlistID])
    }
}

actor GRDBOfflineSyncRepository: OfflineSyncRepository {
    private let database: LibraryDatabase

    init(database: LibraryDatabase = .shared) { self.database = database }

    func prepareInitialOutbox() async throws {
        try await database.writer.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, updatedAt FROM playlist WHERE syncStatus = 'local'")
            for row in rows {
                let idValue: String = row["id"]
                guard let id = UUID(uuidString: idValue) else { continue }
                let updatedAt: Date = row["updatedAt"]
                let operationDate = Date()
                guard let playlist = try Self.playlistPayload(id: id, updatedAt: updatedAt, db: db) else { continue }
                try SyncOutbox.enqueue(db, entityType: .playlist, entityID: idValue, operationType: .playlistUpsert, payload: playlist, playlistID: idValue, createdAt: operationDate)
                let itemRows = try Row.fetchAll(db, sql: "SELECT id, createdAt FROM playlistItem WHERE playlistID = ? ORDER BY rank", arguments: [idValue])
                for (index, itemRow) in itemRows.enumerated() {
                    let itemValue: String = itemRow["id"]
                    guard let itemID = UUID(uuidString: itemValue) else { continue }
                    let createdAt: Date = itemRow["createdAt"]
                    if let item = try Self.playlistItemPayload(id: itemID, updatedAt: createdAt, deletedAt: nil, db: db) {
                        try SyncOutbox.enqueue(db, entityType: .playlistItem, entityID: itemValue, operationType: .playlistItemInsert, payload: item, playlistID: idValue, createdAt: operationDate.addingTimeInterval(Double(index + 1) / 1_000))
                    }
                }
            }
        }
    }

    func readyBatch(limit: Int) async throws -> [SyncOperation] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM syncOperation
                    WHERE state IN ('pending', 'failed') AND nextAttemptAt <= ?
                    ORDER BY createdAt, id LIMIT ?
                    """,
                arguments: [Date(), max(1, min(limit, 100))]
            )
            return rows.compactMap(Self.operation)
        }
    }

    func retryDeferredChanges() async throws {
        try await database.writer.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM syncDeferredChange ORDER BY cursor")
            let decoder = Self.payloadDecoder()
            for row in rows {
                let entityTypeValue: String = row["entityType"]
                let operationTypeValue: String = row["operationType"]
                guard entityTypeValue == SyncEntityType.playlistItem.rawValue,
                      let operationType = SyncOperationType(rawValue: operationTypeValue) else { continue }
                let payloadValue: String = row["payload"]
                let payload = try decoder.decode(PlaylistItemSyncPayload.self, from: Data(payloadValue.utf8))
                let hasPlaylist = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM playlist WHERE id = ?)", arguments: [payload.playlistId.uuidString]) ?? false
                let localTrackID = try Self.localTrackID(syncIdentifier: payload.trackId, db: db)
                guard hasPlaylist, let localTrackID else { continue }
                if payload.deletedAt != nil || operationType == .playlistItemRemove {
                    try db.execute(sql: "DELETE FROM playlistItem WHERE id = ?", arguments: [payload.id.uuidString])
                } else {
                    try db.execute(
                        sql: """
                            INSERT INTO playlistItem(id, playlistID, trackID, rank, createdAt)
                            VALUES (?, ?, ?, ?, ?)
                            ON CONFLICT(id) DO UPDATE SET playlistID = excluded.playlistID, trackID = excluded.trackID,
                                rank = excluded.rank, createdAt = excluded.createdAt
                            """,
                        arguments: [payload.id.uuidString, payload.playlistId.uuidString, localTrackID, payload.rank, payload.createdAt]
                    )
                }
                let operationID: String = row["operationID"]
                let cursor: Int64 = row["cursor"]
                try db.execute(sql: "DELETE FROM syncDeferredChange WHERE operationID = ?", arguments: [operationID])
                try db.execute(sql: "UPDATE syncConflict SET resolvedAt = ? WHERE operationID = ?", arguments: [Date(), operationID])
                try db.execute(sql: "UPDATE playlist SET lastSyncedCursor = MAX(lastSyncedCursor, ?) WHERE id = ?", arguments: [cursor, payload.playlistId.uuidString])
                try Self.refreshPlaylistStatus(payload.playlistId.uuidString, db: db)
            }
        }
    }

    func markAccepted(ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        try await database.writer.write { db in
            var playlistIDs = Set<String>()
            for id in ids {
                if let playlistID = try Self.playlistID(forOperation: id.uuidString, db: db) { playlistIDs.insert(playlistID) }
                try db.execute(sql: "DELETE FROM syncOperation WHERE id = ?", arguments: [id.uuidString])
            }
            for playlistID in playlistIDs { try Self.refreshPlaylistStatus(playlistID, db: db) }
        }
    }

    func markFailed(ids: [UUID], message: String, now: Date) async throws {
        guard !ids.isEmpty else { return }
        try await database.writer.write { db in
            for id in ids {
                let attempt = (try Int.fetchOne(db, sql: "SELECT attemptCount FROM syncOperation WHERE id = ?", arguments: [id.uuidString]) ?? 0) + 1
                let ceiling = min(pow(2, Double(min(attempt, 8))), 300)
                let delay = ceiling + Double.random(in: 0...(ceiling * 0.25))
                try db.execute(
                    sql: "UPDATE syncOperation SET state = 'failed', attemptCount = ?, nextAttemptAt = ?, lastError = ? WHERE id = ?",
                    arguments: [attempt, now.addingTimeInterval(delay), message, id.uuidString]
                )
                if let playlistID = try Self.playlistID(forOperation: id.uuidString, db: db) {
                    try db.execute(sql: "UPDATE playlist SET syncStatus = 'failed' WHERE id = ?", arguments: [playlistID])
                }
            }
            try db.execute(sql: "UPDATE syncState SET lastError = ? WHERE id = 1", arguments: [message])
        }
    }

    func retryAll() async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE syncOperation SET state = 'pending', nextAttemptAt = ?, lastError = NULL", arguments: [Date()])
            try db.execute(sql: "UPDATE playlist SET syncStatus = 'pending' WHERE syncStatus = 'failed'")
            try db.execute(sql: "UPDATE syncState SET lastError = NULL WHERE id = 1")
        }
    }

    func apply(changes: [RemoteSyncChange], cursor: Int64) async throws {
        try await database.writer.write { db in
            let decoder = Self.payloadDecoder()
            var affectedPlaylistIDs = Set<String>()
            for change in changes {
                let data = Data(change.payload.utf8)
                switch change.entityType {
                case .playlist:
                    let payload = try decoder.decode(PlaylistSyncPayload.self, from: data)
                    if payload.deletedAt != nil || change.operationType == .playlistDelete {
                        try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [payload.id.uuidString])
                    } else {
                        affectedPlaylistIDs.insert(payload.id.uuidString)
                        let customCoverPath = try Self.persistCover(payload.customCoverData, playlistID: payload.id)
                        try db.execute(
                            sql: """
                                INSERT INTO playlist(id, title, coverStyle, createdAt, updatedAt, customCoverPath, syncStatus, lastSyncedCursor)
                                VALUES (?, ?, ?, ?, ?, ?, 'synced', ?)
                                ON CONFLICT(id) DO UPDATE SET title = excluded.title, coverStyle = excluded.coverStyle,
                                    createdAt = excluded.createdAt, updatedAt = excluded.updatedAt,
                                    customCoverPath = excluded.customCoverPath, syncStatus = 'synced', lastSyncedCursor = excluded.lastSyncedCursor
                                """,
                            arguments: [payload.id.uuidString, payload.title, payload.coverStyle, payload.createdAt, payload.updatedAt, customCoverPath, cursor]
                        )
                    }
                case .playlistItem:
                    let payload = try decoder.decode(PlaylistItemSyncPayload.self, from: data)
                    if payload.deletedAt != nil || change.operationType == .playlistItemRemove {
                        try db.execute(sql: "DELETE FROM playlistItem WHERE id = ?", arguments: [payload.id.uuidString])
                        affectedPlaylistIDs.insert(payload.playlistId.uuidString)
                    } else {
                        affectedPlaylistIDs.insert(payload.playlistId.uuidString)
                        let hasPlaylist = try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM playlist WHERE id = ?)", arguments: [payload.playlistId.uuidString]) ?? false
                        let localTrackID = try Self.localTrackID(syncIdentifier: payload.trackId, db: db)
                        if hasPlaylist, let localTrackID {
                            try db.execute(
                                sql: """
                                    INSERT INTO playlistItem(id, playlistID, trackID, rank, createdAt)
                                    VALUES (?, ?, ?, ?, ?)
                                    ON CONFLICT(id) DO UPDATE SET playlistID = excluded.playlistID, trackID = excluded.trackID,
                                        rank = excluded.rank, createdAt = excluded.createdAt
                                    """,
                                arguments: [payload.id.uuidString, payload.playlistId.uuidString, localTrackID, payload.rank, payload.createdAt]
                            )
                            try db.execute(sql: "UPDATE playlist SET syncStatus = 'synced', lastSyncedCursor = ? WHERE id = ?", arguments: [cursor, payload.playlistId.uuidString])
                        } else {
                            try Self.insertConflict(
                                db, id: UUID(), operationID: change.id, entityType: .playlistItem,
                                entityID: payload.id.uuidString, reason: hasPlaylist ? "missing_local_track" : "missing_local_playlist",
                                localPayload: "{}", serverPayload: change.payload, createdAt: change.clientTimestamp
                            )
                            try db.execute(
                                sql: """
                                    INSERT OR REPLACE INTO syncDeferredChange(
                                        operationID, cursor, actorDeviceID, entityType, entityID,
                                        operationType, payload, clientTimestamp, reason
                                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                                    """,
                                arguments: [change.id.uuidString, Int64(change.cursor) ?? cursor, change.actorDeviceId.uuidString,
                                            change.entityType.rawValue, change.entityId, change.operationType.rawValue,
                                            change.payload, change.clientTimestamp, hasPlaylist ? "missing_local_track" : "missing_local_playlist"]
                            )
                        }
                    }
                }
            }
            for playlistID in affectedPlaylistIDs { try Self.refreshPlaylistStatus(playlistID, db: db) }
            try db.execute(
                sql: "UPDATE syncState SET cursor = ?, lastSuccessfulSyncAt = ?, lastError = NULL WHERE id = 1",
                arguments: [cursor, Date()]
            )
        }
    }

    func record(conflicts: [SyncConflictRecord]) async throws {
        guard !conflicts.isEmpty else { return }
        try await database.writer.write { db in
            for conflict in conflicts {
                try Self.insertConflict(
                    db, id: conflict.id, operationID: conflict.operationID, entityType: conflict.entityType,
                    entityID: conflict.entityID, reason: conflict.reason, localPayload: conflict.localPayload,
                    serverPayload: conflict.serverPayload, createdAt: conflict.createdAt
                )
                if let playlistID = try Self.playlistID(forEntityType: conflict.entityType, entityID: conflict.entityID, payload: conflict.serverPayload, db: db) {
                    try db.execute(sql: "UPDATE playlist SET syncStatus = 'failed' WHERE id = ?", arguments: [playlistID])
                }
            }
        }
    }

    func overview() async throws -> SyncOverview {
        try await database.writer.read { db in
            let row = try Row.fetchOne(db, sql: "SELECT cursor, lastSuccessfulSyncAt, lastError FROM syncState WHERE id = 1")
            let cursor: Int64 = row?["cursor"] ?? 0
            let lastSuccessfulSyncAt: Date? = row?["lastSuccessfulSyncAt"]
            let lastError: String? = row?["lastError"]
            return SyncOverview(
                pendingCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperation WHERE state = 'pending'") ?? 0,
                failedCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncOperation WHERE state = 'failed'") ?? 0,
                conflictCount: try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM syncConflict WHERE resolvedAt IS NULL") ?? 0,
                cursor: cursor,
                lastSuccessfulSyncAt: lastSuccessfulSyncAt,
                lastError: lastError
            )
        }
    }

    func conflicts() async throws -> [SyncConflictRecord] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT * FROM syncConflict WHERE resolvedAt IS NULL ORDER BY createdAt DESC")
            return rows.compactMap { row in
                let idValue: String = row["id"]
                let operationValue: String = row["operationID"]
                let typeValue: String = row["entityType"]
                guard let id = UUID(uuidString: idValue),
                      let operationID = UUID(uuidString: operationValue),
                      let entityType = SyncEntityType(rawValue: typeValue) else { return nil }
                return SyncConflictRecord(
                    id: id, operationID: operationID, entityType: entityType, entityID: row["entityID"],
                    reason: row["reason"], localPayload: row["localPayload"], serverPayload: row["serverPayload"], createdAt: row["createdAt"]
                )
            }
        }
    }

    private static func operation(_ row: Row) -> SyncOperation? {
        let idValue: String = row["id"]
        let entityTypeValue: String = row["entityType"]
        let operationTypeValue: String = row["operationType"]
        let stateValue: String = row["state"]
        guard let id = UUID(uuidString: idValue),
              let entityType = SyncEntityType(rawValue: entityTypeValue),
              let operationType = SyncOperationType(rawValue: operationTypeValue),
              let state = SyncOperationState(rawValue: stateValue) else { return nil }
        return SyncOperation(id: id, entityType: entityType, entityID: row["entityID"], operationType: operationType,
                             payload: row["payload"], createdAt: row["createdAt"], attemptCount: row["attemptCount"],
                             nextAttemptAt: row["nextAttemptAt"], state: state, lastError: row["lastError"])
    }

    private static func playlistID(forOperation operationID: String, db: Database) throws -> String? {
        guard let row = try Row.fetchOne(db, sql: "SELECT entityType, entityID, payload FROM syncOperation WHERE id = ?", arguments: [operationID]) else { return nil }
        let type: String = row["entityType"]
        if type == SyncEntityType.playlist.rawValue { return row["entityID"] }
        let payload: String = row["payload"]
        return try playlistID(forEntityType: .playlistItem, entityID: row["entityID"], payload: payload, db: db)
    }

    private static func playlistID(forEntityType type: SyncEntityType, entityID: String, payload: String, db: Database) throws -> String? {
        if type == .playlist { return entityID }
        if let data = payload.data(using: .utf8),
           let rawObject = try? JSONSerialization.jsonObject(with: data),
           let object = rawObject as? [String: Any],
           let id = object["playlistId"] as? String { return id }
        return try String.fetchOne(db, sql: "SELECT playlistID FROM playlistItem WHERE id = ?", arguments: [entityID])
    }

    private static func refreshPlaylistStatus(_ playlistID: String, db: Database) throws {
        let operations = try Row.fetchOne(
            db,
            sql: """
                SELECT
                    MAX(CASE WHEN state = 'failed' THEN 1 ELSE 0 END) AS failed,
                    COUNT(*) AS count
                FROM syncOperation
                WHERE (entityType = 'playlist' AND entityID = ?)
                   OR (entityType = 'playlistItem' AND json_extract(payload, '$.playlistId') = ?)
                """,
            arguments: [playlistID, playlistID]
        )
        let failedOperation: Int = operations?["failed"] ?? 0
        let operationCount: Int = operations?["count"] ?? 0
        let conflict = try Bool.fetchOne(
            db,
            sql: """
                SELECT EXISTS(
                    SELECT 1 FROM syncConflict
                    WHERE resolvedAt IS NULL AND (
                        (entityType = 'playlist' AND entityID = ?)
                        OR (entityType = 'playlistItem' AND json_extract(serverPayload, '$.playlistId') = ?)
                    )
                )
                """,
            arguments: [playlistID, playlistID]
        ) ?? false
        let status: DomainSyncStatus = (failedOperation != 0 || conflict) ? .failed : operationCount > 0 ? .pending : .synced
        try db.execute(sql: "UPDATE playlist SET syncStatus = ? WHERE id = ?", arguments: [status.rawValue, playlistID])
    }

    private static func persistCover(_ value: String?, playlistID: UUID) throws -> String? {
        guard let value, let data = Data(base64Encoded: value) else { return nil }
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ShizoMusic/PlaylistArtwork", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("\(playlistID.uuidString).image")
        try data.write(to: url, options: .atomic)
        return url.path
    }

    private static func playlistPayload(id: UUID, updatedAt: Date, db: Database) throws -> PlaylistSyncPayload? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM playlist WHERE id = ?", arguments: [id.uuidString]) else { return nil }
        let path: String? = row["customCoverPath"]
        let cover = path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)).base64EncodedString() }
        return PlaylistSyncPayload(id: id, title: row["title"], coverStyle: row["coverStyle"], customCoverData: cover,
                                   createdAt: row["createdAt"], updatedAt: updatedAt, deletedAt: nil)
    }

    private static func playlistItemPayload(id: UUID, updatedAt: Date, deletedAt: Date?, db: Database) throws -> PlaylistItemSyncPayload? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM playlistItem WHERE id = ?", arguments: [id.uuidString]) else { return nil }
        let playlistValue: String = row["playlistID"]
        guard let playlistID = UUID(uuidString: playlistValue) else { return nil }
        let localTrackID: String = row["trackID"]
        let syncTrackID = try String.fetchOne(
            db,
            sql: "SELECT contentHash FROM trackSource WHERE trackID = ? ORDER BY state = 'available' DESC, modifiedAt DESC LIMIT 1",
            arguments: [localTrackID]
        ) ?? localTrackID
        return PlaylistItemSyncPayload(id: id, playlistId: playlistID, trackId: syncTrackID, rank: row["rank"],
                                       createdAt: row["createdAt"], updatedAt: updatedAt, deletedAt: deletedAt)
    }

    private static func localTrackID(syncIdentifier: String, db: Database) throws -> String? {
        if let id = try String.fetchOne(
            db,
            sql: "SELECT trackID FROM trackSource WHERE contentHash = ? ORDER BY state = 'available' DESC, modifiedAt DESC LIMIT 1",
            arguments: [syncIdentifier]
        ) { return id }
        return try String.fetchOne(db, sql: "SELECT id FROM track WHERE id = ?", arguments: [syncIdentifier])
    }

    private static func insertConflict(
        _ db: Database, id: UUID, operationID: UUID, entityType: SyncEntityType, entityID: String,
        reason: String, localPayload: String, serverPayload: String, createdAt: Date
    ) throws {
        try db.execute(
            sql: """
                INSERT OR IGNORE INTO syncConflict(id, operationID, entityType, entityID, reason, localPayload, serverPayload, createdAt)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [id.uuidString, operationID.uuidString, entityType.rawValue, entityID, reason, localPayload, serverPayload, createdAt]
        )
    }

    private static func payloadDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date")
            }
            return date
        }
        return decoder
    }
}
