import SwiftUI

struct MusicSearchTrackResults: View {
    @EnvironmentObject private var catalogTransfers: CatalogTransferManager
    @EnvironmentObject private var musicSearch: MusicSearchStore
    let results: [MusicSearchResult]
    let onPlay: (MusicSearchResult) -> Void

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SearchSectionTitle("search.tracks")
                ForEach(results, id: \.stableID) { result in
                    HStack(spacing: 10) {
                        Button { onPlay(result) } label: {
                            HStack(spacing: 12) {
                                TrackArtworkView(artworkURL: result.artworkURL, fallbackName: "MistyLake")
                                    .scaledToFill().frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 9))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(verbatim: result.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    HStack(spacing: 6) {
                                        Text(verbatim: result.artist ?? String(localized: "track.unknown_artist")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                        SourceBadge(provider: result.provider)
                                    }
                                    Text(verbatim: result.attribution).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                Text(verbatim: result.duration.trackDurationText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(result.playableTrack == nil)

                        if let localTrack = result.localTrack {
                            TrackActionsMenu(track: localTrack)
                        } else {
                            Menu {
                                Button(result.provider == "catalog" ? "downloads.make_offline" : "search.save_to_library") {
                                    if result.provider == "catalog" {
                                        Task { await catalogTransfers.download(remoteFileID: result.reference.externalID) }
                                    } else {
                                        Task { await musicSearch.acquire(result) }
                                    }
                                }
                                .disabled(result.provider == "catalog" ? false : !result.canAcquire)
                                if let webpage = result.webpageURL {
                                    Link("search.open_provider", destination: webpage)
                                }
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 32, height: 44)
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct SourceBadge: View {
    let provider: String
    var body: some View {
        Text(provider == "audius" ? "Audius" : provider == "piped" ? "Piped" : provider == "catalog" ? "ShizoMusic" : String(localized: "search.source_offline"))
            .font(.system(size: 9, weight: .bold)).textCase(.uppercase)
            .foregroundStyle(provider == "audius" ? Color.orange : provider == "piped" ? Color.red : Color.white.opacity(0.82))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background((provider == "audius" ? Color.orange : provider == "piped" ? Color.red : Color.white).opacity(0.14), in: Capsule())
    }
}

struct ProviderFailureBanner: View {
    let failure: MusicSourceFailure
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: failure.kind == .rateLimit ? "clock.badge.exclamationmark" : "wifi.exclamationmark")
            VStack(alignment: .leading, spacing: 2) {
                Text(failure.provider == "audius" ? "Audius" : failure.provider == "piped" ? "Piped" : failure.provider).font(.caption.bold())
                Text(messageKey).font(.caption2).foregroundStyle(.secondary)
                if failure.provider == "server", failure.message != "search.server_unavailable" {
                    Text(verbatim: failure.message).font(.caption2.monospaced()).foregroundStyle(.secondary).lineLimit(3)
                }
                if let retryAfter = failure.retryAfterSeconds, retryAfter > 0 {
                    Text("\(String(localized: "search.retry_after")) \(retryAfter)s")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("common.retry", action: retry).font(.caption.bold())
        }
        .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var messageKey: LocalizedStringKey {
        switch failure.kind {
        case .authentication: "search.provider_authentication"
        case .rateLimit: "search.provider_rate_limit"
        case .geoRestricted: "search.provider_geo_restricted"
        case .temporary: "search.provider_temporary"
        case .unavailable, .malformedResponse: "search.provider_unavailable"
        }
    }
}

struct ExternalEntityResults: View {
    let title: LocalizedStringKey
    let results: [MusicSearchResult]
    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SearchSectionTitle(title)
                ForEach(results, id: \.stableID) { result in
                    let row = HStack(spacing: 12) {
                        TrackArtworkView(artworkURL: result.artworkURL, fallbackName: result.entityType == .artist ? "ArtistHero" : "MistyLake")
                            .scaledToFill().frame(width: 54, height: 54)
                            .clipShape(result.entityType == .artist ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 10)))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: result.title).font(.headline).lineLimit(1)
                            HStack { if let artist = result.artist { Text(verbatim: artist).font(.caption).foregroundStyle(.secondary) }; SourceBadge(provider: result.provider) }
                            Text(verbatim: result.attribution).font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let webpage = result.webpageURL { Link(destination: webpage) { Image(systemName: "arrow.up.right.square") } }
                    }
                    if result.entityType == .artist {
                        NavigationLink(value: ArtistDetailDestination(
                            name: result.title,
                            provider: result.reference.provider,
                            externalID: result.reference.externalID
                        )) { row }
                        .buttonStyle(.plain)
                    } else { row }
                }
            }
        }
    }
}

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
