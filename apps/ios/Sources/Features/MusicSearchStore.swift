import Foundation

@MainActor
final class ServerMusicSourceAdapter: MusicSourceAdapter {
    let id = "server"
    let capabilities: Set<MusicSourceCapability> = [.search, .stream, .acquire]
    private let authorization: AuthorizationStore
    private let cache: ProviderSearchCache

    init(authorization: AuthorizationStore, cache: ProviderSearchCache = ProviderSearchCache()) {
        self.authorization = authorization
        self.cache = cache
    }

    func authorizationCredentials() async throws -> AuthorizationStore.SyncCredentials? {
        try await authorization.syncCredentials()
    }

    func search(query: String) async throws -> MusicSourceBatch {
        guard let credentials = try await authorization.syncCredentials() else { return MusicSourceBatch(results: [], failures: []) }
        let response = try await credentials.client.musicSearch(query: query, accessToken: credentials.accessToken)
        let results = response.results.compactMap { map($0, client: credentials.client) }
        // Cache must complete before the values become visible to SwiftUI.
        try await cache.save(results, query: query)
        return MusicSourceBatch(results: results, failures: response.failures.map {
            MusicSourceFailure(provider: $0.provider, kind: MusicSourceFailureKind(rawValue: $0.kind) ?? .temporary,
                               message: $0.message, retryAfterSeconds: $0.retryAfterSeconds)
        })
    }

    func retry(provider: String, query: String) async throws -> MusicSourceBatch {
        guard let credentials = try await authorization.syncCredentials() else { return MusicSourceBatch(results: [], failures: []) }
        let response = try await credentials.client.retryMusicProvider(provider: provider, query: query, accessToken: credentials.accessToken)
        let results = response.results.compactMap { map($0, client: credentials.client) }
        try await cache.save(results, query: query)
        return MusicSourceBatch(results: results, failures: response.failures.map {
            MusicSourceFailure(provider: $0.provider, kind: MusicSourceFailureKind(rawValue: $0.kind) ?? .temporary,
                               message: $0.message, retryAfterSeconds: $0.retryAfterSeconds)
        })
    }

    private func map(_ item: APIMusicSearchItem, client: GeneratedAPIClient) -> MusicSearchResult? {
        guard let entityType = ExternalEntityType(rawValue: item.entityType),
              let referenceType = ExternalEntityType(rawValue: item.metadataSource.reference.entityType) else { return nil }
        let reference = ExternalEntityReference(provider: item.metadataSource.reference.provider, entityType: referenceType,
                                                externalID: item.metadataSource.reference.externalID,
                                                canonicalURL: item.metadataSource.reference.canonicalURL.flatMap(URL.init(string:)))
        return MusicSearchResult(id: item.id, entityType: entityType, reference: reference,
            metadataProvider: item.metadataSource.provider, audioProvider: item.audioSource?.provider,
            acquisitionMethod: ExternalAcquisitionMethod(rawValue: item.acquisition.method) ?? .unavailable,
            canAcquire: item.acquisition.allowed, title: item.title, artist: item.artist, release: item.release,
            duration: item.duration, artworkURL: item.artworkURL.flatMap { client.absoluteURLOrRemote($0) },
            streamURL: item.audioSource?.resolverPath.flatMap { client.absoluteURLOrRemote($0) },
            attribution: item.attribution, localTrack: nil)
    }
}

@MainActor
final class MusicSearchStore: ObservableObject {
    @Published private(set) var results: [MusicSearchResult] = []
    @Published private(set) var failures: [MusicSourceFailure] = []
    @Published private(set) var isSearching = false
    @Published private(set) var acquisitionJobs: [APIAcquisitionJob] = []
    @Published private(set) var acquisitionError: String?

    private let local: LocalFTSMusicSourceAdapter
    private let server: ServerMusicSourceAdapter

    init(authorization: AuthorizationStore) {
        local = LocalFTSMusicSourceAdapter()
        server = ServerMusicSourceAdapter(authorization: authorization)
    }

    func search(_ query: String) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { results = []; failures = []; isSearching = false; return }
        isSearching = true
        defer { isSearching = false }
        async let localTask = local.search(query: normalized)
        var remote: MusicSourceBatch?
        var remoteError: Error?
        do { remote = try await server.search(query: normalized) }
        catch { remoteError = error }
        let offline = try? await localTask
        guard !Task.isCancelled else { return }
        // The local branch is independent and remains visible if every remote source fails.
        results = deduplicated((offline?.results ?? []) + (remote?.results ?? []))
        failures = (offline?.failures ?? []) + (remote?.failures ?? [])
        if let remoteError {
            let detail: String
            if let apiError = remoteError as? APIErrorResponse {
                detail = "\(apiError.messageKey) [\(apiError.requestID)]"
            } else { detail = remoteError.localizedDescription }
            failures.append(.init(provider: "server", kind: .temporary, message: detail, retryAfterSeconds: nil))
        }
    }

    func retry(_ provider: String, query: String) async {
        if provider == "server" {
            await search(query)
            return
        }
        do {
            let batch = try await server.retry(provider: provider, query: query)
            results = deduplicated(results.filter { $0.provider != provider } + batch.results)
            failures.removeAll { $0.provider == provider }
            failures.append(contentsOf: batch.failures)
        } catch {
            failures.removeAll { $0.provider == provider }
            failures.append(.init(provider: provider, kind: .temporary, message: error.localizedDescription, retryAfterSeconds: nil))
        }
    }

    func acquire(_ result: MusicSearchResult) async {
        guard result.canAcquire else { return }
        do {
            guard let credentials = try await server.authorizationCredentials() else { return }
            _ = try await credentials.client.createAcquisition(result: result, accessToken: credentials.accessToken)
            await reloadAcquisitions()
        } catch { acquisitionError = error.localizedDescription }
    }

    func reloadAcquisitions() async {
        do {
            guard let credentials = try await server.authorizationCredentials() else { acquisitionJobs = []; return }
            acquisitionJobs = try await credentials.client.acquisitions(accessToken: credentials.accessToken)
        } catch { acquisitionError = error.localizedDescription }
    }

    func retryAcquisition(_ id: UUID) async {
        do {
            guard let credentials = try await server.authorizationCredentials() else { return }
            _ = try await credentials.client.retryAcquisition(id: id, accessToken: credentials.accessToken)
            await reloadAcquisitions()
        } catch { acquisitionError = error.localizedDescription }
    }

    private func deduplicated(_ values: [MusicSearchResult]) -> [MusicSearchResult] {
        var seen = Set<String>()
        let offlineFingerprints = Set(values.filter { $0.provider == "offline" }.map(fingerprint))
        return values.filter { item in
            guard seen.insert(item.stableID).inserted else { return false }
            // The shared catalog may point to the same logical track that is already
            // in Music. Prefer the physical offline source instead of showing twins.
            return item.provider != "catalog" || !offlineFingerprints.contains(fingerprint(item))
        }
    }

    private func fingerprint(_ item: MusicSearchResult) -> String {
        let normalizedArtist = item.artist?.libraryNormalized ?? ""
        return "\(item.title.libraryNormalized)|\(normalizedArtist)|\(Int(item.duration.rounded()))"
    }
}
