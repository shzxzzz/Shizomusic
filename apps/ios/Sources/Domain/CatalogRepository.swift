import CryptoKit
import Foundation
import GRDB

enum MediaTransferDirection: String, Codable, Sendable { case upload, download }
enum MediaTransferState: String, Codable, Sendable { case queued, running, paused, completed, failed, cancelled }

struct MediaTransfer: Identifiable, Hashable, Sendable {
    let id: UUID
    let trackID: String?
    let sourceID: String?
    let contentHash: String
    let title: String
    let direction: MediaTransferDirection
    let state: MediaTransferState
    let progress: Double
    let transferredBytes: Int64
    let totalBytes: Int64
    let uploadSessionID: UUID?
    let nextPart: Int
    let lastError: String?
}

struct LocalUploadCandidate: Sendable {
    let transferID: UUID
    let trackID: String
    let sourceID: String
    let title: String
    let fileURL: URL
    let contentHash: String
    let byteSize: Int64
    let format: String
}

actor CatalogRepository {
    private let database: LibraryDatabase
    init(database: LibraryDatabase = .shared) { self.database = database }

    func recoverInterruptedTransfers(activeIDs: Set<UUID>) async throws {
        try await database.writer.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id FROM mediaTransfer WHERE state='running'")
            for row in rows {
                let value: String = row["id"]
                guard let id = UUID(uuidString: value), !activeIDs.contains(id) else { continue }
                try db.execute(
                    sql: "UPDATE mediaTransfer SET state='failed', lastError=?, updatedAt=? WHERE id=?",
                    arguments: [String(localized: "downloads.interrupted_error"), Date(), value]
                )
            }
        }
    }

    func enqueueLocalUploads() async throws {
        try await database.writer.write { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT sx.id AS sourceID, sx.trackID, sx.contentHash, sx.fileSize, t.title
                FROM trackSource sx JOIN track t ON t.id = sx.trackID
                WHERE sx.sourceKind = 'local' AND sx.state = 'available'
                  AND NOT EXISTS (SELECT 1 FROM mediaTransfer mt WHERE mt.contentHash = sx.contentHash AND mt.direction = 'upload' AND mt.state IN ('queued','running','paused','completed'))
                """)
            for row in rows {
                let trackID: String = row["trackID"]
                let sourceID: String = row["sourceID"]
                let contentHash: String = row["contentHash"]
                let fileSize: Int64 = row["fileSize"]
                try db.execute(sql: """
                    INSERT INTO mediaTransfer(id, trackID, sourceID, contentHash, direction, state, totalBytes, createdAt, updatedAt)
                    VALUES (?, ?, ?, ?, 'upload', 'queued', ?, ?, ?)
                    """, arguments: [UUID().uuidString, trackID, sourceID, contentHash, fileSize, Date(), Date()])
            }
        }
    }

    func nextUpload() async throws -> LocalUploadCandidate? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT mt.id, mt.trackID, mt.sourceID, mt.contentHash, sx.fileURL, sx.fileSize, sx.format, t.title
                FROM mediaTransfer mt JOIN trackSource sx ON sx.id = mt.sourceID JOIN track t ON t.id = mt.trackID
                WHERE mt.direction = 'upload' AND mt.state IN ('queued','failed') ORDER BY mt.updatedAt LIMIT 1
                """) else { return nil }
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return LocalUploadCandidate(transferID: id, trackID: row["trackID"], sourceID: row["sourceID"], title: row["title"],
                                        fileURL: URL(fileURLWithPath: row["fileURL"]), contentHash: row["contentHash"],
                                        byteSize: row["fileSize"], format: row["format"])
        }
    }

    func uploadCandidate(id: UUID) async throws -> LocalUploadCandidate? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: """
                SELECT mt.id, mt.trackID, mt.sourceID, mt.contentHash, sx.fileURL, sx.fileSize, sx.format, t.title
                FROM mediaTransfer mt JOIN trackSource sx ON sx.id=mt.sourceID JOIN track t ON t.id=mt.trackID WHERE mt.id=?
                """, arguments: [id.uuidString]) else { return nil }
            return LocalUploadCandidate(transferID: id, trackID: row["trackID"], sourceID: row["sourceID"], title: row["title"],
                                        fileURL: URL(fileURLWithPath: row["fileURL"]), contentHash: row["contentHash"],
                                        byteSize: row["fileSize"], format: row["format"])
        }
    }

    func updateUpload(_ id: UUID, state: MediaTransferState, sessionID: UUID? = nil, nextPart: Int? = nil,
                      transferred: Int64? = nil, total: Int64? = nil, error: String? = nil) async throws {
        try await database.writer.write { db in
            try db.execute(sql: """
                UPDATE mediaTransfer SET state = ?, uploadSessionID = COALESCE(?, uploadSessionID),
                    nextPart = COALESCE(?, nextPart), transferredBytes = COALESCE(?, transferredBytes),
                    totalBytes = COALESCE(?, totalBytes), progress = CASE WHEN COALESCE(?, totalBytes) > 0
                        THEN CAST(COALESCE(?, transferredBytes) AS DOUBLE) / COALESCE(?, totalBytes) ELSE 0 END,
                    lastError = ?, updatedAt = ? WHERE id = ?
                """, arguments: [state.rawValue, sessionID?.uuidString, nextPart, transferred, total, total, transferred, total, error, Date(), id.uuidString])
        }
    }

    func merge(_ remote: [APICatalogTrack], baseURL: URL) async throws {
        try await database.writer.write { db in
            for item in remote where item.status == "ready" {
                let sourceURL = baseURL.appending(path: item.streamPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
                var trackID = try String.fetchOne(db, sql: "SELECT trackID FROM trackSource WHERE contentHash = ? LIMIT 1", arguments: [item.contentHash])
                if trackID == nil {
                    trackID = UUID().uuidString
                    let now = Date()
                    try db.execute(sql: "INSERT INTO track(id,title,normalizedTitle,duration,createdAt,updatedAt) VALUES(?,?,?,?,?,?)",
                                   arguments: [trackID!, item.title, item.title.libraryNormalized, item.duration, now, now])
                    for (position, name) in Self.artistCredits(item.artist).enumerated() {
                        let artistID = try Self.artist(name, db: db)
                        try db.execute(
                            sql: "INSERT INTO artistCredit(id,trackID,artistID,role,position) VALUES(?,?,?,'primary',?)",
                            arguments: [UUID().uuidString, trackID!, artistID, position]
                        )
                    }
                    if let album = item.album {
                        let albumArtist = item.albumArtist ?? item.artist
                        let releaseID = try Self.release(album, artist: albumArtist, db: db)
                        try db.execute(sql: "INSERT OR IGNORE INTO releaseTrack(releaseID,trackID) VALUES(?,?)", arguments: [releaseID, trackID!])
                    }
                }
                let existingSource = try String.fetchOne(db, sql: "SELECT id FROM trackSource WHERE remoteFileID = ?", arguments: [item.id.uuidString])
                let sourceID = existingSource ?? UUID().uuidString
                try db.execute(sql: """
                    INSERT INTO trackSource(id,trackID,fileURL,contentHash,fileSize,modifiedAt,format,state,lastSeenScanID,sourceKind,remoteFileID,remoteURL,etag,addedByName)
                    VALUES(?,?,?,?,?,?,?,'available',?,'remote',?,?,?,?)
                    ON CONFLICT(id) DO UPDATE SET trackID=excluded.trackID, contentHash=excluded.contentHash, fileSize=excluded.fileSize,
                        format=excluded.format, state='available', remoteURL=excluded.remoteURL, etag=excluded.etag, addedByName=excluded.addedByName
                    """, arguments: [sourceID, trackID!, sourceURL, item.contentHash, Int64(item.byteSize) ?? 0, Date(), item.format ?? item.filename.pathExtension,
                                      UUID().uuidString, item.id.uuidString, sourceURL, "sha256-\(item.contentHash)", item.addedBy.displayName])
                if let artworkPath = item.artworkPath {
                    let artworkURL = baseURL.appending(path: artworkPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))).absoluteString
                    let artworkHash = "remote-\(item.contentHash)"
                    if let assetID = try String.fetchOne(db, sql: "SELECT id FROM mediaAsset WHERE contentHash=? LIMIT 1", arguments: [artworkHash]) {
                        try db.execute(sql: "UPDATE mediaAsset SET localURL=?,trackID=? WHERE id=?", arguments: [artworkURL, trackID!, assetID])
                    } else {
                        try db.execute(sql: "INSERT INTO mediaAsset(id,trackID,kind,localURL,contentHash,mimeType,createdAt) VALUES(?,?,'artwork',?,?, 'image/jpeg',?)",
                                       arguments: [UUID().uuidString, trackID!, artworkURL, artworkHash, Date()])
                    }
                }
                try Self.rebuildFTS(trackID!, db: db)
            }
        }
    }

    func enqueueDownload(trackID: String) async throws {
        try await database.writer.write { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT id, contentHash, fileSize FROM trackSource WHERE trackID=? AND sourceKind='remote' LIMIT 1", arguments: [trackID]) else { return }
            let sourceID: String = row["id"]
            let contentHash: String = row["contentHash"]
            let fileSize: Int64 = row["fileSize"]
            let alreadyQueued = try Bool.fetchOne(db, sql: """
                SELECT EXISTS(SELECT 1 FROM mediaTransfer
                WHERE trackID=? AND direction='download' AND state IN ('queued','running','paused'))
                """, arguments: [trackID]) ?? false
            guard !alreadyQueued else { return }
            try db.execute(sql: "INSERT INTO mediaTransfer(id,trackID,sourceID,contentHash,direction,state,totalBytes,createdAt,updatedAt) VALUES(?,?,?,?,'download','queued',?,?,?)",
                           arguments: [UUID().uuidString, trackID, sourceID, contentHash, fileSize, Date(), Date()])
        }
    }

    func transfers() async throws -> [MediaTransfer] {
        try await database.writer.read { db in
            let rows = try Row.fetchAll(db, sql: "SELECT mt.*, COALESCE(t.title, mt.contentHash) title FROM mediaTransfer mt LEFT JOIN track t ON t.id=mt.trackID ORDER BY mt.updatedAt DESC")
            return rows.compactMap { row in
                guard let id = UUID(uuidString: row["id"]), let direction = MediaTransferDirection(rawValue: row["direction"]),
                      let state = MediaTransferState(rawValue: row["state"]) else { return nil }
                let sessionValue: String? = row["uploadSessionID"]
                return MediaTransfer(id: id, trackID: row["trackID"], sourceID: row["sourceID"], contentHash: row["contentHash"], title: row["title"],
                                     direction: direction, state: state, progress: row["progress"], transferredBytes: row["transferredBytes"],
                                     totalBytes: row["totalBytes"], uploadSessionID: sessionValue.flatMap { UUID(uuidString: $0) }, nextPart: row["nextPart"], lastError: row["lastError"])
            }
        }
    }

    func setTransferState(_ id: UUID, _ state: MediaTransferState, progress: Double? = nil, error: String? = nil, resumeData: Data? = nil) async throws {
        try await database.writer.write { db in
            try db.execute(sql: "UPDATE mediaTransfer SET state=?, progress=COALESCE(?,progress), lastError=?, resumeData=COALESCE(?,resumeData), updatedAt=? WHERE id=?",
                           arguments: [state.rawValue, progress, error, resumeData, Date(), id.uuidString])
        }
    }

    func downloadRequest(_ id: UUID) async throws -> (URL, Data?)? {
        try await database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT sx.remoteURL, mt.resumeData FROM mediaTransfer mt JOIN trackSource sx ON sx.id=mt.sourceID WHERE mt.id=?", arguments: [id.uuidString]),
                  let value: String = row["remoteURL"], let url = URL(string: value) else { return nil }
            let resumeData: Data? = row["resumeData"]
            return (url, resumeData)
        }
    }

    func finishDownload(_ id: UUID, temporaryURL: URL) async throws {
        let metadata: (trackID: String, hash: String, format: String)? = try await database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT mt.trackID,mt.contentHash,sx.format FROM mediaTransfer mt JOIN trackSource sx ON sx.id=mt.sourceID WHERE mt.id=?", arguments: [id.uuidString]) else { return nil }
            let trackID: String = row["trackID"]
            let hash: String = row["contentHash"]
            let format: String = row["format"]
            return (trackID: trackID, hash: hash, format: format)
        }
        guard let metadata else { throw CocoaError(.fileNoSuchFile) }
        let actualHash = try Self.sha256(temporaryURL)
        guard actualHash == metadata.hash else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw CocoaError(.fileReadCorruptFile)
        }
        try await database.writer.write { db in
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("ShizoMusic/Downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let destination = root.appendingPathComponent("\(metadata.hash).\(metadata.format)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            let size = Int64((try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            try db.execute(sql: "DELETE FROM trackSource WHERE trackID=? AND sourceKind='downloaded'", arguments: [metadata.trackID])
            try db.execute(sql: "INSERT INTO trackSource(id,trackID,fileURL,contentHash,fileSize,modifiedAt,format,state,lastSeenScanID,sourceKind) VALUES(?,?,?,?,?,?,?,'available',?,'downloaded')",
                           arguments: [UUID().uuidString, metadata.trackID, destination.path, metadata.hash, size, Date(), metadata.format, UUID().uuidString])
            try db.execute(sql: "UPDATE mediaTransfer SET state='completed',progress=1,transferredBytes=totalBytes,resumeData=NULL,lastError=NULL,updatedAt=? WHERE id=?", arguments: [Date(), id.uuidString])
        }
    }

    func deleteLocalCopy(trackID: String) async throws -> Int {
        try await database.writer.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id,fileURL FROM trackSource WHERE trackID=? AND sourceKind IN ('local','downloaded')", arguments: [trackID])
            for row in rows {
                let path: String = row["fileURL"]
                let sourceID: String = row["id"]
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
                try db.execute(sql: "DELETE FROM trackSource WHERE id=?", arguments: [sourceID])
            }
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM trackSource WHERE trackID=? AND sourceKind='remote' AND state='available'", arguments: [trackID]) ?? 0
        }
    }

    func remoteSourceCount(trackID: String) async throws -> Int {
        try await database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM trackSource WHERE trackID=? AND sourceKind='remote' AND state='available'",
                arguments: [trackID]
            ) ?? 0
        }
    }

    func downloadedStorageBytes() async throws -> Int64 {
        try await database.writer.read { db in
            try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(fileSize),0) FROM trackSource WHERE sourceKind='downloaded' AND state='available'") ?? 0
        }
    }

    func removeAllDownloads() async throws {
        try await database.writer.write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id,fileURL FROM trackSource WHERE sourceKind='downloaded'")
            for row in rows {
                let path: String = row["fileURL"]
                let sourceID: String = row["id"]
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path))
                try db.execute(sql: "DELETE FROM trackSource WHERE id=?", arguments: [sourceID])
            }
        }
    }

    private static func artist(_ name: String, db: Database) throws -> String { if let id = try String.fetchOne(db, sql: "SELECT id FROM artist WHERE normalizedName=?", arguments: [name.libraryNormalized]) { return id }; let id=UUID().uuidString; try db.execute(sql:"INSERT INTO artist(id,name,normalizedName) VALUES(?,?,?)",arguments:[id,name,name.libraryNormalized]); return id }
    private static func artistCredits(_ value: String) -> [String] {
        let separated = value.replacingOccurrences(
            of: #"(?i)\s+(?:feat\.?|ft\.?|featuring|x)\s+|\s+&\s+|\s*;\s*"#,
            with: "\u{1f}",
            options: .regularExpression
        )
        let names = separated.components(separatedBy: "\u{1f}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return names.isEmpty ? [value] : names
    }
    private static func release(_ title: String, artist: String, db: Database) throws -> String { if let id = try String.fetchOne(db,sql:"SELECT id FROM albumRelease WHERE normalizedTitle=? AND normalizedAlbumArtist=?",arguments:[title.libraryNormalized,artist.libraryNormalized]) { return id }; let id=UUID().uuidString; try db.execute(sql:"INSERT INTO albumRelease(id,title,normalizedTitle,albumArtist,normalizedAlbumArtist,createdAt,updatedAt) VALUES(?,?,?,?,?,?,?)",arguments:[id,title,title.libraryNormalized,artist,artist.libraryNormalized,Date(),Date()]); return id }
    private static func rebuildFTS(_ trackID:String, db:Database)throws { try db.execute(sql:"DELETE FROM libraryFTS WHERE trackID=?",arguments:[trackID]); try db.execute(sql:"INSERT INTO libraryFTS(trackID,title,artists,album,aliases) SELECT t.id,t.title,COALESCE((SELECT GROUP_CONCAT(a.name,' ') FROM artistCredit ac JOIN artist a ON a.id=ac.artistID WHERE ac.trackID=t.id),''),COALESCE((SELECT r.title FROM releaseTrack rt JOIN albumRelease r ON r.id=rt.releaseID WHERE rt.trackID=t.id LIMIT 1),''),'' FROM track t WHERE t.id=?",arguments:[trackID]) }
    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private extension String { var pathExtension: String { (self as NSString).pathExtension.lowercased() } }
