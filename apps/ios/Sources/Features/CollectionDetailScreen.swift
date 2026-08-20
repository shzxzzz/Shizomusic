import SwiftUI
import UniformTypeIdentifiers

enum CollectionDetailDestination: Hashable, Sendable {
    case playlist(id: UUID)
    case release(id: String, title: String, artist: String)
    case liked
    case offline
}

enum CollectionHeroArtwork: String, Hashable, Sendable {
    case violet
    case mistyLake
    case sunset
    case liked
}

struct CollectionDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore

    @State private var isEditing = false
    @State private var isCollectionLiked = false
    @State private var heroBottom: CGFloat = 1_000
    @State private var showsFileImporter = false
    @State private var showsMusicFolder = false
    @State private var pendingDeletion: CollectionTrackModel?
    @State private var showsTrackPicker = false
    @State private var showsRename = false
    @State private var showsCoverPicker = false
    @State private var showsDeletePlaylist = false
    @State private var renameTitle = ""

    let destination: CollectionDetailDestination

    private var model: CollectionDetailModel {
        CollectionDetailModel(destination: destination, playlist: playlist)
    }

    private var playlist: Playlist? {
        guard case let .playlist(id) = destination else { return nil }
        return playlistStore.playlists.first { $0.id == id }
    }

    private var showsStickyHeader: Bool {
        heroBottom < 84
    }

    private var displayedTracks: [CollectionTrackModel] {
        if let playlist {
            return playlist.items.map {
                CollectionTrackModel(playableTrack: $0.track, playlistItemID: $0.id)
            }
        }

        let tracks: [PlayableTrack]
        switch destination {
        case .offline:
            tracks = localLibrary.tracks
        case let .release(id, _, _):
            tracks = localLibrary.tracks.filter { $0.releaseID == id }
        case .playlist:
            tracks = []
        case .liked:
            tracks = []
        }
        return tracks.map { track in
            CollectionTrackModel(playableTrack: track)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            CollectionDetailBackground(
                kind: model.kind,
                artwork: model.heroArtwork
            )

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    CollectionNavigationHeader(
                        model: model,
                        isEditing: $isEditing,
                        onBack: { dismiss() },
                        onRename: { prepareRename() },
                        onChangeCover: { showsCoverPicker = true },
                        onDelete: { showsDeletePlaylist = true }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    collectionHero
                        .padding(.top, 18)
                        .background {
                            GeometryReader { proxy in
                                Color.clear.preference(
                                    key: CollectionHeroBottomPreferenceKey.self,
                                    value: proxy.frame(in: .named("collection-scroll")).maxY
                                )
                            }
                        }

                    primaryControls
                        .padding(.top, 24)

                    secondaryControls
                        .padding(.top, 12)

                    if model.kind == .offline, let progress = localLibrary.progress {
                        MediaLibraryProgressView(progress: progress)
                            .padding(.top, 14)
                    }

                    trackList
                        .padding(.top, 30)
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
                .frame(maxWidth: .infinity)
            }
            .coordinateSpace(name: "collection-scroll")
            .onPreferenceChange(CollectionHeroBottomPreferenceKey.self) { value in
                heroBottom = value
            }

            if showsStickyHeader {
                StickyCollectionHeader(
                    titleKey: model.titleKey,
                    isOffline: model.kind == .offline,
                    onBack: { dismiss() }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showsStickyHeader)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .fileImporter(
            isPresented: $showsFileImporter,
            allowedContentTypes: [.audio, .data],
            allowsMultipleSelection: true
        ) { result in
            guard case let .success(urls) = result else { return }
            Task { await localLibrary.importFiles(urls) }
        }
        .sheet(isPresented: $showsMusicFolder) {
            MusicFolderBrowser(directoryURL: localLibrary.musicDirectory) { urls in
                showsMusicFolder = false
                Task { await localLibrary.importFiles(urls) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsTrackPicker) {
            if let playlist {
                PlaylistTrackPicker(playlist: playlist, tracks: localLibrary.tracks)
            }
        }
        .sheet(isPresented: $showsCoverPicker) {
            if let playlist { PlaylistCoverPicker(playlist: playlist) }
        }
        .alert("collection.rename", isPresented: $showsRename) {
            TextField("playlist_create.name_placeholder", text: $renameTitle)
            Button("playlist_create.cancel", role: .cancel) {}
            Button("collection.rename") {
                guard let playlist else { return }
                let title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { return }
                Task { await playlistStore.rename(id: playlist.id, title: title) }
            }
        }
        .confirmationDialog("collection.delete_playlist", isPresented: $showsDeletePlaylist) {
            Button("collection.delete_playlist", role: .destructive) {
                guard let playlist else { return }
                Task {
                    await playlistStore.delete(id: playlist.id)
                    dismiss()
                }
            }
            Button("playlist_create.cancel", role: .cancel) {}
        }
        .confirmationDialog(
            "library.delete_file_title",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            presenting: pendingDeletion
        ) { track in
            Button("library.delete_file_confirm", role: .destructive) {
                Task { await localLibrary.removeTrack(track.playableTrack) }
                pendingDeletion = nil
            }
            Button("friend_profile.cancel", role: .cancel) { pendingDeletion = nil }
        } message: { track in
            Text("\(track.title) — \(track.artist)")
        }
    }

    @ViewBuilder
    private var collectionHero: some View {
        switch model.kind {
        case .playlist, .release, .liked:
            PlaylistCollectionHero(
                titleKey: model.titleKey,
                metadataKey: model.metadataKey,
                artwork: model.heroArtwork ?? .violet,
                artworkURL: model.kind == .release ? displayedTracks.compactMap(\.artworkURL).first : nil,
                playlistCoverStyle: playlist?.coverStyle,
                compactArtwork: dynamicTypeSize.isAccessibilitySize
            )
        case .offline:
            OfflineCollectionHero(
                titleKey: model.titleKey,
                metadataText: offlineMetadata
            )
        }
    }

    @ViewBuilder
    private var primaryControls: some View {
        HStack(spacing: 12) {
            PrimaryPlayButton(
                isOffline: model.kind == .offline,
                accent: model.accentColor,
                action: playCollection
            )

            if model.kind == .playlist || model.kind == .release {
                CircularDownloadButton(accent: model.accentColor)

                CollectionLikeButton(isLiked: $isCollectionLiked)
            }
        }
    }

    @ViewBuilder
    private var secondaryControls: some View {
        switch model.kind {
        case .offline:
            HStack(spacing: 10) {
                CollectionSecondaryActionButton(
                    titleKey: "collection.add_track",
                    systemImage: "plus",
                    accessibilityKey: "collection.add_track",
                    action: { showsFileImporter = true }
                )

                CollectionSecondaryActionButton(
                    titleKey: "collection.open_folder",
                    systemImage: "folder",
                    accessibilityKey: "collection.open_folder_accessibility",
                    action: { showsMusicFolder = true }
                )
            }
        case .playlist:
            HStack(spacing: 12) {
                CollectionSecondaryActionButton(
                    titleKey: "collection.add_tracks",
                    systemImage: "plus",
                    accessibilityKey: "collection.add_tracks",
                    action: { showsTrackPicker = true }
                )

                CollectionOverflowMenu(
                    kind: model.kind,
                    isEditing: $isEditing,
                    onRename: {
                        prepareRename()
                    },
                    onChangeCover: { showsCoverPicker = true },
                    onDelete: { showsDeletePlaylist = true }
                ) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .frame(width: 52, height: 50)
                        .background(.thinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.13), lineWidth: 1)
                        }
                }
                .accessibilityLabel(Text("collection.more_actions"))
            }
        case .liked, .release:
            EmptyView()
        }
    }

    private var trackList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("collection.tracks")
                    .font(.system(size: 20, weight: .bold, design: .rounded))

                Spacer()

                if model.kind == .offline {
                    OfflineSortMenu(
                        selectedSort: localLibrary.sort,
                        selectedFilter: localLibrary.availabilityFilter,
                        onChange: { sort, filter in
                            Task { await localLibrary.apply(sort: sort, filter: filter) }
                        }
                    )
                }
            }
            .foregroundStyle(.white)
            .padding(.bottom, 10)

            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                CollectionTrackRow(
                    track: track,
                    kind: model.kind,
                    isEditing: isEditing,
                    isCurrent: playback.currentTrack.id == track.trackID,
                    onTap: {
                        playback.play(displayedTracks.map(\.playableTrack), startingAt: index, context: queueContext)
                    },
                    onRemove: {
                        if let itemID = track.playlistItemID {
                            Task { await playlistStore.remove(itemID: itemID) }
                        } else if model.kind == .offline { pendingDeletion = track }
                    },
                    onMoveUp: { movePlaylistItem(track, offset: -1) },
                    onMoveDown: { movePlaylistItem(track, offset: 1) }
                )

                if track.id != displayedTracks.last?.id {
                    Divider()
                        .overlay(.white.opacity(0.075))
                        .padding(.leading, isEditing ? 92 : 62)
                }
            }
        }
    }

    private var offlineMetadata: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(localLibrary.tracks.count) · \(formatter.string(fromByteCount: localLibrary.totalBytes))"
    }

    private func playCollection() {
        let tracks = displayedTracks.map(\.playableTrack)
        guard !tracks.isEmpty else { return }
        playback.play(tracks, context: queueContext)
    }

    private var queueContext: QueueSourceContext {
        switch destination {
        case .offline: .offline
        case let .release(id, _, _): .release(id)
        case let .playlist(id): .playlist(id)
        default: .adHoc
        }
    }

    private func movePlaylistItem(_ track: CollectionTrackModel, offset: Int) {
        guard let playlist, let itemID = track.playlistItemID,
              let index = playlist.items.firstIndex(where: { $0.id == itemID }) else { return }
        let destination = min(max(index + offset, 0), playlist.items.count - 1)
        guard destination != index else { return }
        Task { await playlistStore.move(itemID: itemID, to: destination) }
    }

    private func prepareRename() {
        renameTitle = playlist?.title ?? ""
        showsRename = true
    }
}

struct MediaLibraryProgressView: View {
    let progress: MediaLibraryProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(progress.phase == .importing ? "import.progress_importing" : "import.progress_scanning")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer()
                Text(verbatim: "\(progress.completed)/\(progress.total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress.fraction)
                .tint(.cyan)
            if let filename = progress.filename {
                Text(verbatim: filename)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct ImportReportView: View {
    @Environment(\.dismiss) private var dismiss
    let report: ImportReport

    var body: some View {
        NavigationStack {
            List {
                resultSection("import.result_imported", files: report.imported, color: .green)
                resultSection("import.result_duplicates", files: report.duplicates, color: .orange)
                resultSection("import.result_corrupted", files: report.corrupted, color: .red)
                resultSection("import.result_unsupported", files: report.unsupported, color: .yellow)
                resultSection("import.result_failed", files: report.failed, color: .red)
            }
            .navigationTitle("import.result_title")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("queue.done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private func resultSection(_ titleKey: LocalizedStringKey, files: [String], color: Color) -> some View {
        if !files.isEmpty {
            Section {
                ForEach(files, id: \.self) { Text(verbatim: $0) }
            } header: {
                HStack {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(titleKey)
                    Text(verbatim: "\(files.count)")
                }
            }
        }
    }
}

private struct CollectionNavigationHeader: View {
    let model: CollectionDetailModel
    @Binding var isEditing: Bool
    let onBack: () -> Void
    let onRename: () -> Void
    let onChangeCover: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.13), lineWidth: 1)
                    }
            }
            .accessibilityLabel(Text("collection.back"))

            Text("library.title")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))

            Spacer()

            if isEditing {
                Button("collection.done") {
                    isEditing = false
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            } else if model.kind != .release {
                CollectionOverflowMenu(
                    kind: model.kind,
                    isEditing: $isEditing,
                    onRename: onRename,
                    onChangeCover: onChangeCover,
                    onDelete: onDelete
                ) {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay {
                            Circle().stroke(.white.opacity(0.13), lineWidth: 1)
                        }
                }
                .accessibilityLabel(Text("collection.more_actions"))
            }
        }
        .foregroundStyle(.white)
        .frame(height: 44)
    }
}

private struct PlaylistCollectionHero: View {
    let titleKey: String
    let metadataKey: String
    let artwork: CollectionHeroArtwork
    let artworkURL: URL?
    let playlistCoverStyle: PlaylistCoverStyle?
    let compactArtwork: Bool

    private var artworkSize: CGFloat {
        compactArtwork ? 144 : 184
    }

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let artworkURL {
                    TrackArtworkView(artworkURL: artworkURL, fallbackName: "MistyLake").scaledToFill()
                } else if let playlistCoverStyle {
                    LibraryArtwork(style: playlistCoverStyle)
                } else {
                    CollectionHeroArtworkView(artwork: artwork)
                }
            }
                .frame(width: artworkSize, height: artworkSize)
                .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .stroke(.white.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: artwork.shadowColor.opacity(0.36), radius: 30, y: 14)

            VStack(spacing: 6) {
                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(LocalizedStringKey(metadataKey))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

private struct OfflineCollectionHero: View {
    let titleKey: String
    let metadataText: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.045))
                    .frame(width: 142, height: 142)
                    .blur(radius: 12)

                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 124, height: 124)
                    .overlay {
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.30), .white.opacity(0.07)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1
                            )
                    }

                Image(systemName: "arrow.down")
                    .font(.system(size: 43, weight: .medium))
                    .foregroundStyle(.white.opacity(0.90))
            }
            .shadow(color: .white.opacity(0.09), radius: 34)

            VStack(spacing: 6) {
                Text(LocalizedStringKey(titleKey))
                    .font(.system(size: 26, weight: .bold, design: .rounded))

                Text(verbatim: metadataText)
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.56))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
    }
}

private struct CollectionHeroArtworkView: View {
    let artwork: CollectionHeroArtwork

    var body: some View {
        ZStack {
            artworkBackground

            LinearGradient(
                colors: [.white.opacity(0.10), .clear, .black.opacity(0.24)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: artwork.symbol)
                .font(.system(size: 49, weight: .medium))
                .foregroundStyle(.white.opacity(0.84))
                .shadow(color: .black.opacity(0.28), radius: 8, y: 5)
        }
        .clipped()
    }

    @ViewBuilder
    private var artworkBackground: some View {
        switch artwork {
        case .mistyLake:
            Image("MistyLake")
                .resizable()
                .scaledToFill()
        case .sunset:
            Image("AuroraShore")
                .resizable()
                .scaledToFill()
                .saturation(1.15)
        case .violet:
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.04, blue: 0.23),
                    Color(red: 0.47, green: 0.18, blue: 0.68),
                    Color(red: 0.08, green: 0.16, blue: 0.30)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .liked:
            LinearGradient(
                colors: [
                    Color(red: 0.20, green: 0.05, blue: 0.17),
                    Color(red: 0.72, green: 0.18, blue: 0.45),
                    Color(red: 0.38, green: 0.12, blue: 0.52)
                ],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        }
    }
}

private struct PrimaryPlayButton: View {
    let isOffline: Bool
    let accent: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("collection.play", systemImage: "play.fill")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background {
                    Capsule()
                        .fill(isOffline ? Color.white.opacity(0.095) : accent.opacity(0.72))
                        .background(.thinMaterial, in: Capsule())
                }
                .overlay {
                    Capsule().stroke(.white.opacity(isOffline ? 0.18 : 0.15), lineWidth: 1)
                }
        }
        .buttonStyle(CollectionPressButtonStyle())
        .accessibilityLabel(Text("collection.play"))
    }
}

private struct CircularDownloadButton: View {
    let accent: Color

    var body: some View {
        Button(action: {}) {
            Image(systemName: "arrow.down")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(accent.opacity(0.96))
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(CollectionPressButtonStyle())
        .accessibilityLabel(Text("collection.download_playlist"))
    }
}

private struct CollectionLikeButton: View {
    @Binding var isLiked: Bool

    var body: some View {
        Button {
            isLiked.toggle()
        } label: {
            Image(systemName: isLiked ? "heart.fill" : "heart")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(isLiked ? .pink : .white.opacity(0.86))
                .frame(width: 52, height: 52)
                .background(.thinMaterial, in: Circle())
                .overlay {
                    Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
        .buttonStyle(CollectionPressButtonStyle())
        .accessibilityLabel(
            Text(LocalizedStringKey(isLiked ? "collection.unlike" : "collection.like"))
        )
    }
}

private struct CollectionSecondaryActionButton: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let accessibilityKey: LocalizedStringKey
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Label(titleKey, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.86))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
        .buttonStyle(CollectionPressButtonStyle())
        .accessibilityLabel(Text(accessibilityKey))
    }
}

private struct CollectionTrackRow: View {
    let track: CollectionTrackModel
    let kind: CollectionDetailKind
    let isEditing: Bool
    let isCurrent: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isEditing {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
                    .frame(width: 20)
                    .accessibilityHidden(true)
            }

            Button {
                if !isEditing {
                    onTap()
                }
            } label: {
                HStack(spacing: 10) {
                    Group {
                        if let artworkURL = track.artworkURL {
                            TrackArtworkView(
                                artworkURL: artworkURL,
                                fallbackName: track.artwork.assetName
                            )
                            .scaledToFill()
                        } else {
                            CollectionTrackArtworkView(style: track.artwork)
                        }
                    }
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: track.title)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(isCurrent ? Color.cyan.opacity(0.90) : .white)
                            .lineLimit(1)

                        Text(verbatim: track.artist)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.52))
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    if !isEditing {
                        Text(verbatim: track.durationText)
                            .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.40))
                    }
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            if isEditing {
                VStack(spacing: 2) {
                    Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                        .accessibilityLabel(Text("playlist.move_up"))
                    Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                        .accessibilityLabel(Text("playlist.move_down"))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.62))
                .buttonStyle(.plain)

                Button(action: onRemove) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red.opacity(0.82))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("collection.remove_track"))
            } else {
                TrackActionsMenu(
                    track: track.playableTrack,
                    removeTitle: removeTitle,
                    onRemove: onRemove
                )
            }
        }
        .frame(minHeight: 64)
    }

    private var removeTitle: String? {
        switch kind {
        case .offline: "collection.remove_local_copy"
        case .playlist: "collection.remove_from_playlist"
        case .release, .liked: nil
        }
    }
}

private struct CollectionTrackArtworkView: View {
    let style: CollectionTrackArtwork

    var body: some View {
        ZStack {
            switch style {
            case .mistyLake:
                Image("MistyLake")
                    .resizable()
                    .scaledToFill()
            case .auroraShore:
                Image("AuroraShore")
                    .resizable()
                    .scaledToFill()
            case .violet:
                LinearGradient(
                    colors: [.indigo.opacity(0.9), .purple.opacity(0.55), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            case .amber:
                LinearGradient(
                    colors: [.orange.opacity(0.82), .red.opacity(0.45), .black],
                    startPoint: .topTrailing,
                    endPoint: .bottomLeading
                )
            case .graphite:
                LinearGradient(
                    colors: [.white.opacity(0.38), .gray.opacity(0.32), .black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipped()
    }
}

private struct CollectionOverflowMenu<Label: View>: View {
    let kind: CollectionDetailKind
    @Binding var isEditing: Bool
    var onRename: () -> Void = {}
    var onChangeCover: () -> Void = {}
    var onDelete: () -> Void = {}
    @ViewBuilder let label: () -> Label

    var body: some View {
        Menu {
            switch kind {
            case .offline:
                Button("collection.storage_management", action: {})
                Button("collection.sort", action: {})
                Button("collection.clear", role: .destructive, action: {})
            case .playlist:
                Button("collection.edit") { isEditing = true }
                Button("collection.change_cover", action: onChangeCover)
                Button("collection.rename", action: onRename)
                Button("collection.delete_playlist", role: .destructive, action: onDelete)
            case .liked:
                Button("collection.sort", action: {})
            case .release:
                EmptyView()
            }
        } label: {
            label()
        }
    }
}

private struct OfflineSortMenu: View {
    let selectedSort: LibraryTrackSort
    let selectedFilter: LibraryAvailabilityFilter
    let onChange: (LibraryTrackSort, LibraryAvailabilityFilter) -> Void

    var body: some View {
        Menu {
            Section("library.sort") {
                ForEach(LibraryTrackSort.allCases, id: \.self) { sort in
                    Button { onChange(sort, selectedFilter) } label: {
                        if sort == selectedSort { Label(LocalizedStringKey(sort.localizationKey), systemImage: "checkmark") }
                        else { Text(LocalizedStringKey(sort.localizationKey)) }
                    }
                }
            }
            Section("library.filter") {
                ForEach(LibraryAvailabilityFilter.allCases, id: \.self) { filter in
                    Button { onChange(selectedSort, filter) } label: {
                        if filter == selectedFilter { Label(LocalizedStringKey(filter.localizationKey), systemImage: "checkmark") }
                        else { Text(LocalizedStringKey(filter.localizationKey)) }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
                .frame(width: 36, height: 36)
                .background(.white.opacity(0.055), in: Circle())
        }
        .accessibilityLabel(Text("collection.sort"))
    }
}

private struct StickyCollectionHeader: View {
    let titleKey: String
    let isOffline: Bool
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(Text("collection.back"))

            Text(LocalizedStringKey(titleKey))
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer()

            Button(action: {}) {
                Image(systemName: "play.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(isOffline ? 0.09 : 0.13), in: Circle())
            }
            .accessibilityLabel(Text("collection.play"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().overlay(.white.opacity(0.10))
        }
    }
}

private struct CollectionDetailBackground: View {
    let kind: CollectionDetailKind
    let artwork: CollectionHeroArtwork?

    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.027, blue: 0.034)

            if kind == .offline {
                RadialGradient(
                    colors: [.white.opacity(0.13), .white.opacity(0.025), .clear],
                    center: .top,
                    startRadius: 8,
                    endRadius: 460
                )
            } else {
                RadialGradient(
                    colors: [ambientColor.opacity(0.27), ambientColor.opacity(0.07), .clear],
                    center: .top,
                    startRadius: 20,
                    endRadius: 480
                )
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var ambientColor: Color {
        switch artwork {
        case .sunset:
            .orange
        case .mistyLake:
            Color(red: 0.43, green: 0.63, blue: 0.72)
        case .liked:
            .pink
        case .violet, nil:
            .purple
        }
    }
}

private struct CollectionPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct CollectionHeroBottomPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 1_000

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

enum CollectionDetailKind: String, Hashable, Sendable {
    case playlist
    case release
    case liked
    case offline
}

private struct CollectionDetailModel: Sendable {
    let kind: CollectionDetailKind
    let titleKey: String
    let metadataKey: String
    let heroArtwork: CollectionHeroArtwork?

    init(destination: CollectionDetailDestination, playlist: Playlist?) {
        switch destination {
        case .playlist:
            self.kind = .playlist
            self.titleKey = playlist?.title ?? String(localized: "library.playlists")
            self.metadataKey = "\(playlist?.items.count ?? 0) \(String(localized: "collection.tracks_unit"))"
            self.heroArtwork = playlist?.coverStyle.detailArtwork ?? .violet
        case let .release(_, title, artist):
            self.kind = .release
            self.titleKey = title
            self.metadataKey = artist
            self.heroArtwork = .mistyLake
        case .liked:
            self.kind = .liked
            self.titleKey = "library.liked"
            self.metadataKey = "collection.liked_metadata"
            self.heroArtwork = .liked
        case .offline:
            self.kind = .offline
            self.titleKey = "library.offline"
            self.metadataKey = "collection.offline_metadata"
            self.heroArtwork = nil
        }
    }

    var accentColor: Color {
        switch heroArtwork {
        case .sunset:
            Color(red: 0.88, green: 0.46, blue: 0.30)
        case .mistyLake:
            Color(red: 0.45, green: 0.67, blue: 0.76)
        case .liked:
            Color(red: 0.86, green: 0.34, blue: 0.62)
        case .violet:
            Color(red: 0.60, green: 0.36, blue: 0.84)
        case nil:
            Color.white.opacity(0.82)
        }
    }
}

private struct CollectionTrackModel: Identifiable, Sendable {
    let id: String
    let trackID: String
    let playlistItemID: UUID?
    let title: String
    let artist: String
    let artistNames: [String]
    let albumTitle: String?
    let albumArtist: String?
    let releaseID: String?
    let durationText: String
    let artwork: CollectionTrackArtwork
    var artworkURL: URL?
    var fileURL: URL?

    init(
        id: String,
        trackID: String? = nil,
        playlistItemID: UUID? = nil,
        title: String,
        artist: String,
        artistNames: [String]? = nil,
        albumTitle: String? = nil,
        albumArtist: String? = nil,
        releaseID: String? = nil,
        durationText: String,
        artwork: CollectionTrackArtwork,
        artworkURL: URL? = nil,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.trackID = trackID ?? id
        self.playlistItemID = playlistItemID
        self.title = title
        self.artist = artist
        self.artistNames = artistNames ?? [artist]
        self.albumTitle = albumTitle
        self.albumArtist = albumArtist
        self.releaseID = releaseID
        self.durationText = durationText
        self.artwork = artwork
        self.artworkURL = artworkURL
        self.fileURL = fileURL
    }

    init(playableTrack: PlayableTrack, playlistItemID: UUID? = nil) {
        id = playlistItemID?.uuidString ?? playableTrack.id
        trackID = playableTrack.id
        self.playlistItemID = playlistItemID
        title = playableTrack.title
        artist = playableTrack.artist
        artistNames = playableTrack.artistNames
        albumTitle = playableTrack.albumTitle
        albumArtist = playableTrack.albumArtist
        releaseID = playableTrack.releaseID
        durationText = Self.formattedDuration(playableTrack.durationSeconds)
        artwork = .mistyLake
        artworkURL = playableTrack.artworkURL
        fileURL = playableTrack.fileURL
    }

    var playableTrack: PlayableTrack {
        PlayableTrack(
            id: trackID,
            title: title,
            artist: artist,
            artistNames: artistNames,
            albumTitle: albumTitle,
            albumArtist: albumArtist,
            releaseID: releaseID,
            durationSeconds: durationSeconds,
            artworkName: artwork.assetName,
            artworkURL: artworkURL,
            fileURL: fileURL
        )
    }

    private static func formattedDuration(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    private var durationSeconds: Int {
        let components = durationText.split(separator: ":").compactMap { Int($0) }
        guard components.count == 2 else { return 0 }
        return components[0] * 60 + components[1]
    }

}

private enum CollectionTrackArtwork: String, Hashable, Sendable {
    case mistyLake
    case auroraShore
    case violet
    case amber
    case graphite

    var assetName: String {
        switch self {
        case .mistyLake, .violet, .graphite: "MistyLake"
        case .auroraShore, .amber: "AuroraShore"
        }
    }
}

private extension CollectionHeroArtwork {
    var symbol: String {
        switch self {
        case .violet: "moon.stars.fill"
        case .mistyLake: "cloud.moon.fill"
        case .sunset: "road.lanes"
        case .liked: "heart.fill"
        }
    }

    var shadowColor: Color {
        switch self {
        case .violet: .purple
        case .mistyLake: Color(red: 0.40, green: 0.62, blue: 0.72)
        case .sunset: .orange
        case .liked: .pink
        }
    }
}

#Preview("Playlist detail") {
    NavigationStack {
        CollectionDetailScreen(destination: .playlist(id: UUID()))
    }
    .environmentObject(PlaybackCoordinator())
    .environmentObject(LocalMediaLibrary())
    .environmentObject(PlaylistStore())
}

#Preview("Offline detail") {
    NavigationStack {
        CollectionDetailScreen(destination: .offline)
    }
    .environmentObject(PlaybackCoordinator())
    .environmentObject(LocalMediaLibrary())
    .environmentObject(PlaylistStore())
}
