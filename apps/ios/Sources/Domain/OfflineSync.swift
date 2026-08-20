import Foundation

enum SyncEntityType: String, Codable, Sendable { case playlist, playlistItem }
enum SyncOperationType: String, Codable, Sendable {
    case playlistUpsert = "playlist.upsert"
    case playlistDelete = "playlist.delete"
    case playlistItemInsert = "playlistItem.insert"
    case playlistItemMove = "playlistItem.move"
    case playlistItemRemove = "playlistItem.remove"
}
enum SyncOperationState: String, Codable, Sendable { case pending, failed }

struct SyncOperation: Identifiable, Codable, Sendable {
    let id: UUID
    let entityType: SyncEntityType
    let entityID: String
    let operationType: SyncOperationType
    let payload: String
    let createdAt: Date
    let attemptCount: Int
    let nextAttemptAt: Date
    let state: SyncOperationState
    let lastError: String?
}

struct SyncConflictRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let operationID: UUID
    let entityType: SyncEntityType
    let entityID: String
    let reason: String
    let localPayload: String
    let serverPayload: String
    let createdAt: Date
}

struct SyncOverview: Sendable {
    let pendingCount: Int
    let failedCount: Int
    let conflictCount: Int
    let cursor: Int64
    let lastSuccessfulSyncAt: Date?
    let lastError: String?
}

struct PlaylistSyncPayload: Codable, Sendable {
    let id: UUID
    let title: String
    let coverStyle: String
    let customCoverData: String?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct PlaylistItemSyncPayload: Codable, Sendable {
    let id: UUID
    let playlistId: UUID
    let trackId: String
    let rank: Double
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
}

struct RemoteSyncChange: Codable, Sendable {
    let id: UUID
    let cursor: String
    let actorDeviceId: UUID
    let entityType: SyncEntityType
    let entityId: String
    let operationType: SyncOperationType
    let payload: String
    let clientTimestamp: Date
}

protocol OfflineSyncRepository: Sendable {
    func prepareInitialOutbox() async throws
    func retryDeferredChanges() async throws
    func readyBatch(limit: Int) async throws -> [SyncOperation]
    func markAccepted(ids: [UUID]) async throws
    func markFailed(ids: [UUID], message: String, now: Date) async throws
    func retryAll() async throws
    func apply(changes: [RemoteSyncChange], cursor: Int64) async throws
    func record(conflicts: [SyncConflictRecord]) async throws
    func overview() async throws -> SyncOverview
    func conflicts() async throws -> [SyncConflictRecord]
}
