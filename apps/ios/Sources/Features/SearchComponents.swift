import SwiftUI

struct SearchField: View {
    @Binding var query: String
    let onQueryChanged: () -> Void
    let onSubmit: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))

            TextField("search.placeholder", text: $query)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .onChange(of: query) { onQueryChanged() }

            if !query.isEmpty {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("search.clear_query"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.12), lineWidth: 1)
        }
    }
}

struct SearchCategoryBar: View {
    @Binding var selection: SearchCategory

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchCategory.allCases, id: \.self) { category in
                    Button {
                        selection = category
                    } label: {
                        Text(category.titleKey)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(selection == category ? .white : .white.opacity(0.48))
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background {
                                Capsule()
                                    .fill(.thinMaterial)
                                    .overlay {
                                        Capsule().fill(
                                            selection == category
                                                ? Color.purple.opacity(0.24)
                                                : Color.white.opacity(0.025)
                                        )
                                    }
                            }
                            .overlay {
                                Capsule().stroke(.white.opacity(selection == category ? 0.15 : 0.07), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == category ? .isSelected : [])
                }
            }
        }
    }
}

struct SearchAllResults: View {
    let onPlayTrack: (SearchTrackPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 12) {
                SearchSectionTitle("search.best_match")
                SearchBestMatchCard(artist: SearchArtistPreview.samples[0])
            }

            VStack(alignment: .leading, spacing: 10) {
                SearchSectionTitle("search.artists")
                ForEach(SearchArtistPreview.samples.prefix(3)) { artist in
                    SearchArtistRow(artist: artist)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                SearchSectionTitle("search.tracks")
                ForEach(SearchTrackPreview.samples.prefix(4)) { track in
                    SearchTrackRow(track: track, onTap: { onPlayTrack(track) })
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SearchSectionTitle("search.releases")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(SearchReleasePreview.samples) { release in
                            SearchReleaseCard(release: release, width: 132)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                SearchSectionTitle("search.playlists")
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(SearchPlaylistPreview.samples) { playlist in
                            SearchPlaylistCard(playlist: playlist, width: 148)
                        }
                    }
                }
            }
        }
    }
}

struct SearchTracksResults: View {
    @State private var sort: SearchTrackSort = .relevance
    let onPlayTrack: (SearchTrackPreview) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SearchSectionTitle("search.tracks")
                Spacer()
                Menu {
                    ForEach(SearchTrackSort.allCases, id: \.self) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option {
                                Label(option.titleKey, systemImage: "checkmark")
                            } else {
                                Text(option.titleKey)
                            }
                        }
                    }
                } label: {
                    Label("search.sort", systemImage: "arrow.up.arrow.down")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.58))
                }
            }

            ForEach(SearchTrackPreview.samples) { track in
                SearchTrackRow(track: track, onTap: { onPlayTrack(track) })
            }
        }
    }
}

struct SearchArtistsResults: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SearchSectionTitle("search.artists")
            ForEach(SearchArtistPreview.samples) { artist in
                SearchArtistRow(artist: artist)
            }
        }
    }
}

struct SearchReleasesResults: View {
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchSectionTitle("search.releases")
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(SearchReleasePreview.samples) { release in
                    SearchReleaseCard(release: release, width: nil)
                }
            }
        }
    }
}

struct SearchPlaylistsResults: View {
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SearchSectionTitle("search.playlists")
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(SearchPlaylistPreview.samples) { playlist in
                    SearchPlaylistCard(playlist: playlist, width: nil)
                }
            }
        }
    }
}

struct SearchBestMatchCard: View {
    let artist: SearchArtistPreview

    var body: some View {
        NavigationLink(value: ArtistDetailDestination(name: artist.name)) {
            HStack(spacing: 16) {
                SearchArtwork(name: artist.artworkName)
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: artist.name)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .lineLimit(2)
                    Text("search.artist_label")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.48))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.42))
            }
            .foregroundStyle(.white)
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.11), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SearchArtistRow: View {
    let artist: SearchArtistPreview

    var body: some View {
        NavigationLink(value: ArtistDetailDestination(name: artist.name)) {
            HStack(spacing: 12) {
                SearchArtwork(name: artist.artworkName)
                    .frame(width: 54, height: 54)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: artist.name)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                    Text("search.artist_label")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.44))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.34))
            }
            .foregroundStyle(.white)
            .frame(minHeight: 66)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SearchTrackRow: View {
    let track: SearchTrackPreview
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                SearchArtwork(name: track.artworkName)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: track.title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(verbatim: track.artist)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if track.isAvailableOffline {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.34))
                        .accessibilityLabel(Text("search.available_offline"))
                }

                Text(verbatim: track.durationText)
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.42))
            }
            .foregroundStyle(.white)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(track.title), \(track.artist), \(track.durationText)"))
    }
}

struct SearchReleaseCard: View {
    let release: SearchReleasePreview
    let width: CGFloat?

    var body: some View {
        NavigationLink(value: release.destination) {
            VStack(alignment: .leading, spacing: 7) {
                SearchArtwork(name: release.artworkName)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(verbatim: release.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)

                Text(LocalizedStringKey(release.metadataKey))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
            }
            .foregroundStyle(.white)
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct SearchPlaylistCard: View {
    let playlist: SearchPlaylistPreview
    let width: CGFloat?

    var body: some View {
        NavigationLink(value: playlist.destination) {
            VStack(alignment: .leading, spacing: 7) {
                SearchArtwork(name: playlist.artworkName)
                    .aspectRatio(1, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                Text(verbatim: playlist.title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(2)

                Text(LocalizedStringKey(playlist.detailKey))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white)
            .frame(width: width, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}

struct SearchSectionTitle: View {
    let key: LocalizedStringKey

    init(_ key: LocalizedStringKey) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 19, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
    }
}

enum SearchStatusBannerKind: Equatable, Sendable {
    case loading
    case providerError
}

struct SearchStatusBanner: View {
    let kind: SearchStatusBannerKind

    var body: some View {
        HStack(spacing: 10) {
            if kind == .loading {
                ProgressView()
                    .controlSize(.small)
                Text("search.searching_more")
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow.opacity(0.72))
                Text("search.provider_error")
            }
            Spacer()
        }
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .foregroundStyle(.white.opacity(0.65))
        .padding(.horizontal, 13)
        .frame(minHeight: 42)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct SearchEmptyState: View {
    let isOffline: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: isOffline ? "wifi.slash" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.white.opacity(0.48))
            Text(LocalizedStringKey(isOffline ? "search.offline_empty_title" : "search.empty_title"))
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text(LocalizedStringKey(isOffline ? "search.offline_empty_detail" : "search.empty_detail"))
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }
}

struct SearchArtwork: View {
    let name: String

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .clipped()
    }
}

enum SearchTrackSort: CaseIterable, Hashable, Sendable {
    case relevance
    case title
    case artist

    var titleKey: LocalizedStringKey {
        switch self {
        case .relevance: "search.sort_relevance"
        case .title: "search.sort_title"
        case .artist: "search.sort_artist"
        }
    }
}

struct SearchArtistPreview: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let artworkName: String

    static let samples = [
        SearchArtistPreview(id: "skrillex", name: "Skrillex", artworkName: "ArtistHero"),
        SearchArtistPreview(id: "fred", name: "Fred again..", artworkName: "AuroraShore"),
        SearchArtistPreview(id: "burial", name: "Burial", artworkName: "MistyLake"),
        SearchArtistPreview(id: "daft", name: "Daft Punk", artworkName: "ArtistHero"),
        SearchArtistPreview(id: "radiohead", name: "Radiohead", artworkName: "AuroraShore")
    ]
}

struct SearchTrackPreview: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let durationText: String
    let durationSeconds: Int
    let artworkName: String
    let isAvailableOffline: Bool

    var playableTrack: MockPlayableTrack {
        MockPlayableTrack(
            id: id,
            title: title,
            artist: artist,
            durationSeconds: durationSeconds,
            artworkName: artworkName
        )
    }

    static let samples = [
        SearchTrackPreview(id: "bangarang", title: "Bangarang", artist: "Skrillex", durationText: "3:35", durationSeconds: 215, artworkName: "ArtistHero", isAvailableOffline: true),
        SearchTrackPreview(id: "where-are-u-now", title: "Where Are Ü Now", artist: "Jack Ü, Skrillex", durationText: "4:10", durationSeconds: 250, artworkName: "AuroraShore", isAvailableOffline: false),
        SearchTrackPreview(id: "supersonic", title: "Supersonic", artist: "Skrillex, Noisia", durationText: "2:47", durationSeconds: 167, artworkName: "MistyLake", isAvailableOffline: false),
        SearchTrackPreview(id: "rumble", title: "Rumble", artist: "Skrillex, Fred again..", durationText: "2:26", durationSeconds: 146, artworkName: "AuroraShore", isAvailableOffline: true),
        SearchTrackPreview(id: "first-of-year", title: "First of the Year", artist: "Skrillex", durationText: "4:22", durationSeconds: 262, artworkName: "ArtistHero", isAvailableOffline: false),
        SearchTrackPreview(id: "kyoto", title: "Kyoto", artist: "Skrillex", durationText: "3:21", durationSeconds: 201, artworkName: "MistyLake", isAvailableOffline: false)
    ]
}

struct SearchReleasePreview: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let metadataKey: String
    let artworkName: String
    let detailArtwork: CollectionHeroArtwork

    var destination: CollectionDetailDestination {
        .release(title: title, metadataKey: metadataKey, artwork: detailArtwork)
    }

    static let samples = [
        SearchReleasePreview(id: "quest", title: "Quest for Fire", metadataKey: "search.release_album_2023", artworkName: "ArtistHero", detailArtwork: .violet),
        SearchReleasePreview(id: "dont-close", title: "Don't Get Too Close", metadataKey: "search.release_album_2023", artworkName: "AuroraShore", detailArtwork: .sunset),
        SearchReleasePreview(id: "bangarang-release", title: "Bangarang EP", metadataKey: "library.release_ep_2011", artworkName: "MistyLake", detailArtwork: .mistyLake),
        SearchReleasePreview(id: "recess", title: "Recess", metadataKey: "search.release_album_2014", artworkName: "AuroraShore", detailArtwork: .sunset)
    ]
}

struct SearchPlaylistPreview: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let detailKey: String
    let artworkName: String
    let detailArtwork: CollectionHeroArtwork

    var destination: CollectionDetailDestination {
        .playlist(titleKey: title, metadataKey: "search.playlist_metadata", artwork: detailArtwork)
    }

    static let samples = [
        SearchPlaylistPreview(id: "bass", title: "Bass Essentials", detailKey: "search.playlist_42_tracks", artworkName: "ArtistHero", detailArtwork: .violet),
        SearchPlaylistPreview(id: "late", title: "Late Night Energy", detailKey: "search.playlist_31_tracks", artworkName: "AuroraShore", detailArtwork: .sunset),
        SearchPlaylistPreview(id: "electronic", title: "Electronic Focus", detailKey: "search.playlist_54_tracks", artworkName: "MistyLake", detailArtwork: .mistyLake),
        SearchPlaylistPreview(id: "festival", title: "Festival Archive", detailKey: "search.playlist_68_tracks", artworkName: "AuroraShore", detailArtwork: .sunset)
    ]
}
