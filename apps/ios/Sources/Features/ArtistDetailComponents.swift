import SwiftUI

struct ArtistHero: View {
    let name: String
    let onBack: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image("ArtistHero")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .frame(height: 390, alignment: .top)
                .clipped()
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .white, location: 0),
                            .init(color: .white, location: 0.55),
                            .init(color: .white.opacity(0.52), location: 0.68),
                            .init(color: .clear, location: 0.79)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.32),
                    .init(color: .black.opacity(0.18), location: 0.52),
                    .init(color: Color(red: 0.024, green: 0.026, blue: 0.034), location: 0.80),
                    .init(color: Color(red: 0.024, green: 0.026, blue: 0.034), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            Text(verbatim: name)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

            VStack {
                HStack {
                    Button(action: onBack) {
                        HStack(spacing: 7) {
                            Image(systemName: "chevron.left")
                            Text("library.title")
                        }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.76))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("collection.back"))

                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)

                Spacer()
            }
        }
        .frame(height: 390)
    }
}

struct ArtistPrimaryControls: View {
    let artistName: String
    @Binding var isLiked: Bool
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onPlay) {
                Label("artist.listen", systemImage: "play.fill")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(Color.purple.opacity(0.68), in: Capsule())
                    .background(.thinMaterial, in: Capsule())
                    .overlay {
                        Capsule().stroke(.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(ArtistPressButtonStyle())
            .accessibilityLabel(Text("artist.listen"))
            .accessibilityValue(Text(verbatim: artistName))

            Button {
                isLiked.toggle()
            } label: {
                Image(systemName: isLiked ? "heart.fill" : "heart")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isLiked ? .pink : .white)
                    .frame(width: 52, height: 52)
                    .background(.thinMaterial, in: Circle())
                    .overlay {
                        Circle().stroke(.white.opacity(0.14), lineWidth: 1)
                    }
            }
            .buttonStyle(ArtistPressButtonStyle())
            .accessibilityLabel(
                Text(LocalizedStringKey(isLiked ? "artist.unlike" : "artist.like"))
            )
        }
    }
}

struct ArtistLatestReleaseSection: View {
    let artistName: String
    let release: ArtistReleasePreviewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("artist.latest_release")
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            NavigationLink(value: release.detailDestination) {
                HStack(spacing: 14) {
                    Image(release.artworkName)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 94, height: 94)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 5) {
                        Text(verbatim: release.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .lineLimit(2)

                        Text(verbatim: artistName)
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.52))

                        Text(LocalizedStringKey(release.typeYearKey))
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.42))
                    }

                    Spacer(minLength: 6)

                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.09), in: Circle())
                }
                .foregroundStyle(.white)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("artist.latest_release_accessibility"))
        }
    }
}

struct ArtistTracksSection: View {
    let artistName: String
    let titleKey: LocalizedStringKey
    let tracks: [ArtistTrackPreviewModel]
    let currentTrackID: String
    let onTrackTapped: (ArtistTrackPreviewModel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ArtistSectionHeader(
                titleKey: titleKey,
                destination: ArtistSectionDestination(artistName: artistName, kind: .allTracks)
            )

            VStack(spacing: 0) {
                ForEach(tracks) { track in
                    ArtistTrackRow(
                        track: track,
                        isCurrent: currentTrackID == track.id,
                        onTap: { onTrackTapped(track) }
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
}

struct ArtistTrackRow: View {
    let track: ArtistTrackPreviewModel
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 11) {
                Image(track.artworkName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(verbatim: track.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(isCurrent ? Color.cyan.opacity(0.90) : .white)
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(verbatim: track.durationText)
                    .font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.44))
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(track.title), \(track.durationText)"))
    }
}

struct ArtistReleasesSection: View {
    let artistName: String
    let releases: [ArtistReleasePreviewModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArtistSectionHeader(
                titleKey: "artist.releases",
                destination: ArtistSectionDestination(artistName: artistName, kind: .releases)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(releases) { release in
                        NavigationLink(value: release.detailDestination) {
                            VStack(alignment: .leading, spacing: 6) {
                                Image(release.artworkName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 122, height: 122)
                                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                                Text(verbatim: release.title)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .lineLimit(2)

                                Text(LocalizedStringKey(release.typeYearKey))
                                    .font(.system(size: 10, weight: .regular, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.44))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white)
                            .frame(width: 122, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ArtistCompilationsSection: View {
    let artistName: String
    let compilations: [ArtistCompilationPreviewModel]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArtistSectionHeader(
                titleKey: "artist.compilations",
                destination: ArtistSectionDestination(artistName: artistName, kind: .compilations)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(compilations) { compilation in
                        NavigationLink(value: compilation.detailDestination) {
                            HStack(spacing: 10) {
                                Image(compilation.artworkName)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 70, height: 70)
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(verbatim: compilation.title)
                                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                                        .lineLimit(1)

                                    Text(verbatim: compilation.artist)
                                        .font(.system(size: 11, weight: .regular, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.52))

                                    Text(verbatim: compilation.year)
                                        .font(.system(size: 10, weight: .regular, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.38))
                                }

                                Spacer(minLength: 0)
                            }
                            .foregroundStyle(.white)
                            .padding(8)
                            .frame(width: 238, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 17, style: .continuous)
                                    .stroke(.white.opacity(0.10), lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct ArtistFamiliarSection: View {
    let artistName: String
    @Binding var selection: ArtistFamiliarSelection
    let likedTracks: [ArtistTrackPreviewModel]
    let familiarTracks: [ArtistTrackPreviewModel]
    let currentTrackID: String
    let onTrackTapped: (ArtistTrackPreviewModel) -> Void

    private var visibleTracks: [ArtistTrackPreviewModel] {
        selection == .liked ? likedTracks : familiarTracks
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ArtistSectionHeader(
                titleKey: "artist.familiar",
                destination: ArtistSectionDestination(artistName: artistName, kind: .familiar)
            )

            ArtistFamiliarSegmentedControl(selection: $selection)

            VStack(spacing: 0) {
                ForEach(visibleTracks) { track in
                    ArtistTrackRow(
                        track: track,
                        isCurrent: currentTrackID == track.id,
                        onTap: { onTrackTapped(track) }
                    )

                    if track.id != visibleTracks.last?.id {
                        Divider()
                            .overlay(.white.opacity(0.075))
                            .padding(.leading, 58)
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selection)
    }
}

struct ArtistFamiliarSegmentedControl: View {
    @Binding var selection: ArtistFamiliarSelection

    var body: some View {
        HStack(spacing: 4) {
            ForEach(ArtistFamiliarSelection.allCases, id: \.self) { segment in
                Button {
                    selection = segment
                } label: {
                    Text(segment.titleKey)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(selection == segment ? .white : .white.opacity(0.48))
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            selection == segment ? Color.purple.opacity(0.30) : Color.clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == segment ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay {
            Capsule().stroke(.white.opacity(0.11), lineWidth: 1)
        }
    }
}

struct ArtistSectionHeader: View {
    let titleKey: LocalizedStringKey
    let destination: ArtistSectionDestination

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 7) {
                Text(titleKey)
                    .font(.system(size: 19, weight: .bold, design: .rounded))

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.60))
            }
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }
}

struct StickyArtistHeader: View {
    let name: String
    let onBack: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 7) {
                    Image(systemName: "chevron.left")
                    Text("library.title")
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.74))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("collection.back"))

            Text(verbatim: name)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .lineLimit(1)

            Spacer()

            Button(action: onPlay) {
                Image(systemName: "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.10), in: Circle())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().overlay(.white.opacity(0.10))
        }
    }
}

struct ArtistDetailBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.024, green: 0.026, blue: 0.034)

            RadialGradient(
                colors: [.purple.opacity(0.24), .indigo.opacity(0.07), .clear],
                center: .top,
                startRadius: 20,
                endRadius: 520
            )

            LinearGradient(
                colors: [.clear, .black.opacity(0.22), .black.opacity(0.48)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct ArtistPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
