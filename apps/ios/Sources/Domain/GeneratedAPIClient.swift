// Generated from contracts/openapi.yaml. Do not hand-edit endpoint signatures.
import Foundation

struct APIUser: Codable, Sendable {
    enum Role: String, Codable, Sendable { case owner, member }
    let id: UUID
    let displayName: String
    let avatarData: String?
    let role: Role
}

struct APIDevice: Codable, Identifiable, Sendable {
    let id: UUID
    let userId: UUID
    let name: String
    let createdAt: String
    let lastSeenAt: String
    let revokedAt: String?
}

struct APIAuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: String
    let refreshExpiresAt: String
    let user: APIUser
    let device: APIDevice
}

struct APIOnboardingTicket: Codable, Sendable {
    let onboardingToken: String
    let expiresInSeconds: Int
}

struct APIInvitation: Codable, Sendable {
    let code: String
    let expiresAt: String
}

struct APIErrorResponse: Codable, Error, Sendable {
    let code: String
    let messageKey: String
    let requestID: String
}

struct APISyncOperation: Codable, Sendable {
    let id: UUID
    let entityType: SyncEntityType
    let entityId: String
    let operationType: SyncOperationType
    let payload: String
    let clientTimestamp: String
}

struct APISyncConflict: Codable, Sendable {
    let id: UUID
    let operationId: UUID
    let entityType: SyncEntityType
    let entityId: String
    let reason: String
    let localPayload: String
    let serverPayload: String
    let createdAt: String
}

struct APISyncPushResponse: Codable, Sendable {
    let acceptedOperationIds: [UUID]
    let cursor: String
    let conflicts: [APISyncConflict]
}

struct APISyncChange: Codable, Sendable {
    let id: UUID
    let cursor: String
    let actorDeviceId: UUID
    let entityType: SyncEntityType
    let entityId: String
    let operationType: SyncOperationType
    let payload: String
    let clientTimestamp: String
}

struct APISyncPullResponse: Codable, Sendable {
    let changes: [APISyncChange]
    let cursor: String
    let hasMore: Bool
}

struct APICatalogTrack: Codable, Identifiable, Sendable {
    struct AddedBy: Codable, Sendable { let id: UUID; let displayName: String }
    let id: UUID
    let contentHash: String
    let byteSize: String
    let mimeType: String
    let filename: String
    let status: String
    let title: String
    let artist: String
    let album: String?
    let albumArtist: String?
    let duration: Double
    let format: String?
    let codec: String?
    let addedBy: AddedBy
    let streamPath: String
    let artworkPath: String?
    let createdAt: String
}

struct APIUploadSession: Codable, Sendable {
    let id: UUID
    let partSize: Int
    let totalParts: Int
    let uploadedParts: [Int]
    let expiresAt: String
    let alreadyAvailableFileId: UUID?
}

struct APIUploadCompletion: Codable, Sendable { let fileId: UUID; let contentHash: String; let status: String }

struct APIMusicSearchItem: Codable, Sendable {
    struct Reference: Codable, Sendable { let provider: String; let entityType: String; let externalID: String; let canonicalURL: String? }
    struct Source: Codable, Sendable { let provider: String; let reference: Reference }
    struct AudioSource: Codable, Sendable { let provider: String; let reference: Reference; let resolverPath: String? }
    struct Acquisition: Codable, Sendable { let provider: String; let reference: Reference; let method: String; let allowed: Bool }
    let id: String
    let entityType: String
    let title: String
    let artist: String?
    let release: String?
    let duration: Double
    let artworkURL: String?
    let metadataSource: Source
    let audioSource: AudioSource?
    let acquisition: Acquisition
    let attribution: String
}

struct APIMusicSourceFailure: Codable, Sendable {
    let provider: String
    let kind: String
    let message: String
    let retryAfterSeconds: Int?
}

struct APIMusicSearchResponse: Codable, Sendable {
    let results: [APIMusicSearchItem]
    let failures: [APIMusicSourceFailure]
}

struct APIExternalArtistLibrary: Codable, Sendable {
    let artist: APIMusicSearchItem
    let releases: [APIMusicSearchItem]
    let tracks: [APIMusicSearchItem]
}

struct APIAcquisitionJob: Codable, Identifiable, Sendable {
    let id: UUID
    let reference: APIMusicSearchItem.Reference
    let method: String
    let title: String
    let artist: String?
    let artworkURL: String?
    let state: String
    let progress: Double
    let attemptCount: Int
    let maxAttempts: Int
    let errorCode: String?
    let errorDetail: String?
    let catalogFileID: UUID?
    let createdAt: String
    let updatedAt: String
}

struct GeneratedAPIClient: Sendable {
    let baseURL: URL
    var session: URLSession = .shared

    func redeemInvitation(code: String, deviceIdentifier: String, deviceName: String) async throws -> APIOnboardingTicket {
        try await post(
            path: "auth/invitations/redeem",
            body: RedeemBody(code: code, deviceIdentifier: deviceIdentifier, deviceName: deviceName),
            accessToken: nil
        )
    }

    func completeOnboarding(token: String, displayName: String, avatarData: String?) async throws -> APIAuthSession {
        try await post(
            path: "auth/onboarding/complete",
            body: CompleteBody(onboardingToken: token, displayName: displayName, avatarData: avatarData),
            accessToken: nil
        )
    }

    func refresh(refreshToken: String) async throws -> APIAuthSession {
        try await post(path: "auth/refresh", body: RefreshBody(refreshToken: refreshToken), accessToken: nil)
    }

    func currentUser(accessToken: String) async throws -> APIUser {
        try await get(path: "me", accessToken: accessToken)
    }

    func devices(accessToken: String) async throws -> [APIDevice] {
        try await get(path: "admin/devices", accessToken: accessToken)
    }

    func createInvitation(expiresInHours: Int, accessToken: String) async throws -> APIInvitation {
        try await post(path: "admin/invitations", body: InvitationBody(expiresInHours: expiresInHours), accessToken: accessToken)
    }

    func revokeDevice(id: UUID, accessToken: String) async throws {
        try await postWithoutResponse(path: "admin/devices/\(id.uuidString)/revoke", accessToken: accessToken)
    }

    func revokeUser(id: UUID, accessToken: String) async throws {
        try await postWithoutResponse(path: "admin/users/\(id.uuidString)/revoke", accessToken: accessToken)
    }

    func logout(refreshToken: String) async throws {
        try await postWithoutResponse(path: "auth/logout", body: RefreshBody(refreshToken: refreshToken), accessToken: nil)
    }

    func syncPush(operations: [APISyncOperation], accessToken: String) async throws -> APISyncPushResponse {
        try await post(path: "sync/push", body: SyncPushBody(operations: operations), accessToken: accessToken)
    }

    func syncPull(cursor: Int64, limit: Int = 200, accessToken: String) async throws -> APISyncPullResponse {
        var components = URLComponents(url: baseURL.appending(path: "sync/pull"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "cursor", value: String(cursor)), URLQueryItem(name: "limit", value: String(limit))]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func catalog(accessToken: String) async throws -> [APICatalogTrack] {
        let response: CatalogResponse = try await get(path: "catalog", accessToken: accessToken)
        return response.tracks
    }

    func musicSearch(query: String, accessToken: String) async throws -> APIMusicSearchResponse {
        var components = URLComponents(url: baseURL.appending(path: "search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func retryMusicProvider(provider: String, query: String, accessToken: String) async throws -> APIMusicSearchResponse {
        try await post(path: "search/providers/\(provider)/retry", body: SearchRetryBody(query: query, limit: 30), accessToken: accessToken)
    }

    func externalArtistLibrary(provider: String, externalID: String, name: String, accessToken: String) async throws -> APIExternalArtistLibrary {
        let safeProvider = provider.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? provider
        let safeID = externalID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? externalID
        var components = URLComponents(url: baseURL.appending(path: "external/artists/\(safeProvider)/\(safeID)"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    func createAcquisition(result: MusicSearchResult, accessToken: String) async throws -> APIAcquisitionJob {
        let reference = APIMusicSearchItem.Reference(provider: result.reference.provider, entityType: result.reference.entityType.rawValue,
                                                     externalID: result.reference.externalID, canonicalURL: result.reference.canonicalURL?.absoluteString)
        return try await post(path: "acquisitions", body: AcquisitionBody(reference: reference, method: result.acquisitionMethod.rawValue,
                              title: result.title, artist: result.artist, artworkURL: result.artworkURL?.absoluteString), accessToken: accessToken)
    }

    func acquisitions(accessToken: String) async throws -> [APIAcquisitionJob] {
        let response: AcquisitionListResponse = try await get(path: "acquisitions", accessToken: accessToken)
        return response.jobs
    }

    func retryAcquisition(id: UUID, accessToken: String) async throws -> APIAcquisitionJob {
        try await post(path: "acquisitions/\(id.uuidString)/retry", body: EmptyBody(), accessToken: accessToken)
    }

    func createUpload(filename: String, mimeType: String, byteSize: Int64, sha256: String, accessToken: String) async throws -> APIUploadSession {
        try await post(path: "catalog/uploads", body: UploadBody(filename: filename, mimeType: mimeType, byteSize: String(byteSize), sha256: sha256, partSize: 8 * 1_024 * 1_024), accessToken: accessToken)
    }

    func completeUpload(id: UUID, accessToken: String) async throws -> APIUploadCompletion {
        try await post(path: "catalog/uploads/\(id.uuidString)/complete", body: EmptyBody(), accessToken: accessToken)
    }

    func cancelUpload(id: UUID, accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: "catalog/uploads/\(id.uuidString)"))
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        try await performWithoutResponse(request)
    }

    func uploadPartRequest(uploadID: UUID, partNumber: Int, sha256: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "catalog/uploads/\(uploadID.uuidString)/parts/\(partNumber)"))
        request.httpMethod = "PUT"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(sha256, forHTTPHeaderField: "X-Part-SHA256")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return request
    }

    func absoluteURL(path: String) -> URL { baseURL.appending(path: path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }

    func absoluteURLOrRemote(_ value: String) -> URL? {
        if let url = URL(string: value), url.scheme != nil { return url }
        return absoluteURL(path: value)
    }

    private func get<Response: Decodable>(path: String, accessToken: String) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await perform(request)
    }

    private func post<Body: Encodable, Response: Decodable>(path: String, body: Body, accessToken: String?) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        return try await perform(request)
    }

    private func postWithoutResponse(path: String, accessToken: String) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        try await performWithoutResponse(request)
    }

    private func postWithoutResponse<Body: Encodable>(path: String, body: Body, accessToken: String?) async throws {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        try await performWithoutResponse(request)
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func performWithoutResponse(_ request: URLRequest) async throws {
        let (data, response) = try await session.data(for: request)
        try validate(data: data, response: response)
    }

    private func validate(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(http.statusCode) else {
            if let apiError = try? JSONDecoder().decode(APIErrorResponse.self, from: data) { throw apiError }
            throw URLError(.badServerResponse)
        }
    }

    private struct RedeemBody: Encodable { let code: String; let deviceIdentifier: String; let deviceName: String }
    private struct CompleteBody: Encodable { let onboardingToken: String; let displayName: String; let avatarData: String? }
    private struct RefreshBody: Encodable { let refreshToken: String }
    private struct InvitationBody: Encodable { let expiresInHours: Int }
    private struct SyncPushBody: Encodable { let operations: [APISyncOperation] }
    private struct UploadBody: Encodable { let filename: String; let mimeType: String; let byteSize: String; let sha256: String; let partSize: Int }
    private struct SearchRetryBody: Encodable { let query: String; let limit: Int }
    private struct AcquisitionBody: Encodable { let reference: APIMusicSearchItem.Reference; let method: String; let title: String; let artist: String?; let artworkURL: String? }
    private struct AcquisitionListResponse: Decodable { let jobs: [APIAcquisitionJob] }
    private struct CatalogResponse: Decodable { let tracks: [APICatalogTrack] }
    private struct EmptyBody: Encodable {}
}
