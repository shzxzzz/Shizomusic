import SwiftUI

enum LibrarySectionDestination: String, Hashable, Sendable {
    case tracks, playlists, releases, artists
    var titleKey: LocalizedStringKey {
        switch self {
        case .tracks: "library.all_tracks"
        case .playlists: "library.playlists"
        case .releases: "library.releases"
        case .artists: "library.artists"
        }
    }
}

struct LibrarySectionListScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    @EnvironmentObject private var playback: PlaybackCoordinator
    let destination: LibrarySectionDestination

    var body: some View {
        ZStack {
            ArtistDetailBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Button { dismiss() } label: { Label("library.title", systemImage: "chevron.left") }.buttonStyle(.plain)
                    Text(destination.titleKey).font(.largeTitle.bold())
                    if destination == .tracks { trackControls }
                    content
                }
                .frame(maxWidth: 620, alignment: .leading).padding(16).padding(.bottom, 40).frame(maxWidth: .infinity)
            }
        }
        .navigationDestination(for: CollectionDetailDestination.self) { CollectionDetailScreen(destination: $0) }
        .navigationDestination(for: ArtistDetailDestination.self) { ArtistDetailScreen(destination: $0) }
        .toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        if localLibrary.isLoading {
            ProgressView("library.loading").frame(maxWidth: .infinity).padding(.vertical, 50)
        } else if let error = localLibrary.errorMessage {
            ContentUnavailableView("library.error_title", systemImage: "exclamationmark.triangle", description: Text(verbatim: error))
                .frame(maxWidth: .infinity).padding(.vertical, 50)
        } else {
            switch destination {
            case .tracks:
                if localLibrary.tracks.isEmpty {
                    CatalogEmptyState(title: "library.tracks_empty_title", detail: "library.catalog_empty_detail", icon: "music.note")
                } else {
                    SearchTrackResults(tracks: localLibrary.tracks) { track in
                        playback.play(localLibrary.tracks, startingAt: localLibrary.tracks.firstIndex(of: track) ?? 0, context: .offline)
                    }
                }
            case .playlists:
                CatalogEmptyState(title: "library.playlists_empty_title", detail: "library.playlists_empty_detail", icon: "music.note.list")
            case .releases:
                if localLibrary.releases.isEmpty {
                    CatalogEmptyState(title: "library.releases_empty_title", detail: "library.catalog_empty_detail", icon: "square.stack")
                } else { SearchReleaseResults(releases: localLibrary.releases) }
            case .artists:
                if localLibrary.artists.isEmpty {
                    CatalogEmptyState(title: "library.artists_empty_title", detail: "library.catalog_empty_detail", icon: "person.2")
                } else { SearchArtistResults(artists: localLibrary.artists) }
            }
        }
    }

    private var trackControls: some View {
        HStack {
            Menu("library.sort") {
                ForEach(LibraryTrackSort.allCases, id: \.self) { sort in
                    Button(LocalizedStringKey(sort.localizationKey)) {
                        Task { await localLibrary.apply(sort: sort, filter: localLibrary.availabilityFilter) }
                    }
                }
            }
            Menu("library.filter") {
                ForEach(LibraryAvailabilityFilter.allCases, id: \.self) { filter in
                    Button(LocalizedStringKey(filter.localizationKey)) {
                        Task { await localLibrary.apply(sort: localLibrary.sort, filter: filter) }
                    }
                }
            }
        }.buttonStyle(.bordered)
    }
}
