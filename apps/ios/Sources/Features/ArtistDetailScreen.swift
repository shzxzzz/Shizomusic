import SwiftUI

struct ArtistDetailDestination: Hashable, Sendable { let name: String }

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
    let destination: ArtistDetailDestination

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
                    } else {
                        CatalogEmptyState(title: "artist.local_empty_title", detail: "artist.local_empty_detail", icon: "person.crop.circle.badge.questionmark")
                    }
                }
                .frame(maxWidth: 620, alignment: .leading).padding(16).padding(.bottom, 40).frame(maxWidth: .infinity)
            }
        }
        .navigationDestination(for: CollectionDetailDestination.self) { CollectionDetailScreen(destination: $0) }
        .toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { dismiss() } label: { Label("collection.back", systemImage: "chevron.left") }.buttonStyle(.plain)
            HStack(spacing: 18) {
                TrackArtworkView(artworkURL: artist?.artworkURL, fallbackName: "ArtistHero")
                    .scaledToFill().frame(width: 110, height: 110).clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: destination.name).font(.largeTitle.bold()).lineLimit(2)
                    if let artist { Text("\(artist.tracks.count) \(String(localized: "collection.tracks_unit"))").foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func play(_ track: PlayableTrack) {
        guard let artist else { return }
        playback.play(artist.tracks, startingAt: artist.tracks.firstIndex(of: track) ?? 0, context: .artist(artist.id))
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
}
