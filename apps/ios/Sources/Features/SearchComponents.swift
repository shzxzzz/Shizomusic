import SwiftUI

struct SearchField: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("search.placeholder", text: $query).textInputAutocapitalization(.never).autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .accessibilityLabel(Text("search.clear_query"))
            }
        }
        .padding(.horizontal, 14).frame(height: 46)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17))
    }
}

struct SearchCategoryBar: View {
    @Binding var selection: SearchCategory
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchCategory.allCases, id: \.self) { item in
                    Button { selection = item } label: {
                        Text(item.titleKey).font(.subheadline.weight(.semibold)).padding(.horizontal, 14).frame(height: 34)
                            .background(selection == item ? .purple.opacity(0.35) : .white.opacity(0.06), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct SearchTrackResults: View {
    let tracks: [PlayableTrack]
    let onPlay: (PlayableTrack) -> Void
    var body: some View {
        if !tracks.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SearchSectionTitle("search.tracks")
                ForEach(tracks) { track in
                    HStack(spacing: 4) {
                        Button { onPlay(track) } label: {
                            HStack(spacing: 12) {
                                TrackArtworkView(artworkURL: track.artworkURL, fallbackName: track.artworkName)
                                    .scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: track.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Text(verbatim: track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(verbatim: TimeInterval(track.durationSeconds).trackDurationText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        TrackActionsMenu(track: track)
                    }
                }
            }
        }
    }
}

struct SearchArtistResults: View {
    let artists: [LocalArtist]
    var body: some View {
        if !artists.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SearchSectionTitle("search.artists")
                ForEach(artists) { artist in
                    NavigationLink(value: ArtistDetailDestination(name: artist.name)) {
                        HStack(spacing: 12) {
                            TrackArtworkView(artworkURL: artist.artworkURL, fallbackName: "ArtistHero")
                                .scaledToFill().frame(width: 54, height: 54).clipShape(Circle())
                            VStack(alignment: .leading) {
                                Text(verbatim: artist.name).font(.headline)
                                Text("\(artist.tracks.count) \(String(localized: "collection.tracks_unit"))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct SearchReleaseResults: View {
    let releases: [LocalRelease]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    var body: some View {
        if !releases.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SearchSectionTitle("search.releases")
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(releases) { release in
                        NavigationLink(value: CollectionDetailDestination.release(id: release.id, title: release.title, artist: release.artist)) {
                            VStack(alignment: .leading, spacing: 7) {
                                TrackArtworkView(artworkURL: release.artworkURL, fallbackName: "MistyLake")
                                    .scaledToFill().aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 14))
                                Text(verbatim: release.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                Text(verbatim: release.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct SearchSectionTitle: View {
    let key: LocalizedStringKey
    init(_ key: LocalizedStringKey) { self.key = key }
    var body: some View { Text(key).font(.title3.bold()) }
}

struct CatalogEmptyState: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let icon: String
    var body: some View {
        ContentUnavailableView { Label(title, systemImage: icon) } description: { Text(detail) }
            .frame(maxWidth: .infinity).padding(.vertical, 50)
    }
}
