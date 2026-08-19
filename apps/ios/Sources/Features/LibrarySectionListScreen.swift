import SwiftUI

enum LibrarySectionDestination: String, Hashable, Sendable {
    case playlists, releases, artists
    var titleKey: LocalizedStringKey {
        switch self {
        case .playlists: "library.playlists"
        case .releases: "library.releases"
        case .artists: "library.artists"
        }
    }
}

struct LibrarySectionListScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    let destination: LibrarySectionDestination

    var body: some View {
        ZStack {
            ArtistDetailBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Button { dismiss() } label: { Label("library.title", systemImage: "chevron.left") }.buttonStyle(.plain)
                    Text(destination.titleKey).font(.largeTitle.bold())
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
        switch destination {
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
