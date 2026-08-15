import SwiftUI

struct FriendsScreenPreviewState: Sendable {
    var searchQuery: String
    var friends: [FriendPreviewModel]

    static let populated = FriendsScreenPreviewState(
        searchQuery: "",
        friends: FriendPreviewModel.samples
    )

    static let empty = FriendsScreenPreviewState(searchQuery: "", friends: [])

    static let nobodyOnline = FriendsScreenPreviewState(
        searchQuery: "",
        friends: FriendPreviewModel.samples.map {
            FriendPreviewModel(
                id: $0.id,
                displayName: $0.displayName,
                avatarStyle: $0.avatarStyle,
                isOnline: false,
                isListening: false
            )
        }
    )

    static let noSearchResults = FriendsScreenPreviewState(
        searchQuery: "Zoe",
        friends: FriendPreviewModel.samples
    )
}

struct FriendsScreen: View {
    @State private var state: FriendsScreenPreviewState
    @State private var path: [FriendProfileDestination] = []

    private let onFriendTapped: (String) -> Void

    init(
        state: FriendsScreenPreviewState = .populated,
        onFriendTapped: @escaping (String) -> Void = { _ in }
    ) {
        _state = State(initialValue: state)
        self.onFriendTapped = onFriendTapped
    }

    private var trimmedQuery: String {
        state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var onlineFriends: [FriendPreviewModel] {
        state.friends
            .filter(\.isOnline)
            .sorted { lhs, rhs in
                if lhs.isListening != rhs.isListening {
                    return lhs.isListening && !rhs.isListening
                }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    private var offlineFriends: [FriendPreviewModel] {
        state.friends
            .filter { !$0.isOnline }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private var filteredFriends: [FriendPreviewModel] {
        state.friends
            .filter { $0.displayName.localizedCaseInsensitiveContains(trimmedQuery) }
            .sorted { lhs, rhs in
                if lhs.isOnline != rhs.isOnline { return lhs.isOnline && !rhs.isOnline }
                if lhs.isListening != rhs.isListening { return lhs.isListening && !rhs.isListening }
                return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
            }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                FriendsBackground()

                List {
                    if state.friends.isEmpty {
                        FriendsEmptyState()
                    } else if !trimmedQuery.isEmpty {
                        if filteredFriends.isEmpty {
                            FriendsSearchEmptyState()
                        } else {
                            FriendsSection(
                                titleKey: "friends.results",
                                friends: filteredFriends,
                                onTap: openFriend
                            )
                        }
                    } else {
                        if onlineFriends.isEmpty {
                            Section("friends.online") {
                                Text("friends.nobody_online")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .listRowBackground(Color.clear)
                            }
                        } else {
                            FriendsSection(
                                titleKey: "friends.online",
                                friends: onlineFriends,
                                onTap: openFriend
                            )
                        }

                        FriendsSection(
                            titleKey: "friends.offline",
                            friends: offlineFriends,
                            onTap: openFriend
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("friends.title")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $state.searchQuery,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: Text("friends.search_placeholder")
            )
            .toolbarBackground(.hidden, for: .navigationBar)
            .navigationDestination(for: FriendProfileDestination.self) { destination in
                FriendProfileScreen(destination: destination)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func openFriend(_ friend: FriendPreviewModel) {
        onFriendTapped(friend.id)
        path.append(FriendProfileDestination(id: friend.id, displayName: friend.displayName))
    }
}

struct FriendsSection: View {
    let titleKey: LocalizedStringKey
    let friends: [FriendPreviewModel]
    let onTap: (FriendPreviewModel) -> Void

    var body: some View {
        Section {
            ForEach(friends) { friend in
                FriendRow(friend: friend, onTap: { onTap(friend) })
            }
        } header: {
            Text(titleKey)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(.white.opacity(0.50))
        }
    }
}

struct FriendRow: View {
    let friend: FriendPreviewModel
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 13) {
                FriendAvatar(friend: friend)
                    .frame(width: 52, height: 52)

                Text(verbatim: friend.displayName)
                    .font(.system(.body, design: .rounded, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 10)

                FriendPresenceIndicator(friend: friend)
            }
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(FriendRowButtonStyle())
        .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
        .listRowBackground(Color.clear)
        .listRowSeparatorTint(.white.opacity(0.08))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityText: Text {
        if friend.isOnline && friend.isListening {
            return Text(verbatim: friend.displayName)
                + Text(verbatim: ", ")
                + Text("friends.status_online")
                + Text(verbatim: ", ")
                + Text("friends.status_listening")
        }

        return Text(verbatim: friend.displayName)
            + Text(verbatim: ", ")
            + Text(LocalizedStringKey(friend.isOnline ? "friends.status_online" : "friends.status_offline"))
    }
}

struct FriendPresenceIndicator: View {
    let friend: FriendPreviewModel

    var body: some View {
        if friend.isOnline {
            HStack(spacing: 8) {
                if friend.isListening {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.58))
                }

                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
            }
            .accessibilityHidden(true)
        }
    }
}

struct FriendAvatar: View {
    let friend: FriendPreviewModel

    var body: some View {
        ZStack {
            switch friend.avatarStyle {
            case let .image(name):
                Image(name)
                    .resizable()
                    .scaledToFill()
            case .violet:
                LinearGradient(colors: [.purple.opacity(0.88), .indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .amber:
                LinearGradient(colors: [.orange.opacity(0.88), .red.opacity(0.58), .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .neutral:
                Circle().fill(.thinMaterial)
                Text(verbatim: friend.initial)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.78))
            }
        }
        .clipShape(Circle())
        .overlay {
            Circle().stroke(.white.opacity(0.13), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

struct FriendsSearchEmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("friends.search_empty_title")
                .font(.headline)
            Text("friends.search_empty_detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 58)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct FriendsEmptyState: View {
    var body: some View {
        VStack(spacing: 9) {
            Text("friends.empty_title")
                .font(.headline)
            Text("friends.empty_detail")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .padding(.vertical, 70)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

struct FriendProfileDestination: Hashable, Sendable {
    let id: String
    let displayName: String
}

private struct FriendsBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.027, green: 0.029, blue: 0.037)
            LinearGradient(
                colors: [.indigo.opacity(0.12), .clear, .black.opacity(0.14)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .ignoresSafeArea()
    }
}

private struct FriendRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .background(
                configuration.isPressed ? Color.white.opacity(0.055) : Color.clear,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .opacity(configuration.isPressed ? 0.80 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

enum FriendAvatarStyle: Hashable, Sendable {
    case image(String)
    case violet
    case amber
    case neutral
}

struct FriendPreviewModel: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let avatarStyle: FriendAvatarStyle
    let isOnline: Bool
    let isListening: Bool

    var initial: String {
        String(displayName.prefix(1)).uppercased()
    }

    static let samples = [
        FriendPreviewModel(id: "alex", displayName: "Alex", avatarStyle: .image("ArtistHero"), isOnline: true, isListening: true),
        FriendPreviewModel(id: "nikita", displayName: "Nikita", avatarStyle: .image("AuroraShore"), isOnline: true, isListening: true),
        FriendPreviewModel(id: "max", displayName: "Max", avatarStyle: .violet, isOnline: true, isListening: false),
        FriendPreviewModel(id: "kate", displayName: "Kate", avatarStyle: .image("MistyLake"), isOnline: true, isListening: false),
        FriendPreviewModel(id: "dima", displayName: "Dima", avatarStyle: .amber, isOnline: false, isListening: false),
        FriendPreviewModel(id: "misha", displayName: "Misha", avatarStyle: .neutral, isOnline: false, isListening: false),
        FriendPreviewModel(id: "anna", displayName: "Anna", avatarStyle: .image("AuroraShore"), isOnline: false, isListening: false),
        FriendPreviewModel(id: "roman", displayName: "Roman", avatarStyle: .neutral, isOnline: false, isListening: false)
    ]
}

#Preview("Friends") {
    FriendsScreen()
}

#Preview("Friends nobody online") {
    FriendsScreen(state: .nobodyOnline)
}

#Preview("Friends empty") {
    FriendsScreen(state: .empty)
}

#Preview("Friends search empty") {
    FriendsScreen(state: .noSearchResults)
}
