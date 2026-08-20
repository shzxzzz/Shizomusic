import Foundation

@MainActor
final class SyncEngine: ObservableObject {
    enum State: Equatable {
        case local
        case pending(Int)
        case syncing
        case synced
        case failed(String)
    }

    @Published private(set) var state: State = .local
    @Published private(set) var overview = SyncOverview(
        pendingCount: 0, failedCount: 0, conflictCount: 0, cursor: 0,
        lastSuccessfulSyncAt: nil, lastError: nil
    )
    @Published private(set) var conflicts: [SyncConflictRecord] = []

    private let authorization: AuthorizationStore
    private let repository: any OfflineSyncRepository
    private var isSynchronizing = false

    init(
        authorization: AuthorizationStore,
        repository: any OfflineSyncRepository = GRDBOfflineSyncRepository()
    ) {
        self.authorization = authorization
        self.repository = repository
    }

    func synchronize() async {
        guard !isSynchronizing else { return }
        isSynchronizing = true
        defer { isSynchronizing = false }
        do {
            guard let credentials = try await authorization.syncCredentials() else {
                overview = try await repository.overview()
                state = .local
                return
            }
            try await repository.prepareInitialOutbox()
            try await repository.retryDeferredChanges()
            await refreshOverview()
            state = .syncing

            while true {
                let batch = try await repository.readyBatch(limit: 50)
                guard !batch.isEmpty else { break }
                do {
                    let response = try await credentials.client.syncPush(
                        operations: batch.map(Self.apiOperation),
                        accessToken: credentials.accessToken
                    )
                    try await repository.markAccepted(ids: response.acceptedOperationIds)
                    try await repository.record(conflicts: response.conflicts.compactMap(Self.conflict))
                } catch {
                    try await repository.markFailed(ids: batch.map(\.id), message: error.localizedDescription, now: Date())
                    if let apiError = error as? APIErrorResponse { authorization.handleSyncError(apiError) }
                    throw error
                }
            }

            let currentOverview = try await repository.overview()
            var cursor = currentOverview.cursor
            while true {
                let response = try await credentials.client.syncPull(cursor: cursor, accessToken: credentials.accessToken)
                let nextCursor = Int64(response.cursor) ?? cursor
                try await repository.apply(changes: response.changes.compactMap(Self.change), cursor: nextCursor)
                cursor = nextCursor
                if !response.hasMore { break }
            }
            await refreshOverview()
            state = overview.failedCount > 0 || overview.conflictCount > 0
                ? .failed(overview.lastError ?? String(localized: "sync.failed"))
                : overview.pendingCount > 0 ? .pending(overview.pendingCount) : .synced
        } catch {
            await refreshOverview()
            if error is URLError {
                let waiting = overview.pendingCount + overview.failedCount
                state = waiting > 0 ? .pending(waiting) : .local
            } else {
                state = .failed(error.localizedDescription)
            }
        }
    }

    func retry() async {
        try? await repository.retryAll()
        await synchronize()
    }

    func refreshOverview() async {
        if let value = try? await repository.overview() { overview = value }
        if let values = try? await repository.conflicts() { conflicts = values }
        if !isSynchronizing {
            if overview.failedCount > 0 || overview.conflictCount > 0 {
                state = .failed(overview.lastError ?? String(localized: "sync.failed"))
            }
            else if overview.pendingCount > 0 { state = .pending(overview.pendingCount) }
        }
    }

    private static func apiOperation(_ operation: SyncOperation) -> APISyncOperation {
        APISyncOperation(
            id: operation.id,
            entityType: operation.entityType,
            entityId: operation.entityID,
            operationType: operation.operationType,
            payload: operation.payload,
            clientTimestamp: ISO8601DateFormatter().string(from: operation.createdAt)
        )
    }

    private static func conflict(_ value: APISyncConflict) -> SyncConflictRecord? {
        guard let date = parseDate(value.createdAt) else { return nil }
        return SyncConflictRecord(
            id: value.id, operationID: value.operationId, entityType: value.entityType,
            entityID: value.entityId, reason: value.reason, localPayload: value.localPayload,
            serverPayload: value.serverPayload, createdAt: date
        )
    }

    private static func change(_ value: APISyncChange) -> RemoteSyncChange? {
        guard let date = parseDate(value.clientTimestamp) else { return nil }
        return RemoteSyncChange(
            id: value.id, cursor: value.cursor, actorDeviceId: value.actorDeviceId,
            entityType: value.entityType, entityId: value.entityId,
            operationType: value.operationType, payload: value.payload, clientTimestamp: date
        )
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
