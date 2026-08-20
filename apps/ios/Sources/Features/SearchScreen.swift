import SwiftUI

enum SearchCategory: String, CaseIterable, Hashable, Sendable {
    case all, tracks, artists, releases, playlists
    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "search.category_all"
        case .tracks: "search.category_tracks"
        case .artists: "search.category_artists"
        case .releases: "search.category_releases"
        case .playlists: "search.category_playlists"
        }
    }
}

struct SearchScreen: View {
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    @EnvironmentObject private var playlistStore: PlaylistStore
    @State private var query = ""
    @State private var category: SearchCategory = .all

    private var tracks: [PlayableTrack] { localLibrary.searchTracks(query: query) }
    private var artists: [LocalArtist] {
        localLibrary.artists.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.tracks.contains(where: matches) }
    }
    private var releases: [LocalRelease] {
        let matchedIDs = Set(tracks.compactMap(\.releaseID))
        return localLibrary.releases.filter {
            query.isEmpty || matchedIDs.contains($0.id) || $0.title.localizedCaseInsensitiveContains(query) || $0.artist.localizedCaseInsensitiveContains(query)
        }
    }
    private var playlists: [Playlist] {
        playlistStore.playlists.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    private var hasResults: Bool { !tracks.isEmpty || !artists.isEmpty || !releases.isEmpty || !playlists.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                SearchBackground()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        Text("search.title").font(.largeTitle.bold())
                        SearchField(query: $query)
                        SearchCategoryBar(selection: $category)
                        if localLibrary.isLoading {
                            ProgressView("library.loading")
                                .frame(maxWidth: .infinity).padding(.vertical, 50)
                        } else if let error = localLibrary.errorMessage {
                            CatalogErrorState(message: error)
                        } else if localLibrary.tracks.isEmpty && playlistStore.playlists.isEmpty {
                            CatalogEmptyState(title: "search.local_empty_title", detail: "search.local_empty_detail", icon: "music.note.house")
                        } else if !hasResults {
                            CatalogEmptyState(title: "search.nothing_found", detail: "search.try_another_query", icon: "magnifyingglass")
                        } else { results }
                    }
                    .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 120)
                }
            }
            .navigationDestination(for: CollectionDetailDestination.self) { CollectionDetailScreen(destination: $0) }
            .navigationDestination(for: ArtistDetailDestination.self) { ArtistDetailScreen(destination: $0) }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task(id: query) { await localLibrary.search(query: query) }
    }

    @ViewBuilder private var results: some View {
        switch category {
        case .all:
            SearchArtistResults(artists: Array(artists.prefix(3)))
            SearchTrackResults(tracks: Array(tracks.prefix(8)), onPlay: play)
            SearchReleaseResults(releases: Array(releases.prefix(6)))
            PlaylistResultsList(playlists: Array(playlists.prefix(4)))
        case .tracks: SearchTrackResults(tracks: tracks, onPlay: play)
        case .artists: SearchArtistResults(artists: artists)
        case .releases: SearchReleaseResults(releases: releases)
        case .playlists:
            if playlists.isEmpty {
                CatalogEmptyState(title: "search.playlists_empty_title", detail: "search.playlists_empty_detail", icon: "music.note.list")
            } else { PlaylistResultsList(playlists: playlists) }
        }
    }

    private func matches(_ track: PlayableTrack) -> Bool {
        track.title.localizedCaseInsensitiveContains(query) || track.artist.localizedCaseInsensitiveContains(query) || (track.albumTitle?.localizedCaseInsensitiveContains(query) ?? false)
    }

    private func play(_ track: PlayableTrack) {
        playback.play(tracks, startingAt: tracks.firstIndex(of: track) ?? 0, context: .search(query))
    }
}

private struct CatalogErrorState: View {
    let message: String
    var body: some View {
        ContentUnavailableView("library.error_title", systemImage: "exclamationmark.triangle", description: Text(verbatim: message))
            .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}

private struct SearchBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.028, blue: 0.038)
            RadialGradient(colors: [.purple.opacity(0.20), .clear], center: .topLeading, startRadius: 10, endRadius: 500)
        }.ignoresSafeArea()
    }
}

#Preview("Local search") {
    SearchScreen().environmentObject(PlaybackCoordinator()).environmentObject(LocalMediaLibrary()).environmentObject(PlaylistStore())
}
