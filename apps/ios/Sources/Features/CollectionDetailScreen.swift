import SwiftUI
import UniformTypeIdentifiers

enum CollectionDetailDestination: Hashable, Sendable {
    case playlist(titleKey: String, metadataKey: String, artwork: CollectionHeroArtwork)
    case release(title: String, metadataKey: String, artwork: CollectionHeroArtwork)
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

    @State private var isEditing = false
    @State private var isCollectionLiked = false
    @State private var heroBottom: CGFloat = 1_000
    @State private var showsFileImporter = false
    @State private var showsMusicFolder = false

    let destination: CollectionDetailDestination

    private var model: CollectionDetailPreviewModel {
        CollectionDetailPreviewModel(destination: destination)
    }

    private var showsStickyHeader: Bool {
        heroBottom < 84
    }

    private var displayedTracks: [CollectionTrackPreviewModel] {
        guard model.kind == .offline else { return model.tracks }
        return localLibrary.tracks.map(CollectionTrackPreviewModel.init(playableTrack:))
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
                        onBack: { dismiss() }
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
            allowedContentTypes: [.audio],
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
    }

    @ViewBuilder
    private var collectionHero: some View {
        switch model.kind {
        case .playlist, .release, .liked:
            PlaylistCollectionHero(
                titleKey: model.titleKey,
                metadataKey: model.metadataKey,
                artwork: model.heroArtwork ?? .violet,
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
                    accessibilityKey: "collection.add_tracks"
                )

                CollectionOverflowMenu(kind: model.kind, isEditing: $isEditing) {
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
                    OfflineSortMenu()
                }
            }
            .foregroundStyle(.white)
            .padding(.bottom, 10)

            ForEach(Array(displayedTracks.enumerated()), id: \.element.id) { index, track in
                CollectionTrackRow(
                    track: track,
                    kind: model.kind,
                    isEditing: isEditing,
                    isCurrent: playback.currentTrack.id == track.id,
                    onTap: {
                        playback.play(displayedTracks.map(\.playableTrack), startingAt: index)
                    }
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
        playback.play(tracks)
    }
}

private struct CollectionNavigationHeader: View {
    let model: CollectionDetailPreviewModel
    @Binding var isEditing: Bool
    let onBack: () -> Void

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
                CollectionOverflowMenu(kind: model.kind, isEditing: $isEditing) {
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
    let compactArtwork: Bool

    private var artworkSize: CGFloat {
        compactArtwork ? 144 : 184
    }

    var body: some View {
        VStack(spacing: 16) {
            CollectionHeroArtworkView(artwork: artwork)
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
    let track: CollectionTrackPreviewModel
    let kind: CollectionDetailKind
    let isEditing: Bool
    let isCurrent: Bool
    let onTap: () -> Void

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
                Button(action: {}) {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.red.opacity(0.82))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("collection.remove_track"))
            } else {
                TrackOverflowMenu(track: track, kind: kind)
            }
        }
        .frame(minHeight: 64)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(track.title), \(track.artist), \(track.durationText)"))
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

private struct TrackOverflowMenu: View {
    @EnvironmentObject private var playback: PlaybackCoordinator

    let track: CollectionTrackPreviewModel
    let kind: CollectionDetailKind

    var body: some View {
        Menu {
            Button("collection.play_next") { playback.playNext(track.playableTrack) }
            Button("collection.add_to_queue") { playback.addToQueue(track.playableTrack) }
            Button("collection.add_to_playlist", action: {})

            if kind != .offline {
                Button("collection.download", action: {})
            }

            Divider()
            Button("collection.go_to_artist", action: {})
            Button("collection.go_to_release", action: {})
            if kind != .release {
                Divider()
                Button(
                    LocalizedStringKey(
                        kind == .offline
                            ? "collection.remove_local_copy"
                            : "collection.remove_from_playlist"
                    ),
                    role: .destructive,
                    action: {}
                )
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .frame(width: 32, height: 44)
        }
        .accessibilityLabel(Text("collection.more_actions"))
        .accessibilityValue(Text(verbatim: track.title))
    }
}

private struct CollectionOverflowMenu<Label: View>: View {
    let kind: CollectionDetailKind
    @Binding var isEditing: Bool
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
                Button("collection.change_cover", action: {})
                Button("collection.rename", action: {})
                Button("collection.delete_playlist", role: .destructive, action: {})
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
    var body: some View {
        Menu {
            Button("collection.sort_recent", action: {})
            Button("collection.sort_title", action: {})
            Button("collection.sort_artist", action: {})
            Button("collection.sort_size", action: {})
            Button("collection.sort_duration", action: {})
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

private struct CollectionDetailPreviewModel: Sendable {
    let kind: CollectionDetailKind
    let titleKey: String
    let metadataKey: String
    let heroArtwork: CollectionHeroArtwork?
    let tracks: [CollectionTrackPreviewModel]

    init(destination: CollectionDetailDestination) {
        switch destination {
        case let .playlist(titleKey, metadataKey, artwork):
            self.kind = .playlist
            self.titleKey = titleKey
            self.metadataKey = metadataKey
            self.heroArtwork = artwork
            self.tracks = CollectionTrackPreviewModel.playlistSamples
        case let .release(title, metadataKey, artwork):
            self.kind = .release
            self.titleKey = title
            self.metadataKey = metadataKey
            self.heroArtwork = artwork
            self.tracks = CollectionTrackPreviewModel.releaseSamples
        case .liked:
            self.kind = .liked
            self.titleKey = "library.liked"
            self.metadataKey = "collection.liked_metadata"
            self.heroArtwork = .liked
            self.tracks = CollectionTrackPreviewModel.likedSamples
        case .offline:
            self.kind = .offline
            self.titleKey = "library.offline"
            self.metadataKey = "collection.offline_metadata"
            self.heroArtwork = nil
            self.tracks = CollectionTrackPreviewModel.offlineSamples
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

private struct CollectionTrackPreviewModel: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let durationText: String
    let artwork: CollectionTrackArtwork
    var artworkURL: URL?
    var fileURL: URL?

    init(
        id: String,
        title: String,
        artist: String,
        durationText: String,
        artwork: CollectionTrackArtwork,
        artworkURL: URL? = nil,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.durationText = durationText
        self.artwork = artwork
        self.artworkURL = artworkURL
        self.fileURL = fileURL
    }

    init(playableTrack: PlayableTrack) {
        id = playableTrack.id
        title = playableTrack.title
        artist = playableTrack.artist
        durationText = Self.formattedDuration(playableTrack.durationSeconds)
        artwork = .mistyLake
        artworkURL = playableTrack.artworkURL
        fileURL = playableTrack.fileURL
    }

    var playableTrack: MockPlayableTrack {
        MockPlayableTrack(
            id: id,
            title: title,
            artist: artist,
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

    static let playlistSamples = [
        CollectionTrackPreviewModel(id: "after-dark", title: "After Dark", artist: "Mr.Kitty", durationText: "3:51", artwork: .violet),
        CollectionTrackPreviewModel(id: "midnight-city", title: "Midnight City", artist: "M83", durationText: "4:03", artwork: .auroraShore),
        CollectionTrackPreviewModel(id: "nightcall", title: "Nightcall", artist: "Kavinsky", durationText: "4:18", artwork: .amber),
        CollectionTrackPreviewModel(id: "less-i-know", title: "The Less I Know The Better", artist: "Tame Impala", durationText: "3:38", artwork: .mistyLake),
        CollectionTrackPreviewModel(id: "space-song", title: "Space Song", artist: "Beach House", durationText: "5:20", artwork: .graphite),
        CollectionTrackPreviewModel(id: "resonance", title: "Resonance", artist: "HOME", durationText: "3:32", artwork: .violet)
    ]

    static let likedSamples = [
        CollectionTrackPreviewModel(id: "instant-crush", title: "Instant Crush", artist: "Daft Punk", durationText: "5:37", artwork: .amber),
        CollectionTrackPreviewModel(id: "after-dark-liked", title: "After Dark", artist: "Mr.Kitty", durationText: "3:51", artwork: .violet),
        CollectionTrackPreviewModel(id: "space-song-liked", title: "Space Song", artist: "Beach House", durationText: "5:20", artwork: .mistyLake),
        CollectionTrackPreviewModel(id: "nightcall-liked", title: "Nightcall", artist: "Kavinsky", durationText: "4:18", artwork: .auroraShore),
        CollectionTrackPreviewModel(id: "resonance-liked", title: "Resonance", artist: "HOME", durationText: "3:32", artwork: .graphite)
    ]

    static let offlineSamples = [
        CollectionTrackPreviewModel(id: "nightcall-offline", title: "Nightcall", artist: "Kavinsky", durationText: "4:18", artwork: .amber),
        CollectionTrackPreviewModel(id: "midnight-city-offline", title: "Midnight City", artist: "M83", durationText: "4:03", artwork: .auroraShore),
        CollectionTrackPreviewModel(id: "after-dark-offline", title: "After Dark", artist: "Mr.Kitty", durationText: "3:51", artwork: .violet),
        CollectionTrackPreviewModel(id: "resonance-offline", title: "Resonance", artist: "HOME", durationText: "3:32", artwork: .graphite),
        CollectionTrackPreviewModel(id: "505-offline", title: "505", artist: "Arctic Monkeys", durationText: "4:13", artwork: .mistyLake),
        CollectionTrackPreviewModel(id: "instant-crush-offline", title: "Instant Crush", artist: "Daft Punk", durationText: "5:37", artwork: .amber)
    ]

    static let releaseSamples = [
        CollectionTrackPreviewModel(id: "give-life-back", title: "Give Life Back to Music", artist: "Daft Punk", durationText: "4:35", artwork: .graphite),
        CollectionTrackPreviewModel(id: "game-of-love", title: "The Game of Love", artist: "Daft Punk", durationText: "5:22", artwork: .amber),
        CollectionTrackPreviewModel(id: "giorgio", title: "Giorgio by Moroder", artist: "Daft Punk", durationText: "9:04", artwork: .violet),
        CollectionTrackPreviewModel(id: "instant-crush-release", title: "Instant Crush", artist: "Daft Punk", durationText: "5:37", artwork: .auroraShore)
    ]
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
        CollectionDetailScreen(
            destination: .playlist(
                titleKey: "library.playlist_night",
                metadataKey: "collection.night_metadata",
                artwork: .violet
            )
        )
    }
    .environmentObject(MockPlaybackState())
    .environmentObject(LocalMediaLibrary())
}

#Preview("Offline detail") {
    NavigationStack {
        CollectionDetailScreen(destination: .offline)
    }
    .environmentObject(MockPlaybackState())
    .environmentObject(LocalMediaLibrary())
}
