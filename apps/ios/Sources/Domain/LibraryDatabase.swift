import Foundation
import GRDB

final class LibraryDatabase: @unchecked Sendable {
    static let shared: LibraryDatabase = {
        do { return try LibraryDatabase() }
        catch { fatalError("Unable to open ShizoMusic database: \(error)") }
    }()

    let writer: DatabasePool

    init(path: String? = nil) throws {
        let databasePath: String
        if let path {
            databasePath = path
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ShizoMusic", isDirectory: true)
            try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
            databasePath = support.appendingPathComponent("library.sqlite").path
        }

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        configuration.busyMode = .timeout(5)
        configuration.label = "ShizoMusic.Library"
        writer = try DatabasePool(path: databasePath, configuration: configuration)
        try Self.migrator.migrate(writer)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1.domain-library") { db in
            try db.execute(sql: """
                CREATE TABLE track (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    normalizedTitle TEXT NOT NULL,
                    duration DOUBLE NOT NULL,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                );
                CREATE TABLE trackSource (
                    id TEXT PRIMARY KEY NOT NULL,
                    trackID TEXT NOT NULL REFERENCES track(id) ON DELETE CASCADE,
                    fileURL TEXT NOT NULL UNIQUE,
                    contentHash TEXT NOT NULL,
                    fileSize INTEGER NOT NULL,
                    modifiedAt DATETIME NOT NULL,
                    format TEXT NOT NULL,
                    state TEXT NOT NULL,
                    lastSeenScanID TEXT NOT NULL
                );
                CREATE INDEX trackSource_trackID ON trackSource(trackID);
                CREATE INDEX trackSource_contentHash ON trackSource(contentHash);

                CREATE TABLE artist (
                    id TEXT PRIMARY KEY NOT NULL,
                    name TEXT NOT NULL,
                    normalizedName TEXT NOT NULL UNIQUE
                );
                CREATE TABLE artistAlias (
                    id TEXT PRIMARY KEY NOT NULL,
                    artistID TEXT NOT NULL REFERENCES artist(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    normalizedName TEXT NOT NULL,
                    UNIQUE(artistID, normalizedName)
                );
                CREATE TABLE artistCredit (
                    id TEXT PRIMARY KEY NOT NULL,
                    trackID TEXT NOT NULL REFERENCES track(id) ON DELETE CASCADE,
                    artistID TEXT NOT NULL REFERENCES artist(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    position INTEGER NOT NULL,
                    UNIQUE(trackID, artistID, role)
                );
                CREATE INDEX artistCredit_trackID ON artistCredit(trackID);
                CREATE INDEX artistCredit_artistID ON artistCredit(artistID);

                CREATE TABLE albumRelease (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    normalizedTitle TEXT NOT NULL,
                    albumArtist TEXT NOT NULL,
                    normalizedAlbumArtist TEXT NOT NULL,
                    artworkAssetID TEXT,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL,
                    UNIQUE(normalizedTitle, normalizedAlbumArtist)
                );
                CREATE TABLE releaseTrack (
                    releaseID TEXT NOT NULL REFERENCES albumRelease(id) ON DELETE CASCADE,
                    trackID TEXT NOT NULL REFERENCES track(id) ON DELETE CASCADE,
                    discNumber INTEGER,
                    trackNumber INTEGER,
                    PRIMARY KEY(releaseID, trackID)
                );
                CREATE INDEX releaseTrack_trackID ON releaseTrack(trackID);

                CREATE TABLE mediaAsset (
                    id TEXT PRIMARY KEY NOT NULL,
                    trackID TEXT REFERENCES track(id) ON DELETE CASCADE,
                    releaseID TEXT REFERENCES albumRelease(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    localURL TEXT NOT NULL,
                    contentHash TEXT NOT NULL,
                    mimeType TEXT,
                    createdAt DATETIME NOT NULL
                );
                CREATE INDEX mediaAsset_trackID ON mediaAsset(trackID);
                CREATE INDEX mediaAsset_releaseID ON mediaAsset(releaseID);
                CREATE INDEX mediaAsset_contentHash ON mediaAsset(contentHash);

                CREATE VIRTUAL TABLE libraryFTS USING fts5(
                    trackID UNINDEXED,
                    title,
                    artists,
                    album,
                    aliases,
                    tokenize='unicode61 remove_diacritics 2'
                );

                CREATE TABLE queueState (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    currentItemID TEXT,
                    elapsedSeconds DOUBLE NOT NULL DEFAULT 0,
                    shuffleEnabled INTEGER NOT NULL DEFAULT 0,
                    repeatMode TEXT NOT NULL DEFAULT 'off',
                    contextType TEXT NOT NULL DEFAULT 'adHoc',
                    contextID TEXT,
                    updatedAt DATETIME NOT NULL
                );
                CREATE TABLE queueItem (
                    id TEXT PRIMARY KEY NOT NULL,
                    trackID TEXT NOT NULL REFERENCES track(id),
                    position INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    enqueuedAt DATETIME NOT NULL
                );
                CREATE UNIQUE INDEX queueItem_position ON queueItem(position);
                CREATE INDEX queueItem_trackID ON queueItem(trackID);
                CREATE INDEX queueItem_status ON queueItem(status);
                """)
        }
        migrator.registerMigration("v2.playlists") { db in
            try db.execute(sql: """
                CREATE TABLE playlist (
                    id TEXT PRIMARY KEY NOT NULL,
                    title TEXT NOT NULL,
                    coverStyle TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    updatedAt DATETIME NOT NULL
                );
                CREATE TABLE playlistItem (
                    id TEXT PRIMARY KEY NOT NULL,
                    playlistID TEXT NOT NULL REFERENCES playlist(id) ON DELETE CASCADE,
                    trackID TEXT NOT NULL REFERENCES track(id),
                    rank DOUBLE NOT NULL,
                    createdAt DATETIME NOT NULL
                );
                CREATE INDEX playlistItem_playlist_rank ON playlistItem(playlistID, rank);
                CREATE INDEX playlistItem_trackID ON playlistItem(trackID);
                """)
        }
        migrator.registerMigration("v3.analytics-and-playlist-covers") { db in
            try db.execute(sql: "ALTER TABLE playlist ADD COLUMN customCoverPath TEXT")
            try db.execute(sql: """
                DELETE FROM playlistItem
                WHERE id NOT IN (
                    SELECT id FROM (
                        SELECT id, ROW_NUMBER() OVER (
                            PARTITION BY playlistID, trackID
                            ORDER BY rank, createdAt, id
                        ) AS rowNumber
                        FROM playlistItem
                    ) WHERE rowNumber = 1
                );
                CREATE UNIQUE INDEX playlistItem_unique_track ON playlistItem(playlistID, trackID);

                CREATE TABLE listeningEvent (
                    id TEXT PRIMARY KEY NOT NULL,
                    sessionID TEXT NOT NULL,
                    trackID TEXT NOT NULL REFERENCES track(id),
                    eventType TEXT NOT NULL,
                    occurredAt DATETIME NOT NULL,
                    position DOUBLE NOT NULL,
                    fromPosition DOUBLE,
                    toPosition DOUBLE,
                    listenedSeconds DOUBLE NOT NULL DEFAULT 0,
                    contextType TEXT NOT NULL,
                    contextID TEXT
                );
                CREATE INDEX listeningEvent_session ON listeningEvent(sessionID, occurredAt);
                CREATE INDEX listeningEvent_track_date ON listeningEvent(trackID, occurredAt);
                CREATE INDEX listeningEvent_type_date ON listeningEvent(eventType, occurredAt);
                """)
        }
        migrator.registerMigration("v4.offline-sync") { db in
            try db.execute(sql: """
                ALTER TABLE playlist ADD COLUMN syncStatus TEXT NOT NULL DEFAULT 'local';
                ALTER TABLE playlist ADD COLUMN lastSyncedCursor INTEGER NOT NULL DEFAULT 0;

                CREATE TABLE syncOperation (
                    id TEXT PRIMARY KEY NOT NULL,
                    entityType TEXT NOT NULL,
                    entityID TEXT NOT NULL,
                    operationType TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    attemptCount INTEGER NOT NULL DEFAULT 0,
                    nextAttemptAt DATETIME NOT NULL,
                    state TEXT NOT NULL DEFAULT 'pending',
                    lastError TEXT
                );
                CREATE INDEX syncOperation_ready ON syncOperation(state, nextAttemptAt, createdAt);
                CREATE INDEX syncOperation_entity ON syncOperation(entityType, entityID);

                CREATE TABLE syncState (
                    id INTEGER PRIMARY KEY CHECK(id = 1),
                    cursor INTEGER NOT NULL DEFAULT 0,
                    lastSuccessfulSyncAt DATETIME,
                    lastError TEXT
                );
                INSERT INTO syncState(id, cursor) VALUES (1, 0);

                CREATE TABLE syncConflict (
                    id TEXT PRIMARY KEY NOT NULL,
                    operationID TEXT NOT NULL,
                    entityType TEXT NOT NULL,
                    entityID TEXT NOT NULL,
                    reason TEXT NOT NULL,
                    localPayload TEXT NOT NULL,
                    serverPayload TEXT NOT NULL,
                    createdAt DATETIME NOT NULL,
                    resolvedAt DATETIME
                );
                CREATE INDEX syncConflict_unresolved ON syncConflict(resolvedAt, createdAt);

                """)
        }
        migrator.registerMigration("v5.deferred-sync-changes") { db in
            try db.execute(sql: """
                CREATE TABLE IF NOT EXISTS syncDeferredChange (
                    operationID TEXT PRIMARY KEY NOT NULL,
                    cursor INTEGER NOT NULL,
                    actorDeviceID TEXT NOT NULL,
                    entityType TEXT NOT NULL,
                    entityID TEXT NOT NULL,
                    operationType TEXT NOT NULL,
                    payload TEXT NOT NULL,
                    clientTimestamp DATETIME NOT NULL,
                    reason TEXT NOT NULL
                );
                """)
        }
        return migrator
    }
}
