import SwiftUI

struct ArtistSectionListScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: MockPlaybackState

    @State private var familiarSelection: ArtistFamiliarSelection = .liked

    let destination: ArtistSectionDestination

    private var model: ArtistDetailPreviewModel {
        ArtistDetailPreviewModel(name: destination.artistName)
    }

    var body: some View {
        ZStack {
            ArtistDetailBackground()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    navigationHeader
                    content
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 34)
                .frame(maxWidth: .infinity)
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
                    Text(verbatim: destination.artistName)
                        .lineLimit(1)
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("collection.back"))

            Text(destination.kind.titleKey)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch destination.kind {
        case .allTracks:
            trackList(allTracks)
        case .releases:
            releaseGrid
        case .compilations:
            compilationList
        case .familiar:
            familiarContent
        }
    }

    private var allTracks: [ArtistTrackPreviewModel] {
        var seen = Set<String>()
        return (model.recentTracks + model.likedTracks + model.familiarTracks).filter {
            seen.insert($0.id).inserted
        }
    }

    private var releaseGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 20
        ) {
            ForEach(model.releases) { release in
                NavigationLink(value: release.detailDestination) {
                    VStack(alignment: .leading, spacing: 7) {
                        Image(release.artworkName)
                            .resizable()
                            .scaledToFill()
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                        Text(verbatim: release.title)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .lineLimit(2)

                        Text(LocalizedStringKey(release.typeYearKey))
                            .font(.system(size: 11, design: .rounded))
                            .foregroundStyle(.white.opacity(0.46))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var compilationList: some View {
        LazyVStack(spacing: 10) {
            ForEach(model.compilations) { compilation in
                NavigationLink(value: compilation.detailDestination) {
                    HStack(spacing: 13) {
                        Image(compilation.artworkName)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))

                        VStack(alignment: .leading, spacing: 5) {
                            Text(verbatim: compilation.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                            Text(verbatim: compilation.artist)
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.white.opacity(0.52))
                            Text(verbatim: compilation.year)
                                .font(.system(size: 11, design: .rounded))
                                .foregroundStyle(.white.opacity(0.38))
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.36))
                    }
                    .foregroundStyle(.white)
                    .padding(10)
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

    private var familiarContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ArtistFamiliarSegmentedControl(selection: $familiarSelection)
            trackList(familiarSelection == .liked ? model.likedTracks : model.familiarTracks)
        }
        .animation(.easeInOut(duration: 0.18), value: familiarSelection)
    }

    private func trackList(_ tracks: [ArtistTrackPreviewModel]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(tracks) { track in
                ArtistTrackRow(
                    track: track,
                    isCurrent: playback.currentTrack.id == track.id,
                    onTap: { playback.play(track.playableTrack(artist: model.name)) }
                )

                if track.id != tracks.last?.id {
                    Divider()
                        .overlay(.white.opacity(0.075))
                        .padding(.leading, 58)
                }
            }
        }
    }
}

#Preview("Artist familiar") {
    NavigationStack {
        ArtistSectionListScreen(
            destination: ArtistSectionDestination(artistName: "The Weeknd", kind: .familiar)
        )
    }
    .environmentObject(MockPlaybackState())
}
