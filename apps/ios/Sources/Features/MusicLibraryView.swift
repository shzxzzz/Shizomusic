import Foundation
import SwiftUI

struct MusicLibraryView: View {
    @State private var playlists = LibraryPlaylist.samples
    @State private var showsCreatePlaylist = false

    private let releases = LibraryRelease.samples
    private let topArtists = LibraryTopArtist.samples

    var body: some View {
        NavigationStack {
            ZStack {
                LibraryAmbientBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        libraryHeader
                        quickAccess
                        playlistsSection
                        releasesSection

                        Divider()
                            .overlay(.white.opacity(0.12))

                        artistsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                }
            }
            .navigationDestination(for: CollectionDetailDestination.self) { destination in
                CollectionDetailScreen(destination: destination)
            }
            .navigationDestination(for: LibrarySectionDestination.self) { destination in
                LibrarySectionListScreen(destination: destination)
            }
            .navigationDestination(for: ArtistDetailDestination.self) { destination in
                ArtistDetailScreen(destination: destination)
            }
            .navigationDestination(for: ArtistSectionDestination.self) { destination in
                ArtistSectionListScreen(destination: destination)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showsCreatePlaylist) {
            CreatePlaylistSheet { title, artworkStyle in
                playlists.insert(
                    LibraryPlaylist(
                        id: UUID().uuidString,
                        titleKey: title,
                        detailKey: "library.playlist_empty_detail",
                        collectionMetadataKey: "collection.empty_metadata",
                        detailArtwork: artworkStyle.detailArtwork,
                        artworkStyle: artworkStyle
                    ),
                    at: 0
                )
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .preferredColorScheme(.dark)
    }

    private var libraryHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("library.title")
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(verbatim: "@username")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            Spacer()
        }
        .foregroundStyle(.white)
    }

    private var quickAccess: some View {
        HStack(spacing: 10) {
            NavigationLink(value: CollectionDetailDestination.liked) {
                QuickAccessCard(
                    icon: "heart.fill",
                    iconColor: Color(red: 0.91, green: 0.54, blue: 0.96),
                    titleKey: "library.liked",
                    detailKey: "library.liked_detail"
                )
            }
            .buttonStyle(.plain)

            NavigationLink(value: CollectionDetailDestination.offline) {
                QuickAccessCard(
                    icon: "arrow.down.circle.fill",
                    iconColor: Color(red: 0.72, green: 0.76, blue: 0.80),
                    titleKey: "library.offline",
                    detailKey: "library.offline_detail"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var playlistsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                titleKey: "library.playlists",
                destination: .playlists,
                onAdd: { showsCreatePlaylist = true }
            )

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(playlists) { playlist in
                    NavigationLink(value: playlist.detailDestination) {
                        PlaylistTile(playlist: playlist)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var releasesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(titleKey: "library.releases", destination: .releases)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                spacing: 10
            ) {
                ForEach(releases) { release in
                    NavigationLink(value: release.detailDestination) {
                        ReleaseTile(release: release)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var artistsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(titleKey: "library.artists", destination: .artists)

            Text("library.top_this_month")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.48))

            VStack(spacing: 7) {
                ForEach(topArtists) { artist in
                    NavigationLink(value: artist.detailDestination) {
                        TopArtistRow(artist: artist)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LibraryAmbientBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.035, green: 0.04, blue: 0.055)

            RadialGradient(
                colors: [Color.indigo.opacity(0.20), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 420
            )

            RadialGradient(
                colors: [Color.cyan.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

private struct QuickAccessCard: View {
    let icon: String
    let iconColor: Color
    let titleKey: LocalizedStringKey
    let detailKey: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label {
                Text(titleKey)
                    .lineLimit(1)
            } icon: {
                Image(systemName: icon)
                    .foregroundStyle(iconColor)
            }
            .font(.system(size: 13, weight: .semibold, design: .rounded))

            Text(detailKey)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.58))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .frame(height: 68)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
    }
}

private struct SectionHeader: View {
    let titleKey: LocalizedStringKey
    let destination: LibrarySectionDestination
    var onAdd: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: destination) {
                HStack(spacing: 7) {
                    Text(titleKey)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.68))
                }
            }
            .buttonStyle(.plain)

            Spacer()

            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("library.add_playlist"))
            }
        }
        .foregroundStyle(.white)
    }
}

private struct PlaylistTile: View {
    let playlist: LibraryPlaylist

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LibraryArtwork(style: playlist.artworkStyle)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.72)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(playlist.titleKey))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .lineLimit(1)

                        Text(LocalizedStringKey(playlist.detailKey))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                    .padding(8)
                }

            Color.clear.frame(height: 0)
        }
        .foregroundStyle(.white)
    }
}

private struct ReleaseTile: View {
    let release: LibraryRelease

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            LibraryArtwork(style: release.artworkStyle)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(verbatim: release.title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Text(verbatim: release.artist)
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)

            Text(LocalizedStringKey(release.metaKey))
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
    }
}

private struct TopArtistRow: View {
    let artist: LibraryTopArtist

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: "\(artist.rank)")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.62))
                .frame(width: 18)

            ArtistAvatar(style: artist.avatarStyle)
                .frame(width: 32, height: 32)

            Text(verbatim: artist.name)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer(minLength: 8)

            Text(LocalizedStringKey(artist.durationKey))
                .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.54))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background(.thinMaterial, in: Capsule())
        .overlay {
            Capsule()
                .stroke(.white.opacity(0.11), lineWidth: 1)
        }
    }
}

private struct ArtistAvatar: View {
    let style: LibraryArtworkStyle

    var body: some View {
        LibraryArtwork(style: style)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
    }
}

private struct LibraryArtwork: View {
    let style: LibraryArtworkStyle

    var body: some View {
        ZStack {
            artworkBackground

            Image(systemName: style.symbol)
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white.opacity(0.74))
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
        }
    }

    @ViewBuilder
    private var artworkBackground: some View {
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
                colors: [Color(red: 0.12, green: 0.05, blue: 0.25), Color(red: 0.51, green: 0.24, blue: 0.72)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .sunset:
            LinearGradient(
                colors: [Color(red: 0.15, green: 0.10, blue: 0.22), Color(red: 0.90, green: 0.36, blue: 0.22)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        case .midnight:
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.03, blue: 0.07), Color(red: 0.15, green: 0.36, blue: 0.48)],
                startPoint: .bottom,
                endPoint: .top
            )
        case .silver:
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.13, blue: 0.15), Color(red: 0.73, green: 0.76, blue: 0.79)],
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        }
    }
}

private enum LibraryArtworkStyle: String, Hashable, Sendable {
    case mistyLake
    case auroraShore
    case violet
    case sunset
    case midnight
    case silver

    var symbol: String {
        switch self {
        case .mistyLake: "moon.stars.fill"
        case .auroraShore: "sparkles"
        case .violet: "waveform"
        case .sunset: "road.lanes"
        case .midnight: "headphones"
        case .silver: "music.note"
        }
    }

    var detailArtwork: CollectionHeroArtwork {
        switch self {
        case .mistyLake, .midnight: .mistyLake
        case .auroraShore, .sunset: .sunset
        case .violet: .violet
        case .silver: .mistyLake
        }
    }
}

private struct LibraryPlaylist: Identifiable, Sendable {
    let id: String
    let titleKey: String
    let detailKey: String
    let collectionMetadataKey: String
    let detailArtwork: CollectionHeroArtwork
    let artworkStyle: LibraryArtworkStyle

    var detailDestination: CollectionDetailDestination {
        .playlist(
            titleKey: titleKey,
            metadataKey: collectionMetadataKey,
            artwork: detailArtwork
        )
    }

    static let samples = [
        LibraryPlaylist(id: "night", titleKey: "library.playlist_night", detailKey: "library.playlist_night_detail", collectionMetadataKey: "collection.night_metadata", detailArtwork: .violet, artworkStyle: .violet),
        LibraryPlaylist(id: "training", titleKey: "library.playlist_training", detailKey: "library.playlist_training_detail", collectionMetadataKey: "collection.training_metadata", detailArtwork: .mistyLake, artworkStyle: .midnight),
        LibraryPlaylist(id: "road", titleKey: "library.playlist_road", detailKey: "library.playlist_road_detail", collectionMetadataKey: "collection.road_metadata", detailArtwork: .sunset, artworkStyle: .sunset)
    ]
}

private struct LibraryRelease: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let metaKey: String
    let artworkStyle: LibraryArtworkStyle

    var detailDestination: CollectionDetailDestination {
        .release(
            title: title,
            metadataKey: metaKey,
            artwork: artworkStyle.detailArtwork
        )
    }

    static let samples = [
        LibraryRelease(id: "ram", title: "Random Access…", artist: "Daft Punk", metaKey: "library.release_album_2013", artworkStyle: .silver),
        LibraryRelease(id: "rainbows", title: "In Rainbows", artist: "Radiohead", metaKey: "library.release_album_2007", artworkStyle: .violet),
        LibraryRelease(id: "bangarang", title: "Bangarang EP", artist: "Skrillex", metaKey: "library.release_ep_2011", artworkStyle: .sunset)
    ]
}

private struct LibraryTopArtist: Identifiable, Sendable {
    let id: Int
    let rank: Int
    let name: String
    let durationKey: String
    let avatarStyle: LibraryArtworkStyle

    var detailDestination: ArtistDetailDestination {
        ArtistDetailDestination(name: name)
    }

    static let samples = [
        LibraryTopArtist(id: 1, rank: 1, name: "Fred again..", durationKey: "library.duration_7_12", avatarStyle: .mistyLake),
        LibraryTopArtist(id: 2, rank: 2, name: "Skrillex", durationKey: "library.duration_5_48", avatarStyle: .sunset),
        LibraryTopArtist(id: 3, rank: 3, name: "Burial", durationKey: "library.duration_3_04", avatarStyle: .midnight)
    ]
}

private struct CreatePlaylistSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var selectedArtwork: LibraryArtworkStyle = .violet

    let onCreate: (String, LibraryArtworkStyle) -> Void

    private let artworkOptions: [LibraryArtworkStyle] = [
        .violet,
        .mistyLake,
        .sunset,
        .silver
    ]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                TextField("playlist_create.name_placeholder", text: $title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 16)
                    .frame(height: 54)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    Text("playlist_create.cover")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))

                    HStack(spacing: 12) {
                        ForEach(artworkOptions, id: \.self) { artwork in
                            Button {
                                selectedArtwork = artwork
                            } label: {
                                LibraryArtwork(style: artwork)
                                    .frame(maxWidth: .infinity)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(
                                                selectedArtwork == artwork ? Color.white : Color.white.opacity(0.10),
                                                lineWidth: selectedArtwork == artwork ? 2 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("playlist_create.title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("playlist_create.cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("playlist_create.create") {
                        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        onCreate(normalizedTitle, selectedArtwork)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
