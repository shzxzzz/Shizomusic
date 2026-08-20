import Foundation
import GRDB

actor GRDBPlaylistRepository: PlaylistRepository {
    private enum CustomCoverOverride {
        case preserve
        case replace(String?)
    }

    private let database: LibraryDatabase
    private static let rankStep = 1_024.0

    init(database: LibraryDatabase = .shared) { self.database = database }

    func fetchAll() async throws -> [Playlist] {
        try await database.writer.read { db in
            let playlistRows = try Row.fetchAll(db, sql: "SELECT * FROM playlist ORDER BY updatedAt DESC, title")
            let itemRows = try Row.fetchAll(db, sql: "SELECT * FROM playlistItem ORDER BY playlistID, rank, createdAt")
            let trackIDs = Array(Set(itemRows.map { row -> String in row["trackID"] }))
            let tracks = try GRDBTrackRepository.fetchPlayableTracks(
                db: db,
                matchingTrackIDs: trackIDs,
                sort: .title,
                filter: .all
            )
            let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
            let rowsByPlaylist = Dictionary(grouping: itemRows) { row -> String in row["playlistID"] }

            return playlistRows.compactMap { row in
                let idValue: String = row["id"]
                guard let id = UUID(uuidString: idValue) else { return nil }
                let items = (rowsByPlaylist[idValue] ?? []).compactMap { itemRow -> PlaylistItem? in
                    let itemIDValue: String = itemRow["id"]
                    let trackID: String = itemRow["trackID"]
                    guard let itemID = UUID(uuidString: itemIDValue), let track = tracksByID[trackID] else { return nil }
                    return PlaylistItem(
                        id: itemID,
                        playlistID: id,
                        track: track,
                        rank: itemRow["rank"],
                        createdAt: itemRow["createdAt"]
                    )
                }
                let coverValue: String = row["coverStyle"]
                let customCoverPath: String? = row["customCoverPath"]
                return Playlist(
                    id: id,
                    title: row["title"],
                    coverStyle: PlaylistCoverStyle(rawValue: coverValue) ?? .violet,
                    customCoverURL: customCoverPath.map(URL.init(fileURLWithPath:)),
                    items: items,
                    createdAt: row["createdAt"],
                    updatedAt: row["updatedAt"],
                    syncStatus: DomainSyncStatus(rawValue: row["syncStatus"]) ?? .local,
                    lastSyncedCursor: row["lastSyncedCursor"]
                )
            }
        }
    }

    func create(title: String, coverStyle: PlaylistCoverStyle) async throws -> UUID {
        let id = UUID()
        try await database.writer.write { db in
            let now = Date()
            try db.execute(
                sql: "INSERT INTO playlist(id, title, coverStyle, createdAt, updatedAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [id.uuidString, title, coverStyle.rawValue, now, now]
            )
            let payload = PlaylistSyncPayload(id: id, title: title, coverStyle: coverStyle.rawValue, customCoverData: nil, createdAt: now, updatedAt: now, deletedAt: nil)
            try SyncOutbox.enqueue(db, entityType: .playlist, entityID: id.uuidString, operationType: .playlistUpsert, payload: payload, playlistID: id.uuidString, createdAt: now)
        }
        return id
    }

    func rename(id: UUID, title: String) async throws {
        try await update(id: id, column: "title", value: title, customCoverOverride: .preserve)
    }

    func changeCover(id: UUID, coverStyle: PlaylistCoverStyle) async throws {
        try await database.writer.write { db in
            let now = Date()
            try db.execute(
                sql: "UPDATE playlist SET coverStyle = ?, customCoverPath = NULL, updatedAt = ? WHERE id = ?",
                arguments: [coverStyle.rawValue, now, id.uuidString]
            )
            if let payload = try Self.playlistPayload(id: id, updatedAt: now, customCoverOverride: .replace(nil), db: db) {
                try SyncOutbox.enqueue(db, entityType: .playlist, entityID: id.uuidString, operationType: .playlistUpsert, payload: payload, playlistID: id.uuidString, createdAt: now)
            }
        }
    }

    func setCustomCover(id: UUID, fileURL: URL) async throws {
        let coverData = try Data(contentsOf: fileURL).base64EncodedString()
        try await update(id: id, column: "customCoverPath", value: fileURL.path, customCoverOverride: .replace(coverData))
    }

    func delete(id: UUID) async throws {
        try await database.writer.write { db in
            let now = Date()
            let payload = try Self.playlistPayload(id: id, updatedAt: now, deletedAt: now, customCoverOverride: .preserve, db: db)
            if let payload {
                try SyncOutbox.enqueue(db, entityType: .playlist, entityID: id.uuidString, operationType: .playlistDelete, payload: payload, playlistID: id.uuidString, createdAt: now)
            }
            try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func add(trackID: String, to playlistID: UUID) async throws -> UUID {
        try await database.writer.write { db in
            if let existing = try String.fetchOne(
                db,
                sql: "SELECT id FROM playlistItem WHERE playlistID = ? AND trackID = ? LIMIT 1",
                arguments: [playlistID.uuidString, trackID]
            ), let existingID = UUID(uuidString: existing) {
                return existingID
            }
            let itemID = UUID()
            let now = Date()
            let lastRank = try Double.fetchOne(
                db,
                sql: "SELECT rank FROM playlistItem WHERE playlistID = ? ORDER BY rank DESC LIMIT 1",
                arguments: [playlistID.uuidString]
            )
            try db.execute(
                sql: "INSERT INTO playlistItem(id, playlistID, trackID, rank, createdAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [itemID.uuidString, playlistID.uuidString, trackID, (lastRank ?? 0) + Self.rankStep, now]
            )
            try Self.touch(playlistID, at: now, db: db)
            if let payload = try Self.playlistItemPayload(id: itemID, updatedAt: now, deletedAt: nil, db: db) {
                try SyncOutbox.enqueue(db, entityType: .playlistItem, entityID: itemID.uuidString, operationType: .playlistItemInsert, payload: payload, playlistID: playlistID.uuidString, createdAt: now)
            }
            return itemID
        }
    }

    func remove(itemID: UUID) async throws {
        try await database.writer.write { db in
            let now = Date()
            let payload = try Self.playlistItemPayload(id: itemID, updatedAt: now, deletedAt: now, db: db)
            let playlistID = payload?.playlistId.uuidString
            if let payload, let playlistID {
                try SyncOutbox.enqueue(db, entityType: .playlistItem, entityID: itemID.uuidString, operationType: .playlistItemRemove, payload: payload, playlistID: playlistID, createdAt: now)
            }
            try db.execute(sql: "DELETE FROM playlistItem WHERE id = ?", arguments: [itemID.uuidString])
            if let playlistID, let id = UUID(uuidString: playlistID) { try Self.touch(id, at: now, db: db) }
        }
    }

    func move(itemID: UUID, to destinationIndex: Int) async throws {
        try await database.writer.write { db in
            guard let playlistID = try String.fetchOne(
                db,
                sql: "SELECT playlistID FROM playlistItem WHERE id = ?",
                arguments: [itemID.uuidString]
            ) else { return }
            var ids = try String.fetchAll(
                db,
                sql: "SELECT id FROM playlistItem WHERE playlistID = ? AND id <> ? ORDER BY rank, createdAt",
                arguments: [playlistID, itemID.uuidString]
            )
            ids.insert(itemID.uuidString, at: min(max(destinationIndex, 0), ids.count))
            let index = ids.firstIndex(of: itemID.uuidString) ?? 0
            let previousRank = index > 0 ? try Self.rank(of: ids[index - 1], db: db) : nil
            let nextRank = index + 1 < ids.count ? try Self.rank(of: ids[index + 1], db: db) : nil
            var newRank = Self.fractionalRank(previous: previousRank, next: nextRank)
            var rebalancedItemIDs: [UUID] = []
            if let previousRank, let nextRank, abs(nextRank - previousRank) < 0.000_001 {
                for (position, id) in ids.enumerated() {
                    try db.execute(sql: "UPDATE playlistItem SET rank = ? WHERE id = ?", arguments: [Double(position + 1) * Self.rankStep, id])
                    if id != itemID.uuidString, let value = UUID(uuidString: id) { rebalancedItemIDs.append(value) }
                }
                newRank = Double(index + 1) * Self.rankStep
            }
            try db.execute(sql: "UPDATE playlistItem SET rank = ? WHERE id = ?", arguments: [newRank, itemID.uuidString])
            let now = Date()
            if let id = UUID(uuidString: playlistID) { try Self.touch(id, at: now, db: db) }
            if let payload = try Self.playlistItemPayload(id: itemID, updatedAt: now, deletedAt: nil, db: db) {
                try SyncOutbox.enqueue(db, entityType: .playlistItem, entityID: itemID.uuidString, operationType: .playlistItemMove, payload: payload, playlistID: playlistID, createdAt: now)
            }
            for rebalancedID in rebalancedItemIDs {
                if let payload = try Self.playlistItemPayload(id: rebalancedID, updatedAt: now, deletedAt: nil, db: db) {
                    try SyncOutbox.enqueue(db, entityType: .playlistItem, entityID: rebalancedID.uuidString, operationType: .playlistItemMove, payload: payload, playlistID: playlistID, createdAt: now)
                }
            }
        }
    }

    private func update(id: UUID, column: String, value: String, customCoverOverride: CustomCoverOverride) async throws {
        try await database.writer.write { db in
            let now = Date()
            try db.execute(sql: "UPDATE playlist SET \(column) = ?, updatedAt = ? WHERE id = ?", arguments: [value, now, id.uuidString])
            if let payload = try Self.playlistPayload(id: id, updatedAt: now, customCoverOverride: customCoverOverride, db: db) {
                try SyncOutbox.enqueue(db, entityType: .playlist, entityID: id.uuidString, operationType: .playlistUpsert, payload: payload, playlistID: id.uuidString, createdAt: now)
            }
        }
    }

    private static func fractionalRank(previous: Double?, next: Double?) -> Double {
        switch (previous, next) {
        case let (previous?, next?): (previous + next) / 2
        case let (previous?, nil): previous + rankStep
        case let (nil, next?): next - rankStep
        case (nil, nil): rankStep
        }
    }

    private static func rank(of itemID: String, db: Database) throws -> Double? {
        try Double.fetchOne(db, sql: "SELECT rank FROM playlistItem WHERE id = ?", arguments: [itemID])
    }

    private static func touch(_ playlistID: UUID, at date: Date, db: Database) throws {
        try db.execute(sql: "UPDATE playlist SET updatedAt = ? WHERE id = ?", arguments: [date, playlistID.uuidString])
    }

    private static func playlistPayload(
        id: UUID,
        updatedAt: Date,
        deletedAt: Date? = nil,
        customCoverOverride: CustomCoverOverride,
        db: Database
    ) throws -> PlaylistSyncPayload? {
        guard let row = try Row.fetchOne(db, sql: "SELECT * FROM playlist WHERE id = ?", arguments: [id.uuidString]) else { return nil }
        let path: String? = row["customCoverPath"]
        let storedCover = path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)).base64EncodedString() }
        let customCover: String?
        switch customCoverOverride {
        case .preserve: customCover = storedCover
        case let .replace(value): customCover = value
        }
        return PlaylistSyncPayload(
            id: id, title: row["title"], coverStyle: row["coverStyle"], customCoverData: customCover,
            createdAt: row["createdAt"], updatedAt: updatedAt, deletedAt: deletedAt
        )
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
        return PlaylistItemSyncPayload(
            id: id, playlistId: playlistID, trackId: syncTrackID, rank: row["rank"],
            createdAt: row["createdAt"], updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}
