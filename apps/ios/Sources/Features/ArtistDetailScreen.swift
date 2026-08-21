import SwiftUI

struct ArtistDetailDestination: Hashable, Sendable {
    let name: String
    let provider: String?
    let externalID: String?

    init(name: String, provider: String? = nil, externalID: String? = nil) {
        self.name = name
        self.provider = provider
        self.externalID = externalID
    }
}

enum ArtistSectionKind: String, Hashable, Sendable {
    case allTracks, releases, compilations, familiar
    var titleKey: LocalizedStringKey {
        switch self {
        case .allTracks: "artist.all_tracks"
        case .releases: "artist.releases"
        case .compilations: "artist.compilations"
        case .familiar: "artist.familiar"
        }
    }
}

struct ArtistSectionDestination: Hashable, Sendable {
    let artistName: String
    let kind: ArtistSectionKind
}

struct ArtistDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    @EnvironmentObject private var musicSearch: MusicSearchStore
    let destination: ArtistDetailDestination
    @State private var externalLibrary: ExternalArtistLibrary?
    @State private var isLoadingExternal = false
    @State private var externalError: String?

    private var artist: LocalArtist? { localLibrary.artists.first { $0.name == destination.name } }
    private var releases: [LocalRelease] {
        localLibrary.releases.filter { release in
            release.tracks.contains { track in
                track.artistNames.contains { $0.libraryNormalized == destination.name.libraryNormalized }
            }
        }
    }

    var body: some View {
        ZStack {
            ArtistDetailBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header
                    if let artist {
                        Button { playback.play(artist.tracks, context: .artist(artist.id)) } label: { Label("collection.play", systemImage: "play.fill") }
                            .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                        SearchTrackResults(tracks: artist.tracks, onPlay: play)
                        SearchReleaseResults(releases: releases)
                    }
                    if isLoadingExternal {
                        ProgressView("search.searching_more").frame(maxWidth: .infinity, alignment: .leading)
                    } else if let externalLibrary {
                        MusicSearchTrackResults(results: externalLibrary.tracks, onPlay: playExternal)
                        ExternalEntityResults(title: "artist.releases", results: externalLibrary.releases)
                    } else if artist == nil, let externalError {
                        ContentUnavailableView(
                            "library.error_title",
                            systemImage: "exclamationmark.triangle",
                            description: Text(verbatim: externalError)
                        )
                    } else if artist == nil {
                        CatalogEmptyState(title: "artist.local_empty_title", detail: "artist.local_empty_detail", icon: "person.crop.circle.badge.questionmark")
                    }
                }
                .frame(maxWidth: 620, alignment: .leading).padding(16).padding(.bottom, 40).frame(maxWidth: .infinity)
            }
        }
        .navigationDestination(for: CollectionDetailDestination.self) { CollectionDetailScreen(destination: $0) }
        .toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
        .task(id: destination) { await loadExternalLibrary() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { dismiss() } label: { Label("collection.back", systemImage: "chevron.left") }.buttonStyle(.plain)
            HStack(spacing: 18) {
                TrackArtworkView(artworkURL: externalLibrary?.artist.artworkURL ?? artist?.artworkURL, fallbackName: "ArtistHero")
                    .scaledToFill().frame(width: 110, height: 110).clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: destination.name).font(.largeTitle.bold()).lineLimit(2)
                    let count = max(artist?.tracks.count ?? 0, externalLibrary?.tracks.count ?? 0)
                    if count > 0 { Text("\(count) \(String(localized: "collection.tracks_unit"))").foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func play(_ track: PlayableTrack) {
        guard let artist else { return }
        playback.play(artist.tracks, startingAt: artist.tracks.firstIndex(of: track) ?? 0, context: .artist(artist.id))
    }

    private func playExternal(_ result: MusicSearchResult) {
        guard let track = result.playableTrack else { return }
        let playable = externalLibrary?.tracks.compactMap(\.playableTrack) ?? []
        playback.play(playable, startingAt: playable.firstIndex(of: track) ?? 0, context: .artist(destination.externalID ?? destination.name))
    }

    private func loadExternalLibrary() async {
        isLoadingExternal = true
        defer { isLoadingExternal = false }
        do {
            externalLibrary = try await musicSearch.artistLibrary(
                provider: destination.provider ?? "catalog",
                externalID: destination.externalID ?? destination.name.libraryNormalized,
                name: destination.name
            )
            externalError = nil
        } catch { externalError = error.localizedDescription }
    }
}

struct ArtistDetailBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.028, blue: 0.038)
            RadialGradient(colors: [.purple.opacity(0.18), .clear], center: .topTrailing, startRadius: 20, endRadius: 500)
        }.ignoresSafeArea()
    }
}

#Preview("Local artist") {
    NavigationStack { ArtistDetailScreen(destination: .init(name: "Artist")) }
        .environmentObject(PlaybackCoordinator()).environmentObject(LocalMediaLibrary()).environmentObject(PlaylistStore())
        .environmentObject(MusicSearchStore(authorization: AuthorizationStore()))
}
