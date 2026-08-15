import SwiftUI

enum LibrarySectionDestination: String, Hashable, Sendable {
    case playlists
    case releases
    case artists
    case favorites

    var titleKey: LocalizedStringKey {
        switch self {
        case .playlists: "library.playlists"
        case .releases: "library.releases"
        case .artists: "library.artists"
        case .favorites: "library.favorites"
        }
    }
}

struct LibrarySectionListScreen: View {
    @Environment(\.dismiss) private var dismiss

    let destination: LibrarySectionDestination

    var body: some View {
        ZStack {
            LibraryListBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    navigationHeader
                    content
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 30)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var navigationHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button(action: { dismiss() }) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left")
                    Text("library.title")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)

            Text(destination.titleKey)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination {
        case .playlists:
            LibraryPlaylistGrid()
        case .releases:
            LibraryReleaseGrid()
        case .artists:
            LibraryArtistList(artists: LibraryListArtist.allArtists)
        case .favorites:
            LibraryArtistList(artists: LibraryListArtist.favoriteArtists)
        }
    }
}

private struct LibraryPlaylistGrid: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(LibraryListPlaylist.samples) { playlist in
                NavigationLink(value: playlist.destination) {
                    VStack(alignment: .leading, spacing: 7) {
                        LibraryListArtwork(style: playlist.artwork)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                        Text(LocalizedStringKey(playlist.titleKey))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        Text(LocalizedStringKey(playlist.detailKey))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LibraryReleaseGrid: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(LibraryListRelease.samples) { release in
                NavigationLink(value: release.destination) {
                    VStack(alignment: .leading, spacing: 6) {
                        LibraryListArtwork(style: release.artwork)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                        Text(verbatim: release.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        Text(verbatim: release.metadata)
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.48))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LibraryArtistList: View {
    let artists: [LibraryListArtist]

    var body: some View {
        LazyVStack(spacing: 9) {
            ForEach(artists) { artist in
                NavigationLink(value: ArtistDetailDestination(name: artist.name)) {
                    HStack(spacing: 12) {
                        LibraryListArtwork(style: artist.artwork)
                            .frame(width: 52, height: 52)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: artist.name)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))

                            Text("library.artist_label")
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(.white.opacity(0.46))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.42))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 68)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(.white.opacity(0.10), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct LibraryListArtwork: View {
    let style: LibraryListArtworkStyle

    var body: some View {
        ZStack {
            switch style {
            case .misty:
                Image("MistyLake")
                    .resizable()
                    .scaledToFill()
            case .shore:
                Image("AuroraShore")
                    .resizable()
                    .scaledToFill()
            case .violet:
                LinearGradient(colors: [.purple, .indigo, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .amber:
                LinearGradient(colors: [.orange, .red.opacity(0.55), .black], startPoint: .topTrailing, endPoint: .bottomLeading)
            case .silver:
                LinearGradient(colors: [.white.opacity(0.58), .gray, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
            case .artist:
                Image("ArtistHero")
                    .resizable()
                    .scaledToFill()
            }
        }
        .clipped()
    }
}

private struct LibraryListBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.027, green: 0.03, blue: 0.04)
            RadialGradient(colors: [.indigo.opacity(0.18), .clear], center: .topLeading, startRadius: 10, endRadius: 480)
        }
        .ignoresSafeArea()
    }
}

private enum LibraryListArtworkStyle: String, Hashable, Sendable {
    case misty
    case shore
    case violet
    case amber
    case silver
    case artist

    var collectionArtwork: CollectionHeroArtwork {
        switch self {
        case .misty, .silver, .artist: .mistyLake
        case .shore, .amber: .sunset
        case .violet: .violet
        }
    }
}

private struct LibraryListPlaylist: Identifiable, Sendable {
    let id: String
    let titleKey: String
    let detailKey: String
    let metadataKey: String
    let artwork: LibraryListArtworkStyle

    var destination: CollectionDetailDestination {
        .playlist(titleKey: titleKey, metadataKey: metadataKey, artwork: artwork.collectionArtwork)
    }

    static let samples = [
        LibraryListPlaylist(id: "night", titleKey: "library.playlist_night", detailKey: "library.playlist_night_detail", metadataKey: "collection.night_metadata", artwork: .violet),
        LibraryListPlaylist(id: "training", titleKey: "library.playlist_training", detailKey: "library.playlist_training_detail", metadataKey: "collection.training_metadata", artwork: .misty),
        LibraryListPlaylist(id: "road", titleKey: "library.playlist_road", detailKey: "library.playlist_road_detail", metadataKey: "collection.road_metadata", artwork: .amber),
        LibraryListPlaylist(id: "focus", titleKey: "library.playlist_focus", detailKey: "library.playlist_focus_detail", metadataKey: "collection.focus_metadata", artwork: .silver),
        LibraryListPlaylist(id: "morning", titleKey: "library.playlist_morning", detailKey: "library.playlist_morning_detail", metadataKey: "collection.morning_metadata", artwork: .shore),
        LibraryListPlaylist(id: "archive", titleKey: "library.playlist_archive", detailKey: "library.playlist_archive_detail", metadataKey: "collection.archive_metadata", artwork: .misty)
    ]
}

private struct LibraryListRelease: Identifiable, Sendable {
    let id: String
    let title: String
    let metadata: String
    let metadataKey: String
    let artwork: LibraryListArtworkStyle

    var destination: CollectionDetailDestination {
        .release(title: title, metadataKey: metadataKey, artwork: artwork.collectionArtwork)
    }

    static let samples = [
        LibraryListRelease(id: "ram", title: "Random Access Memories", metadata: "Daft Punk · 2013", metadataKey: "library.release_album_2013", artwork: .silver),
        LibraryListRelease(id: "rainbows", title: "In Rainbows", metadata: "Radiohead · 2007", metadataKey: "library.release_album_2007", artwork: .violet),
        LibraryListRelease(id: "bangarang", title: "Bangarang EP", metadata: "Skrillex · 2011", metadataKey: "library.release_ep_2011", artwork: .amber),
        LibraryListRelease(id: "hurry", title: "Hurry Up Tomorrow", metadata: "The Weeknd · 2026", metadataKey: "artist.release_album_2026", artwork: .artist),
        LibraryListRelease(id: "dawn", title: "Dawn FM", metadata: "The Weeknd · 2022", metadataKey: "artist.release_album_2022", artwork: .misty),
        LibraryListRelease(id: "after-hours", title: "After Hours", metadata: "The Weeknd · 2020", metadataKey: "artist.release_album_2020", artwork: .shore)
    ]
}

private struct LibraryListArtist: Identifiable, Sendable {
    let id: String
    let name: String
    let artwork: LibraryListArtworkStyle

    static let allArtists = [
        LibraryListArtist(id: "weeknd", name: "The Weeknd", artwork: .artist),
        LibraryListArtist(id: "fred", name: "Fred again..", artwork: .misty),
        LibraryListArtist(id: "skrillex", name: "Skrillex", artwork: .amber),
        LibraryListArtist(id: "burial", name: "Burial", artwork: .violet),
        LibraryListArtist(id: "daft", name: "Daft Punk", artwork: .silver),
        LibraryListArtist(id: "radiohead", name: "Radiohead", artwork: .shore)
    ]

    static let favoriteArtists = [
        LibraryListArtist(id: "weeknd", name: "The Weeknd", artwork: .artist),
        LibraryListArtist(id: "aphex", name: "Aphex Twin", artwork: .silver),
        LibraryListArtist(id: "kanye", name: "Kanye West", artwork: .amber),
        LibraryListArtist(id: "boniver", name: "Bon Iver", artwork: .misty)
    ]
}

#Preview("Library playlists") {
    NavigationStack {
        LibrarySectionListScreen(destination: .playlists)
    }
}
