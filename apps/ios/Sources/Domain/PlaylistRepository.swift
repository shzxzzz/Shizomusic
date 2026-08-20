import Foundation
import GRDB

actor GRDBPlaylistRepository: PlaylistRepository {
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
                return Playlist(
                    id: id,
                    title: row["title"],
                    coverStyle: PlaylistCoverStyle(rawValue: coverValue) ?? .violet,
                    items: items,
                    createdAt: row["createdAt"],
                    updatedAt: row["updatedAt"]
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
        }
        return id
    }

    func rename(id: UUID, title: String) async throws {
        try await update(id: id, column: "title", value: title)
    }

    func changeCover(id: UUID, coverStyle: PlaylistCoverStyle) async throws {
        try await update(id: id, column: "coverStyle", value: coverStyle.rawValue)
    }

    func delete(id: UUID) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [id.uuidString])
        }
    }

    func add(trackID: String, to playlistID: UUID) async throws -> UUID {
        let itemID = UUID()
        try await database.writer.write { db in
            let lastRank = try Double.fetchOne(
                db,
                sql: "SELECT rank FROM playlistItem WHERE playlistID = ? ORDER BY rank DESC LIMIT 1",
                arguments: [playlistID.uuidString]
            )
            try db.execute(
                sql: "INSERT INTO playlistItem(id, playlistID, trackID, rank, createdAt) VALUES (?, ?, ?, ?, ?)",
                arguments: [itemID.uuidString, playlistID.uuidString, trackID, (lastRank ?? 0) + Self.rankStep, Date()]
            )
            try Self.touch(playlistID, db: db)
        }
        return itemID
    }

    func remove(itemID: UUID) async throws {
        try await database.writer.write { db in
            let playlistID = try String.fetchOne(db, sql: "SELECT playlistID FROM playlistItem WHERE id = ?", arguments: [itemID.uuidString])
            try db.execute(sql: "DELETE FROM playlistItem WHERE id = ?", arguments: [itemID.uuidString])
            if let playlistID, let id = UUID(uuidString: playlistID) { try Self.touch(id, db: db) }
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
            if let previousRank, let nextRank, abs(nextRank - previousRank) < 0.000_001 {
                for (position, id) in ids.enumerated() {
                    try db.execute(sql: "UPDATE playlistItem SET rank = ? WHERE id = ?", arguments: [Double(position + 1) * Self.rankStep, id])
                }
                newRank = Double(index + 1) * Self.rankStep
            }
            try db.execute(sql: "UPDATE playlistItem SET rank = ? WHERE id = ?", arguments: [newRank, itemID.uuidString])
            if let id = UUID(uuidString: playlistID) { try Self.touch(id, db: db) }
        }
    }

    private func update(id: UUID, column: String, value: String) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE playlist SET \(column) = ?, updatedAt = ? WHERE id = ?", arguments: [value, Date(), id.uuidString])
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

    private static func touch(_ playlistID: UUID, db: Database) throws {
        try db.execute(sql: "UPDATE playlist SET updatedAt = ? WHERE id = ?", arguments: [Date(), playlistID.uuidString])
    }
}
