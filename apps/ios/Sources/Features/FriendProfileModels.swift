import SwiftUI

enum FriendProfileTab: String, CaseIterable, Hashable, Sendable {
    case nowPlaying
    case queue

    var titleKey: LocalizedStringKey {
        switch self {
        case .nowPlaying: "friend_profile.now_playing"
        case .queue: "friend_profile.queue"
        }
    }
}
enum FriendSyncState: String, Hashable, Sendable {
    case disconnected
    case synchronized
    case reconnecting
    case lost

    var titleKey: LocalizedStringKey {
        switch self {
        case .disconnected: "friend_profile.sync_disconnected"
        case .synchronized: "friend_profile.sync_synchronized"
        case .reconnecting: "friend_profile.sync_reconnecting"
        case .lost: "friend_profile.sync_lost"
        }
    }

    var systemImage: String {
        switch self {
        case .disconnected: "person.2"
        case .synchronized: "checkmark.circle.fill"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .lost: "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .disconnected: .secondary
        case .synchronized: .green
        case .reconnecting: .orange
        case .lost: .red
        }
    }
}

struct FriendCurrentTrack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artistName: String
    let artworkName: String
    let positionText: String
    let durationText: String
    let progress: Double
    let isPlaying: Bool

    static let sample = FriendCurrentTrack(
        id: "friend-dancing-in-flames",
        title: "Dancing In The Flames",
        artistName: "The Weeknd",
        artworkName: "ArtistHero",
        positionText: "1:42",
        durationText: "3:57",
        progress: 0.43,
        isPlaying: true
    )
}

struct FriendQueueItem: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artistName: String
    let durationText: String
    let artworkName: String

    static let samples = [
        FriendQueueItem(id: "friend-sao-paulo", title: "São Paulo", artistName: "The Weeknd", durationText: "3:37", artworkName: "AuroraShore"),
        FriendQueueItem(id: "friend-open-hearts", title: "Open Hearts", artistName: "The Weeknd", durationText: "3:49", artworkName: "MistyLake"),
        FriendQueueItem(id: "friend-take-my-breath", title: "Take My Breath", artistName: "The Weeknd", durationText: "3:40", artworkName: "ArtistHero")
    ]
}

enum FriendSavedKind: String, CaseIterable, Hashable, Sendable {
    case playlists
    case releases
    case artists
    case liked

    var titleKey: LocalizedStringKey {
        switch self {
        case .playlists: "friend_profile.saved_playlists"
        case .releases: "friend_profile.saved_releases"
        case .artists: "friend_profile.saved_artists"
        case .liked: "friend_profile.saved_liked"
        }
    }

    var systemImage: String {
        switch self {
        case .playlists: "music.note.list"
        case .releases: "square.stack"
        case .artists: "person.2"
        case .liked: "heart.fill"
        }
    }

    var countKey: String {
        switch self {
        case .playlists: "friend_profile.saved_playlists_count"
        case .releases: "friend_profile.saved_releases_count"
        case .artists: "friend_profile.saved_artists_count"
        case .liked: "friend_profile.saved_liked_count"
        }
    }

    var usesCircularArtwork: Bool { self == .artists }
}

struct FriendSavedItem: Identifiable, Hashable, Sendable {
    let kind: FriendSavedKind
    let artworkNames: [String]

    var id: FriendSavedKind { kind }

    static let samples = [
        FriendSavedItem(kind: .playlists, artworkNames: ["AuroraShore", "MistyLake", "ArtistHero"]),
        FriendSavedItem(kind: .releases, artworkNames: ["ArtistHero", "AuroraShore", "MistyLake"]),
        FriendSavedItem(kind: .artists, artworkNames: ["ArtistHero", "MistyLake", "AuroraShore"]),
        FriendSavedItem(kind: .liked, artworkNames: ["MistyLake", "ArtistHero", "AuroraShore"])
    ]
}

struct FriendSuggestionTrack: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artistName: String
    let artworkName: String

    static let samples = [
        FriendSuggestionTrack(id: "suggest-rumble", title: "Rumble", artistName: "Skrillex, Fred again..", artworkName: "AuroraShore"),
        FriendSuggestionTrack(id: "suggest-blinding", title: "Blinding Lights", artistName: "The Weeknd", artworkName: "ArtistHero"),
        FriendSuggestionTrack(id: "suggest-pulse", title: "Пульс тишины", artistName: "Эхо Внутри", artworkName: "MistyLake")
    ]
}

struct FriendSavedDestination: Hashable, Sendable {
    let friendName: String
    let kind: FriendSavedKind
}

struct FriendProfileState: Sendable {
    let id: String
    let displayName: String
    let avatarStyle: FriendAvatarStyle
    let isOnline: Bool
    var selectedTab: FriendProfileTab
    let currentTrack: FriendCurrentTrack?
    let queue: [FriendQueueItem]
    var isConnected: Bool
    var syncState: FriendSyncState
    let savedContent: [FriendSavedItem]

    static func make(for destination: FriendProfileDestination) -> FriendProfileState {
        let friend = FriendModel.samples.first { $0.id == destination.id }
        let isOnline = friend?.isOnline ?? true
        let isListening = friend?.isListening ?? true

        return FriendProfileState(
            id: destination.id,
            displayName: destination.displayName,
            avatarStyle: friend?.avatarStyle ?? .neutral,
            isOnline: isOnline,
            selectedTab: .nowPlaying,
            currentTrack: isOnline && isListening ? .sample : nil,
            queue: isOnline && isListening ? FriendQueueItem.samples : [],
            isConnected: false,
            syncState: .disconnected,
            savedContent: FriendSavedItem.samples
        )
    }

    static let onlineListening = make(for: FriendProfileDestination(id: "alex", displayName: "Alex"))

    static var connected: FriendProfileState {
        var state = onlineListening
        state.isConnected = true
        state.syncState = .synchronized
        return state
    }

    static var queueTab: FriendProfileState {
        var state = onlineListening
        state.selectedTab = .queue
        return state
    }

    static let onlineIdle = FriendProfileState(
        id: "kate",
        displayName: "Kate",
        avatarStyle: .image("MistyLake"),
        isOnline: true,
        selectedTab: .nowPlaying,
        currentTrack: nil,
        queue: [],
        isConnected: false,
        syncState: .disconnected,
        savedContent: FriendSavedItem.samples
    )

    static let offline = FriendProfileState(
        id: "dima",
        displayName: "Dima",
        avatarStyle: .amber,
        isOnline: false,
        selectedTab: .nowPlaying,
        currentTrack: nil,
        queue: [],
        isConnected: false,
        syncState: .disconnected,
        savedContent: FriendSavedItem.samples
    )

    static var reconnecting: FriendProfileState {
        var state = connected
        state.syncState = .reconnecting
        return state
    }
}

struct FriendProfileActions {
    var onConnectTapped: () -> Void = {}
    var onDisconnectTapped: () -> Void = {}
    var onCurrentTrackTapped: () -> Void = {}
    var onSuggestTrackTapped: () -> Void = {}
    var onQueueTrackTapped: (String) -> Void = { _ in }
    var onFriendPlaylistsTapped: () -> Void = {}
    var onFriendReleasesTapped: () -> Void = {}
    var onFriendArtistsTapped: () -> Void = {}
    var onFriendLikedTracksTapped: () -> Void = {}

    func savedAction(for kind: FriendSavedKind) -> () -> Void {
        switch kind {
        case .playlists: onFriendPlaylistsTapped
        case .releases: onFriendReleasesTapped
        case .artists: onFriendArtistsTapped
        case .liked: onFriendLikedTracksTapped
        }
    }
}
