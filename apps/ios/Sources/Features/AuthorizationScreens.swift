import PhotosUI
import SwiftUI

struct AuthorizationRootView: View {
    @EnvironmentObject private var authorization: AuthorizationStore

    var body: some View {
        Group {
            switch authorization.phase {
            case .loading:
                ProgressView("auth.loading")
            case .unauthenticated:
                InvitationEntryScreen()
            case let .profile(token):
                ProfileOnboardingScreen(onboardingToken: token)
            case .authenticated, .localOnly:
                LibraryView(authorization: authorization)
            case let .invalidInvitation(messageKey):
                AuthorizationFailureScreen(
                    icon: "ticket.fill",
                    title: "auth.invitation_problem_title",
                    detail: LocalizedStringKey(messageKey),
                    action: authorization.retryInvitation
                )
            case .revoked:
                AuthorizationFailureScreen(
                    icon: "iphone.slash",
                    title: "auth.device_revoked_title",
                    detail: "auth.device_revoked_detail",
                    action: authorization.retryInvitation
                )
            }
        }
        .environmentObject(authorization)
        .preferredColorScheme(.dark)
        .task { await authorization.restore() }
    }
}

private struct InvitationEntryScreen: View {
    @EnvironmentObject private var authorization: AuthorizationStore
    @State private var code = ""
    @State private var serverURL = UserDefaults.standard.string(forKey: "auth.serverURL") ?? "https://shizomusic.example.ts.net"

    var body: some View {
        AuthorizationBackground {
            VStack(spacing: 22) {
                Image(systemName: "music.note.house.fill").font(.system(size: 54)).foregroundStyle(.purple.gradient)
                Text("auth.welcome_title").font(.largeTitle.bold())
                Text("auth.welcome_detail").foregroundStyle(.secondary).multilineTextAlignment(.center)
                TextField("auth.server_url", text: $serverURL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .textFieldStyle(.roundedBorder)
                TextField("auth.invitation_code", text: $code)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                if let error = authorization.errorMessage { Text(verbatim: error).font(.footnote).foregroundStyle(.red) }
                Button("auth.continue") { Task { await authorization.redeem(code: code, serverURL: serverURL) } }
                    .buttonStyle(.borderedProminent).tint(.purple)
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authorization.isWorking)
                Button("auth.local_only", action: authorization.useLocalOnly)
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ProfileOnboardingScreen: View {
    @EnvironmentObject private var authorization: AuthorizationStore
    let onboardingToken: String
    @State private var displayName = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var avatarData: Data?

    var body: some View {
        // PhotosPicker's label is @Sendable in the current SDK. Capture an immutable
        // snapshot instead of reading main-actor State from that closure.
        let currentAvatarData = avatarData
        AuthorizationBackground {
            VStack(spacing: 22) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Group {
                        if let currentAvatarData, let image = UIImage(data: currentAvatarData) {
                            Image(uiImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus").resizable().scaledToFit().padding(22)
                        }
                    }
                    .frame(width: 120, height: 120).clipShape(Circle())
                    .background(.thinMaterial, in: Circle())
                }
                Text("auth.profile_title").font(.largeTitle.bold())
                TextField("auth.display_name", text: $displayName).textFieldStyle(.roundedBorder)
                if let error = authorization.errorMessage { Text(verbatim: error).font(.footnote).foregroundStyle(.red) }
                Button("auth.finish") {
                    Task { await authorization.completeProfile(onboardingToken: onboardingToken, displayName: displayName, avatarData: avatarData) }
                }
                .buttonStyle(.borderedProminent).tint(.purple)
                .disabled(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || authorization.isWorking)
            }
            .onChange(of: photoItem) {
                guard let photoItem else { return }
                Task { avatarData = try? await photoItem.loadTransferable(type: Data.self) }
            }
        }
    }
}

private struct AuthorizationFailureScreen: View {
    let icon: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        AuthorizationBackground {
            VStack(spacing: 18) {
                Image(systemName: icon).font(.system(size: 52)).foregroundStyle(.orange)
                Text(title).font(.title.bold())
                Text(detail).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("auth.try_again", action: action).buttonStyle(.borderedProminent).tint(.purple)
            }
        }
    }
}

private struct AuthorizationBackground<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.027, blue: 0.04).ignoresSafeArea()
            RadialGradient(colors: [.purple.opacity(0.28), .clear], center: .top, startRadius: 20, endRadius: 520).ignoresSafeArea()
            content.frame(maxWidth: 430).padding(28)
        }
    }
}

struct AccessManagementScreen: View {
    @EnvironmentObject private var authorization: AuthorizationStore

    var body: some View {
        List {
            Section {
                Button("auth.create_invitation") { Task { await authorization.createInvitation() } }
                if let invitation = authorization.latestInvitation {
                    LabeledContent("auth.invitation_code", value: invitation.code)
                    LabeledContent("auth.expires", value: invitation.expiresAt)
                }
            }
            Section("auth.devices") {
                ForEach(authorization.devices) { device in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(verbatim: device.name)
                            Text(verbatim: device.lastSeenAt).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if device.revokedAt == nil {
                            Menu("auth.revoke") {
                                Button("auth.revoke_device", role: .destructive) { Task { await authorization.revokeDevice(device) } }
                                Button("auth.revoke_user", role: .destructive) { Task { await authorization.revokeUser(for: device) } }
                            }
                        } else {
                            Text("auth.revoked").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("auth.access_management")
        .task { await authorization.loadDevices() }
    }
}
