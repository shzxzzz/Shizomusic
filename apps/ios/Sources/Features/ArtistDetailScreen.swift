import SwiftUI

struct ArtistDetailDestination: Hashable, Sendable {
    let name: String
}

enum ArtistSectionKind: String, Hashable, Sendable {
    case allTracks
    case releases
    case compilations
    case familiar

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
    @EnvironmentObject private var playback: MockPlaybackState

    @State private var isLiked = false
    @State private var familiarSelection: ArtistFamiliarSelection = .liked
    @State private var heroBottom: CGFloat = 1_000

    let destination: ArtistDetailDestination

    private var model: ArtistDetailPreviewModel {
        ArtistDetailPreviewModel(name: destination.name)
    }

    private var showsStickyHeader: Bool {
        heroBottom < 78
    }

    var body: some View {
        ZStack(alignment: .top) {
            ArtistDetailBackground()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 30) {
                    ArtistHero(
                        name: model.name,
                        onBack: { dismiss() }
                    )
                    .padding(.horizontal, -16)
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: ArtistHeroBottomPreferenceKey.self,
                                value: proxy.frame(in: .named("artist-scroll")).maxY
                            )
                        }
                    }

                    ArtistPrimaryControls(
                        artistName: model.name,
                        isLiked: $isLiked,
                        onPlay: playArtist
                    )

                    ArtistLatestReleaseSection(
                        artistName: model.name,
                        release: model.latestRelease
                    )

                    ArtistTracksSection(
                        artistName: model.name,
                        titleKey: "artist.all_tracks",
                        tracks: model.recentTracks,
                        currentTrackID: playback.currentTrack.id,
                        onTrackTapped: playTrack
                    )

                    ArtistReleasesSection(artistName: model.name, releases: model.releases)

                    ArtistCompilationsSection(artistName: model.name, compilations: model.compilations)

                    ArtistFamiliarSection(
                        artistName: model.name,
                        selection: $familiarSelection,
                        likedTracks: model.likedTracks,
                        familiarTracks: model.familiarTracks,
                        currentTrackID: playback.currentTrack.id,
                        onTrackTapped: playTrack
                    )
                }
                .frame(maxWidth: 620)
                .padding(.horizontal, 16)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea(edges: .top)
            .coordinateSpace(name: "artist-scroll")
            .onPreferenceChange(ArtistHeroBottomPreferenceKey.self) { value in
                heroBottom = value
            }

            if showsStickyHeader {
                StickyArtistHeader(
                    name: model.name,
                    onBack: { dismiss() },
                    onPlay: playArtist
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(2)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: showsStickyHeader)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func playArtist() {
        guard let firstTrack = model.recentTracks.first else { return }
        playTrack(firstTrack)
    }

    private func playTrack(_ track: ArtistTrackPreviewModel) {
        playback.play(track.playableTrack(artist: model.name))
    }
}

enum ArtistFamiliarSelection: String, CaseIterable, Hashable, Sendable {
    case liked
    case familiar

    var titleKey: LocalizedStringKey {
        switch self {
        case .liked: "artist.liked_tracks"
        case .familiar: "artist.familiar_tracks"
        }
    }
}

struct ArtistDetailPreviewModel: Sendable {
    let name: String
    let latestRelease: ArtistReleasePreviewModel
    let recentTracks: [ArtistTrackPreviewModel]
    let releases: [ArtistReleasePreviewModel]
    let compilations: [ArtistCompilationPreviewModel]
    let likedTracks: [ArtistTrackPreviewModel]
    let familiarTracks: [ArtistTrackPreviewModel]

    init(name: String) {
        self.name = name
        self.latestRelease = ArtistReleasePreviewModel.latest
        self.recentTracks = ArtistTrackPreviewModel.recent
        self.releases = ArtistReleasePreviewModel.releases
        self.compilations = ArtistCompilationPreviewModel.samples
        self.likedTracks = ArtistTrackPreviewModel.liked
        self.familiarTracks = ArtistTrackPreviewModel.familiar
    }
}

struct ArtistTrackPreviewModel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let durationText: String
    let durationSeconds: Int
    let artworkName: String

    func playableTrack(artist: String) -> MockPlayableTrack {
        MockPlayableTrack(
            id: id,
            title: title,
            artist: artist,
            durationSeconds: durationSeconds,
            artworkName: artworkName
        )
    }

    static let recent = [
        ArtistTrackPreviewModel(id: "dancing-in-flames", title: "Dancing In The Flames", durationText: "4:02", durationSeconds: 242, artworkName: "AuroraShore"),
        ArtistTrackPreviewModel(id: "sao-paulo", title: "São Paulo", durationText: "3:37", durationSeconds: 217, artworkName: "ArtistHero"),
        ArtistTrackPreviewModel(id: "open-hearts", title: "Open Hearts", durationText: "3:49", durationSeconds: 229, artworkName: "MistyLake")
    ]

    static let liked = [
        ArtistTrackPreviewModel(id: "blinding-lights", title: "Blinding Lights", durationText: "3:20", durationSeconds: 200, artworkName: "AuroraShore"),
        ArtistTrackPreviewModel(id: "save-your-tears", title: "Save Your Tears", durationText: "3:35", durationSeconds: 215, artworkName: "ArtistHero"),
        ArtistTrackPreviewModel(id: "starboy", title: "Starboy", durationText: "3:50", durationSeconds: 230, artworkName: "MistyLake")
    ]

    static let familiar = [
        ArtistTrackPreviewModel(id: "in-your-eyes", title: "In Your Eyes", durationText: "3:57", durationSeconds: 237, artworkName: "ArtistHero"),
        ArtistTrackPreviewModel(id: "initiation", title: "Initiation", durationText: "4:20", durationSeconds: 260, artworkName: "MistyLake"),
        ArtistTrackPreviewModel(id: "take-my-breath", title: "Take My Breath", durationText: "3:40", durationSeconds: 220, artworkName: "AuroraShore")
    ]
}

struct ArtistReleasePreviewModel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let typeYearKey: String
    let artworkName: String
    let detailArtwork: CollectionHeroArtwork

    var detailDestination: CollectionDetailDestination {
        .release(title: title, metadataKey: typeYearKey, artwork: detailArtwork)
    }

    static let latest = ArtistReleasePreviewModel(
        id: "hurry-up-tomorrow",
        title: "Hurry Up Tomorrow",
        typeYearKey: "artist.release_album_date_2026",
        artworkName: "AuroraShore",
        detailArtwork: .violet
    )

    static let releases = [
        ArtistReleasePreviewModel(id: "hurry", title: "Hurry Up Tomorrow", typeYearKey: "artist.release_album_2026", artworkName: "AuroraShore", detailArtwork: .sunset),
        ArtistReleasePreviewModel(id: "dawn-fm", title: "Dawn FM", typeYearKey: "artist.release_album_2022", artworkName: "MistyLake", detailArtwork: .mistyLake),
        ArtistReleasePreviewModel(id: "after-hours", title: "After Hours", typeYearKey: "artist.release_album_2020", artworkName: "AuroraShore", detailArtwork: .sunset),
        ArtistReleasePreviewModel(id: "starboy-release", title: "Starboy", typeYearKey: "artist.release_album_2016", artworkName: "ArtistHero", detailArtwork: .violet),
        ArtistReleasePreviewModel(id: "beauty", title: "Beauty Behind the Madness", typeYearKey: "artist.release_album_2015", artworkName: "MistyLake", detailArtwork: .mistyLake)
    ]
}

struct ArtistCompilationPreviewModel: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let year: String
    let artworkName: String
    let detailArtwork: CollectionHeroArtwork

    var detailDestination: CollectionDetailDestination {
        .release(title: title, metadataKey: "artist.compilation_metadata", artwork: detailArtwork)
    }

    static let samples = [
        ArtistCompilationPreviewModel(id: "popular", title: "Popular", artist: "Madonna", year: "2023", artworkName: "ArtistHero", detailArtwork: .violet),
        ArtistCompilationPreviewModel(id: "one-right-now", title: "One Right Now", artist: "Post Malone", year: "2022", artworkName: "AuroraShore", detailArtwork: .sunset),
        ArtistCompilationPreviewModel(id: "moth-to-flame", title: "Moth To A Flame", artist: "Swedish House Mafia", year: "2021", artworkName: "MistyLake", detailArtwork: .mistyLake)
    ]
}

struct ArtistHeroBottomPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 1_000

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview("Artist detail") {
    NavigationStack {
        ArtistDetailScreen(destination: ArtistDetailDestination(name: "The Weeknd"))
    }
    .environmentObject(MockPlaybackState())
}
