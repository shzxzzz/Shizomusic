import Foundation

@MainActor
final class ServerMusicSourceAdapter: MusicSourceAdapter {
    let id = "server"
    let capabilities: Set<MusicSourceCapability> = [.search, .stream, .download]
    private let authorization: AuthorizationStore
    private let cache: ProviderSearchCache

    init(authorization: AuthorizationStore, cache: ProviderSearchCache = ProviderSearchCache()) {
        self.authorization = authorization
        self.cache = cache
    }

    func search(query: String) async throws -> MusicSourceBatch {
        guard let credentials = try await authorization.syncCredentials() else { return MusicSourceBatch(results: [], failures: []) }
        let response = try await credentials.client.musicSearch(query: query, accessToken: credentials.accessToken)
        let results = response.results.map { item in
            MusicSearchResult(
                id: item.id, provider: item.provider, title: item.title, artist: item.artist,
                album: item.album, duration: item.duration,
                artworkURL: item.artworkURL.flatMap { credentials.client.absoluteURLOrRemote($0) },
                webpageURL: item.webpageURL.flatMap(URL.init(string:)),
                streamURL: item.streamPath.flatMap { credentials.client.absoluteURLOrRemote($0) },
                capabilities: Set(item.capabilities.compactMap(MusicSourceCapability.init(rawValue:))),
                attribution: item.attribution, localTrack: nil
            )
        }
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
        let results = response.results.map { item in
            MusicSearchResult(id: item.id, provider: item.provider, title: item.title, artist: item.artist,
                              album: item.album, duration: item.duration,
                              artworkURL: item.artworkURL.flatMap { credentials.client.absoluteURLOrRemote($0) },
                              webpageURL: item.webpageURL.flatMap(URL.init(string:)),
                              streamURL: item.streamPath.flatMap { credentials.client.absoluteURLOrRemote($0) },
                              capabilities: Set(item.capabilities.compactMap(MusicSourceCapability.init(rawValue:))),
                              attribution: item.attribution, localTrack: nil)
        }
        try await cache.save(results, query: query)
        return MusicSourceBatch(results: results, failures: response.failures.map {
            MusicSourceFailure(provider: $0.provider, kind: MusicSourceFailureKind(rawValue: $0.kind) ?? .temporary,
                               message: $0.message, retryAfterSeconds: $0.retryAfterSeconds)
        })
    }
}

@MainActor
final class MusicSearchStore: ObservableObject {
    @Published private(set) var results: [MusicSearchResult] = []
    @Published private(set) var failures: [MusicSourceFailure] = []
    @Published private(set) var isSearching = false

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
        async let serverTask = server.search(query: normalized)
        let offline = try? await localTask
        let remote = try? await serverTask
        guard !Task.isCancelled else { return }
        // The local branch is independent and remains visible if every remote source fails.
        results = deduplicated((offline?.results ?? []) + (remote?.results ?? []))
        failures = (offline?.failures ?? []) + (remote?.failures ?? [])
        if remote == nil { failures.append(.init(provider: "server", kind: .temporary, message: "search.server_unavailable", retryAfterSeconds: nil)) }
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
        "\(item.title.libraryNormalized)|\(item.artist.libraryNormalized)|\(Int(item.duration.rounded()))"
    }
}
