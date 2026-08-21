import Foundation
import UIKit

@MainActor
final class AuthorizationStore: ObservableObject {
    struct SyncCredentials: Sendable {
        let client: GeneratedAPIClient
        let accessToken: String
    }
    enum Phase {
        case loading
        case unauthenticated
        case profile(onboardingToken: String)
        case authenticated(APIAuthSession)
        case invalidInvitation(messageKey: String)
        case revoked
        case localOnly
    }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var devices: [APIDevice] = []
    @Published private(set) var latestInvitation: APIInvitation?

    private var client: GeneratedAPIClient
    private let keychain: KeychainTokenStore
    private let defaults: UserDefaults

    init(
        baseURL: URL = URL(string: "https://shizomusic.example.ts.net")!,
        keychain: KeychainTokenStore = KeychainTokenStore(),
        defaults: UserDefaults = .standard
    ) {
        let storedURL = defaults.string(forKey: "auth.serverURL").flatMap(URL.init(string:)) ?? baseURL
        self.client = GeneratedAPIClient(baseURL: storedURL)
        self.keychain = keychain
        self.defaults = defaults
    }

    var currentUser: APIUser? {
        guard case let .authenticated(session) = phase else { return nil }
        return session.user
    }

    var serverURLString: String { client.baseURL.absoluteString }

    @discardableResult
    func updateServerURL(_ value: String) async -> Bool {
        guard let url = Self.normalizedServerURL(value) else {
            errorMessage = String(localized: "auth.server_invalid")
            return false
        }

        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        let candidate = GeneratedAPIClient(baseURL: url)

        switch phase {
        case let .authenticated(current):
            do {
                // Verify the existing session at the new endpoint before replacing
                // the working client. Refresh only when the access token is expiring.
                var session = current
                if Self.isExpiringSoon(current.accessExpiresAt) {
                    session = try await candidate.refresh(refreshToken: current.refreshToken)
                    try save(session)
                } else {
                    _ = try await candidate.currentUser(accessToken: current.accessToken)
                }
                client = candidate
                defaults.set(url.absoluteString, forKey: "auth.serverURL")
                phase = .authenticated(session)
                return true
            } catch let error as APIErrorResponse {
                errorMessage = String(localized: String.LocalizationValue(error.messageKey))
                return false
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        case .localOnly:
            client = candidate
            defaults.set(url.absoluteString, forKey: "auth.serverURL")
            defaults.set(false, forKey: "auth.localOnly")
            phase = .unauthenticated
            return true
        default:
            client = candidate
            defaults.set(url.absoluteString, forKey: "auth.serverURL")
            return true
        }
    }

    func restore() async {
        guard case .loading = phase else { return }
        if defaults.bool(forKey: "auth.localOnly") {
            phase = .localOnly
            return
        }
        guard let refreshToken = keychain.read("refreshToken") else {
            phase = .unauthenticated
            return
        }
        await run {
            let session = try await self.client.refresh(refreshToken: refreshToken)
            try self.save(session)
            self.phase = .authenticated(session)
        }
    }

    func redeem(code: String, serverURL: String) async {
        guard let url = Self.normalizedServerURL(serverURL) else {
            errorMessage = String(localized: "auth.server_invalid")
            return
        }
        client = GeneratedAPIClient(baseURL: url)
        defaults.set(url.absoluteString, forKey: "auth.serverURL")
        let deviceIdentifier = persistentDeviceIdentifier()
        await run {
            let ticket = try await self.client.redeemInvitation(
                code: code,
                deviceIdentifier: deviceIdentifier,
                deviceName: UIDevice.current.name
            )
            self.phase = .profile(onboardingToken: ticket.onboardingToken)
        }
    }

    func completeProfile(onboardingToken: String, displayName: String, avatarData: Data?) async {
        await run {
            let session = try await self.client.completeOnboarding(
                token: onboardingToken,
                displayName: displayName,
                avatarData: avatarData?.base64EncodedString()
            )
            try self.save(session)
            self.defaults.set(false, forKey: "auth.localOnly")
            self.phase = .authenticated(session)
        }
    }

    func useLocalOnly() {
        defaults.set(true, forKey: "auth.localOnly")
        phase = .localOnly
    }

    func leaveLocalOnly() {
        defaults.set(false, forKey: "auth.localOnly")
        phase = .unauthenticated
    }

    func retryInvitation() {
        errorMessage = nil
        phase = .unauthenticated
    }

    func logout() async {
        if let refreshToken = keychain.read("refreshToken") { try? await client.logout(refreshToken: refreshToken) }
        clearSession()
        phase = .unauthenticated
    }

    func loadDevices() async {
        guard case let .authenticated(session) = phase, session.user.role == .owner else { return }
        await run { self.devices = try await self.client.devices(accessToken: session.accessToken) }
    }

    func createInvitation(expiresInHours: Int = 72) async {
        guard case let .authenticated(session) = phase, session.user.role == .owner else { return }
        await run { self.latestInvitation = try await self.client.createInvitation(expiresInHours: expiresInHours, accessToken: session.accessToken) }
    }

    func revokeDevice(_ device: APIDevice) async {
        guard case let .authenticated(session) = phase, session.user.role == .owner else { return }
        await run {
            try await self.client.revokeDevice(id: device.id, accessToken: session.accessToken)
            self.devices = try await self.client.devices(accessToken: session.accessToken)
        }
    }

    func revokeUser(for device: APIDevice) async {
        guard case let .authenticated(session) = phase, session.user.role == .owner else { return }
        await run {
            try await self.client.revokeUser(id: device.userId, accessToken: session.accessToken)
            self.devices = try await self.client.devices(accessToken: session.accessToken)
        }
    }

    func syncCredentials() async throws -> SyncCredentials? {
        guard case let .authenticated(current) = phase else { return nil }
        var session = current
        if Self.isExpiringSoon(session.accessExpiresAt) {
            session = try await client.refresh(refreshToken: session.refreshToken)
            try save(session)
            phase = .authenticated(session)
        }
        return SyncCredentials(client: client, accessToken: session.accessToken)
    }

    func handleSyncError(_ error: APIErrorResponse) {
        guard error.code == "device_revoked" || error.code == "unauthorized" else { return }
        clearSession()
        phase = error.code == "device_revoked" ? .revoked : .unauthenticated
    }

    private func run(_ operation: () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
            errorMessage = nil
        } catch let error as APIErrorResponse {
            errorMessage = String(localized: String.LocalizationValue(error.messageKey))
            switch error.code {
            case "invalid_invitation", "expired_invitation", "invitation_used":
                phase = .invalidInvitation(messageKey: error.messageKey)
            case "device_revoked":
                clearSession()
                phase = .revoked
            case "unauthorized":
                clearSession()
                phase = .unauthenticated
            default:
                if case .loading = phase { phase = .unauthenticated }
            }
        } catch {
            errorMessage = error.localizedDescription
            if case .loading = phase {
                if let cached = cachedSession() {
                    phase = .authenticated(cached)
                    errorMessage = nil
                } else {
                    phase = .unauthenticated
                }
            }
        }
    }

    private func save(_ session: APIAuthSession) throws {
        try keychain.write(session.refreshToken, account: "refreshToken")
        try keychain.write(session.accessToken, account: "accessToken")
        let cached = CachedIdentity(
            user: session.user,
            device: session.device,
            accessExpiresAt: session.accessExpiresAt,
            refreshExpiresAt: session.refreshExpiresAt
        )
        defaults.set(try JSONEncoder().encode(cached), forKey: "auth.cachedIdentity")
    }

    private func clearSession() {
        keychain.delete("refreshToken")
        keychain.delete("accessToken")
        defaults.removeObject(forKey: "auth.cachedIdentity")
    }

    private func persistentDeviceIdentifier() -> String {
        if let existing = keychain.read("deviceIdentifier") { return existing }
        let value = UUID().uuidString
        try? keychain.write(value, account: "deviceIdentifier")
        return value
    }

    private static func normalizedServerURL(_ value: String) -> URL? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }

    private static func isExpiringSoon(_ value: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .distantPast
        return date.timeIntervalSinceNow < 60
    }

    private func cachedSession() -> APIAuthSession? {
        guard let data = defaults.data(forKey: "auth.cachedIdentity"),
              let identity = try? JSONDecoder().decode(CachedIdentity.self, from: data),
              let accessToken = keychain.read("accessToken"),
              let refreshToken = keychain.read("refreshToken") else { return nil }
        return APIAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            accessExpiresAt: identity.accessExpiresAt,
            refreshExpiresAt: identity.refreshExpiresAt,
            user: identity.user,
            device: identity.device
        )
    }

    private struct CachedIdentity: Codable {
        let user: APIUser
        let device: APIDevice
        let accessExpiresAt: String
        let refreshExpiresAt: String
    }
}
