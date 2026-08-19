import SwiftUI

struct FriendProfileScreen: View {
    @Environment(\.dismiss) private var dismiss

    @State private var state: FriendProfileState
    @State private var heroBottom: CGFloat = 1_000
    @State private var showsSuggestionSheet = false
    @State private var noticeKey: String?

    private let actions: FriendProfileActions

    init(
        destination: FriendProfileDestination,
        initialState: FriendProfileState? = nil,
        actions: FriendProfileActions = FriendProfileActions()
    ) {
        _state = State(initialValue: initialState ?? .make(for: destination))
        self.actions = actions
    }

    private var showsStickyHeader: Bool { heroBottom < 70 }

    var body: some View {
        ZStack(alignment: .top) {
            FriendProfileBackground(isListening: state.currentTrack != nil)

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 26) {
                    FriendProfileHero(
                        state: state,
                        onBack: { dismiss() },
                        onMenuAction: { noticeKey = $0 }
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: FriendProfileHeroBottomKey.self,
                                value: proxy.frame(in: .named("friend-profile-scroll")).maxY
                            )
                        }
                    }

                    FriendProfileSegmentedControl(selection: $state.selectedTab)

                    activeTabContent

                    if let noticeKey {
                        FriendProfileNotice(key: noticeKey, displayName: state.displayName)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    FriendSavedContentSection(
                        displayName: state.displayName,
                        items: state.savedContent,
                        actions: actions
                    )
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 36)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "friend-profile-scroll")
            .onPreferenceChange(FriendProfileHeroBottomKey.self) { heroBottom = $0 }

            if showsStickyHeader {
                FriendProfileStickyHeader(
                    displayName: state.displayName,
                    isOnline: state.isOnline,
                    isConnected: state.isConnected,
                    onBack: { dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.20), value: showsStickyHeader)
        .animation(.easeInOut(duration: 0.18), value: state.selectedTab)
        .animation(.easeInOut(duration: 0.18), value: state.isConnected)
        .sheet(isPresented: $showsSuggestionSheet) {
            FriendTrackSuggestionSheet(displayName: state.displayName) { _ in
                noticeKey = "friend_profile.suggested"
            }
        }
        .navigationDestination(for: FriendSavedDestination.self) { destination in
            FriendSavedPlaceholderView(destination: destination)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var activeTabContent: some View {
        switch state.selectedTab {
        case .nowPlaying:
            FriendNowPlayingContent(
                state: state,
                onCurrentTrackTapped: actions.onCurrentTrackTapped,
                onConnect: connect,
                onDisconnect: disconnect
            )
        case .queue:
            FriendQueueContent(
                state: state,
                onTrackTapped: actions.onQueueTrackTapped,
                onSuggest: {
                    actions.onSuggestTrackTapped()
                    showsSuggestionSheet = true
                }
            )
        }
    }

    private func connect() {
        actions.onConnectTapped()
        state.isConnected = true
        state.syncState = .synchronized
    }

    private func disconnect() {
        actions.onDisconnectTapped()
        state.isConnected = false
        state.syncState = .disconnected
    }
}
private struct FriendProfileHero: View {
    let state: FriendProfileState
    let onBack: () -> Void
    let onMenuAction: (String) -> Void

    private var friend: FriendModel {
        FriendModel(
            id: state.id,
            displayName: state.displayName,
            avatarStyle: state.avatarStyle,
            isOnline: state.isOnline,
            isListening: state.currentTrack != nil
        )
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel(Text("collection.back"))

                Spacer()

                Menu {
                    Button("friend_profile.more_details") { onMenuAction("friend_profile.details_later") }
                    Button("friend_profile.copy_name") { onMenuAction("friend_profile.name_copied") }
                    Button("friend_profile.diagnostics") { onMenuAction("friend_profile.diagnostics_later") }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel(Text("friend_profile.more_actions"))
            }

            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Color.purple.opacity(0.24))
                    .frame(width: 154, height: 154)
                    .blur(radius: 28)

                FriendAvatar(friend: friend)
                    .frame(width: 116, height: 116)
                    .padding(8)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay { Circle().stroke(.white.opacity(0.18), lineWidth: 1) }

                if state.isOnline {
                    Circle()
                        .fill(.green)
                        .frame(width: 12, height: 12)
                        .overlay { Circle().stroke(Color.black.opacity(0.70), lineWidth: 2) }
                        .offset(x: -8, y: -8)
                        .accessibilityHidden(true)
                }
            }

            Text(verbatim: state.displayName)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            Text(verbatim: state.displayName)
                + Text(verbatim: ", ")
                + Text(LocalizedStringKey(state.isOnline ? "friends.status_online" : "friends.status_offline"))
        )
    }
}

private struct FriendProfileSegmentedControl: View {
    @Binding var selection: FriendProfileTab

    var body: some View {
        HStack(spacing: 5) {
            ForEach(FriendProfileTab.allCases, id: \.self) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.titleKey)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == tab ? .white : .white.opacity(0.48))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .background {
                            if selection == tab {
                                Capsule().fill(.thinMaterial)
                                    .overlay { Capsule().fill(Color.purple.opacity(0.25)) }
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay { Capsule().stroke(.white.opacity(0.11), lineWidth: 1) }
    }
}

private struct FriendNowPlayingContent: View {
    let state: FriendProfileState
    let onCurrentTrackTapped: () -> Void
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !state.isOnline {
                FriendProfileEmptyMessage(key: "friend_profile.unavailable", systemImage: "person.slash")
            } else if let track = state.currentTrack {
                FriendCurrentTrackCard(track: track, onTap: onCurrentTrackTapped)

                if state.isConnected {
                    FriendConnectedStatus(syncState: state.syncState, onDisconnect: onDisconnect)
                } else {
                    Button(action: onConnect) {
                        Label("friend_profile.connect", systemImage: "person.2.fill")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .background(Color.purple.opacity(0.62), in: Capsule())
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        Text("friend_profile.connect_accessibility") + Text(verbatim: " \(state.displayName)")
                    )
                }
            } else {
                FriendProfileEmptyMessage(key: "friend_profile.nothing_playing", systemImage: "music.note")
            }
        }
    }
}

private struct FriendCurrentTrackCard: View {
    let track: FriendCurrentTrack
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(track.artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 82, height: 82)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: track.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                    Text(verbatim: track.artistName)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                    Text(verbatim: "\(track.positionText) / \(track.durationText)")
                        .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.44))

                    ProgressView(value: track.progress)
                        .tint(.white.opacity(0.78))
                }

                Image(systemName: track.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.52))
                    .frame(width: 28)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            Text(verbatim: "\(track.title), \(track.artistName), \(track.positionText) / \(track.durationText)")
        )
    }
}

private struct FriendConnectedStatus: View {
    let syncState: FriendSyncState
    let onDisconnect: () -> Void

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 11) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 17, weight: .semibold))
                VStack(alignment: .leading, spacing: 3) {
                    Text("friend_profile.listening_together")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                    Label(syncState.titleKey, systemImage: syncState.systemImage)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(syncState.tint)
                }
                Spacer()
            }

            Button("friend_profile.disconnect", action: onDisconnect)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 42)
                .background(.white.opacity(0.055), in: Capsule())
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
    }
}

private struct FriendQueueContent: View {
    let state: FriendProfileState
    let onTrackTapped: (String) -> Void
    let onSuggest: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !state.isOnline {
                FriendProfileEmptyMessage(key: "friend_profile.queue_unavailable", systemImage: "wifi.slash")
            } else if let currentTrack = state.currentTrack {
                VStack(alignment: .leading, spacing: 9) {
                    Text("friend_profile.queue_now")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.50))
                    FriendQueueCurrentRow(track: currentTrack)
                }

                if !state.queue.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("friend_profile.queue_next")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.50))

                        ForEach(Array(state.queue.enumerated()), id: \.element.id) { index, track in
                            FriendQueueRow(index: index + 1, track: track) {
                                onTrackTapped(track.id)
                            }
                        }
                    }
                }

                Button(action: onSuggest) {
                    Label("friend_profile.suggest_track", systemImage: "plus")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                        .background(.thinMaterial, in: Capsule())
                        .overlay { Capsule().stroke(.white.opacity(0.11), lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    Text("friend_profile.suggest_accessibility") + Text(verbatim: " \(state.displayName)")
                )
            } else {
                FriendProfileEmptyMessage(key: "friend_profile.queue_empty", systemImage: "text.line.last.and.arrowtriangle.forward")
            }
        }
    }
}

private struct FriendQueueCurrentRow: View {
    let track: FriendCurrentTrack

    var body: some View {
        HStack(spacing: 12) {
            Image(track.artworkName)
                .resizable()
                .scaledToFill()
                .frame(width: 58, height: 58)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: track.title).font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(verbatim: track.artistName)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            Text(verbatim: track.durationText)
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.48))
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}

private struct FriendQueueRow: View {
    let index: Int
    let track: FriendQueueItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Text(verbatim: "\(index)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.38))
                    .frame(width: 18)
                Image(track.artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: track.title)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(verbatim: track.artistName)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.46))
                        .lineLimit(1)
                }
                Spacer()
                Text(verbatim: track.durationText)
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.44))
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(track.title), \(track.artistName), \(track.durationText)"))
    }
}

private struct FriendSavedContentSection: View {
    let displayName: String
    let items: [FriendSavedItem]
    let actions: FriendProfileActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Text("friend_profile.saved")
                Text(verbatim: displayName)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .font(.system(size: 19, weight: .bold, design: .rounded))

            ForEach(items) { item in
                NavigationLink(value: FriendSavedDestination(friendName: displayName, kind: item.kind)) {
                    FriendSavedRow(item: item)
                }
                .simultaneousGesture(TapGesture().onEnded { _ in actions.savedAction(for: item.kind)() })
                .buttonStyle(.plain)
            }
        }
    }
}

private struct FriendSavedRow: View {
    let item: FriendSavedItem

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: item.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.white.opacity(0.06), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(item.kind.titleKey)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Text(LocalizedStringKey(item.kind.countKey))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.44))
            }

            Spacer(minLength: 4)

            HStack(spacing: -7) {
                ForEach(Array(item.artworkNames.prefix(3).enumerated()), id: \.offset) { _, name in
                    artworkView(name: name)
                }
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.38))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(minHeight: 68)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.09), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func artworkView(name: String) -> some View {
        if item.kind.usesCircularArtwork {
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(Circle())
                .overlay { Circle().stroke(Color.black.opacity(0.50), lineWidth: 1) }
        } else {
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

private struct FriendProfileEmptyMessage: View {
    let key: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(.white.opacity(0.42))
            Text(key)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 34)
    }
}

private struct FriendProfileNotice: View {
    let key: String
    let displayName: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(LocalizedStringKey(key))
            if key == "friend_profile.suggested" {
                Text(verbatim: displayName)
            }
            Spacer()
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .padding(.horizontal, 13)
        .frame(minHeight: 42)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct FriendProfileStickyHeader: View {
    let displayName: String
    let isOnline: Bool
    let isConnected: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 34, height: 34)
            }
            Text(verbatim: displayName)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer()
            if isConnected {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.60))
            }
            if isOnline {
                Circle().fill(.green).frame(width: 8, height: 8)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Divider().overlay(.white.opacity(0.08)) }
    }
}

private struct FriendProfileBackground: View {
    let isListening: Bool

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.027, blue: 0.035)
            if isListening {
                RadialGradient(
                    colors: [.purple.opacity(0.22), .indigo.opacity(0.08), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 430
                )
            }
            LinearGradient(colors: [.clear, .black.opacity(0.20)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

private struct FriendSavedPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss
    let destination: FriendSavedDestination

    var body: some View {
        ZStack {
            FriendProfileBackground(isListening: false)
            VStack(spacing: 10) {
                Text(destination.kind.titleKey)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("friend_profile.saved_page_later")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Button(action: { dismiss() }) {
                    Label(destination.friendName, systemImage: "chevron.left")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 48)
            .background(.ultraThinMaterial)
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FriendTrackSuggestionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedTrack: FriendSuggestionTrack?

    let displayName: String
    let onConfirm: (FriendSuggestionTrack) -> Void

    private var tracks: [FriendSuggestionTrack] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return FriendSuggestionTrack.samples }
        return FriendSuggestionTrack.samples.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
                || $0.artistName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("friend_profile.find_track", text: $query)
                }
                .padding(.horizontal, 13)
                .frame(height: 44)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))

                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(tracks) { track in
                            Button { selectedTrack = track } label: {
                                HStack(spacing: 11) {
                                    Image(track.artworkName)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 48, height: 48)
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: track.title).font(.system(size: 14, weight: .semibold, design: .rounded))
                                        Text(verbatim: track.artistName)
                                            .font(.system(size: 11, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if selectedTrack?.id == track.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.purple)
                                    }
                                }
                                .foregroundStyle(.white)
                                .frame(minHeight: 58)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let selectedTrack {
                    VStack(spacing: 10) {
                        Text("friend_profile.suggest_confirm")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text(verbatim: displayName)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        HStack(spacing: 10) {
                            Button("friend_profile.cancel") { self.selectedTrack = nil }
                                .frame(maxWidth: .infinity)
                            Button("friend_profile.suggest") {
                                onConfirm(selectedTrack)
                                dismiss()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
            }
            .padding(16)
            .background(FriendProfileBackground(isListening: false))
            .navigationTitle("friend_profile.suggest_track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("friend_profile.close") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct FriendProfileHeroBottomKey: PreferenceKey {
    static let defaultValue: CGFloat = 1_000
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

#Preview("Friend profile") {
    NavigationStack {
        FriendProfileScreen(
            destination: FriendProfileDestination(id: "alex", displayName: "Alex"),
            initialState: .onlineListening
        )
    }
}

#Preview("Friend connected") {
    FriendProfileScreen(destination: FriendProfileDestination(id: "alex", displayName: "Alex"), initialState: .connected)
}

#Preview("Friend queue") {
    FriendProfileScreen(destination: FriendProfileDestination(id: "alex", displayName: "Alex"), initialState: .queueTab)
}

#Preview("Friend idle") {
    FriendProfileScreen(destination: FriendProfileDestination(id: "kate", displayName: "Kate"), initialState: .onlineIdle)
}

#Preview("Friend offline") {
    FriendProfileScreen(destination: FriendProfileDestination(id: "dima", displayName: "Dima"), initialState: .offline)
}

#Preview("Friend reconnecting") {
    FriendProfileScreen(destination: FriendProfileDestination(id: "alex", displayName: "Alex"), initialState: .reconnecting)
}
