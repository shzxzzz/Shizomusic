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
}
