import SwiftUI

struct ArtistSectionListScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    let destination: ArtistSectionDestination

    private var artist: LocalArtist? { localLibrary.artists.first { $0.name == destination.artistName } }
    private var releases: [LocalRelease] {
        localLibrary.releases.filter { release in
            release.tracks.contains { track in
                track.artistNames.contains { $0.libraryNormalized == destination.artistName.libraryNormalized }
            }
        }
    }

    var body: some View {
        ZStack {
            ArtistDetailBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Button { dismiss() } label: { Label(destination.artistName, systemImage: "chevron.left") }.buttonStyle(.plain)
                    Text(destination.kind.titleKey).font(.largeTitle.bold())
                    content
                }
                .frame(maxWidth: 620, alignment: .leading).padding(16).frame(maxWidth: .infinity)
            }
        }.toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var content: some View {
        switch destination.kind {
        case .allTracks:
            SearchTrackResults(tracks: artist?.tracks ?? []) { track in
                let tracks = artist?.tracks ?? []
                playback.play(tracks, startingAt: tracks.firstIndex(of: track) ?? 0, context: .artist(destination.artistName.libraryNormalized))
            }
        case .releases:
            SearchReleaseResults(releases: releases)
        case .compilations, .familiar:
            CatalogEmptyState(title: "artist.section_empty_title", detail: "artist.section_empty_detail", icon: "music.note.list")
        }
    }
}
