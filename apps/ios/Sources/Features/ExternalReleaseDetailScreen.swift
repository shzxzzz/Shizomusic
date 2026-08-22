import SwiftUI

struct ExternalReleaseDestination: Hashable, Sendable {
    let provider: String
    let externalID: String
    let title: String
    let artist: String
    let artworkURL: URL?
}

struct ExternalReleaseDetailScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    @EnvironmentObject private var musicSearch: MusicSearchStore
    let destination: ExternalReleaseDestination
    @State private var detail: ExternalReleaseDetail?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            ArtistDetailBackground()
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
                    Button { dismiss() } label: { Label("collection.back", systemImage: "chevron.left") }.buttonStyle(.plain)
                    HStack(alignment: .bottom, spacing: 18) {
                        TrackArtworkView(artworkURL: detail?.release.artworkURL ?? destination.artworkURL, fallbackName: "MistyLake")
                            .scaledToFill().frame(width: 150, height: 150).clipShape(RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: detail?.release.title ?? destination.title).font(.largeTitle.bold()).lineLimit(3)
                            Text(verbatim: detail?.release.artist ?? destination.artist).foregroundStyle(.secondary)
                            if let metadata { Text(verbatim: metadata).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let detail, !playableTracks(detail.tracks).isEmpty {
                        HStack {
                            Button { play(detail.tracks, startingAt: 0) } label: { Label("collection.play", systemImage: "play.fill") }
                            Button { shuffle(detail.tracks) } label: { Label("collection.shuffle", systemImage: "shuffle") }
                        }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
                    }
                    if isLoading { ProgressView("search.searching_more") }
                    else if detail != nil {
                        SearchSectionTitle("search.tracks")
                        ForEach(releaseDiscs) { disc in
                            if releaseDiscs.count > 1 {
                                Text("\(String(localized: "release.disc")) \(disc.id)").font(.headline).foregroundStyle(.secondary)
                            }
                            MusicSearchTrackResults(results: disc.tracks, onPlay: playOne, showsSectionTitle: false, showsTrackNumber: true)
                        }
                    }
                    else if let errorMessage {
                        ContentUnavailableView("library.error_title", systemImage: "exclamationmark.triangle", description: Text(verbatim: errorMessage))
                    }
                }
                .frame(maxWidth: 620, alignment: .leading).padding(16).padding(.bottom, 50).frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
        .task(id: destination) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .catalogLibraryDidChange)) { _ in
            Task { await load() }
        }
    }

    private var metadata: String? {
        guard let release = detail?.release else { return nil }
        let type = release.releaseType?.rawValue.capitalized ?? "Release"
        let year = release.releaseDate?.prefix(4).description
        let count = release.trackCount.map(String.init)
        return [type, year, count.map { "\($0) \(String(localized: "collection.tracks_unit"))" }].compactMap { $0 }.joined(separator: " · ")
    }
    private var releaseDiscs: [ReleaseDisc] {
        let grouped = Dictionary(grouping: detail?.tracks ?? []) { $0.discNumber ?? 1 }
        return grouped.keys.sorted().map { disc in
            ReleaseDisc(id: disc, tracks: grouped[disc, default: []].sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) })
        }
    }
    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { detail = try await musicSearch.externalRelease(provider: destination.provider, externalID: destination.externalID); errorMessage = nil }
        catch { errorMessage = error.localizedDescription }
    }
    private func playOne(_ result: MusicSearchResult) {
        guard let tracks = detail?.tracks, let index = tracks.firstIndex(where: { $0.stableID == result.stableID }) else { return }
        play(tracks, startingAt: index)
    }
    private func play(_ results: [MusicSearchResult], startingAt index: Int) {
        let playable = playableTracks(results)
        guard let selected = results.indices.contains(index) ? resolvedTrack(results[index]) : nil,
              let playableIndex = playable.firstIndex(of: selected) else { return }
        playback.play(playable, startingAt: playableIndex, context: .release(destination.externalID))
    }
    private func playableTracks(_ results: [MusicSearchResult]) -> [PlayableTrack] { results.compactMap(resolvedTrack) }
    private func shuffle(_ results: [MusicSearchResult]) {
        let tracks = playableTracks(results).shuffled()
        guard !tracks.isEmpty else { return }
        playback.play(tracks, context: .release(destination.externalID))
    }
    private func resolvedTrack(_ result: MusicSearchResult) -> PlayableTrack? {
        if let local = localLibrary.tracks.first(where: { local in
            local.title.libraryNormalized == result.title.libraryNormalized
                && local.artist.libraryNormalized == (result.artist ?? "").libraryNormalized
                && (result.duration == 0 || abs(Double(local.durationSeconds) - result.duration) <= 3)
        }) { return local }
        return result.playableTrack
    }
}

private struct ReleaseDisc: Identifiable {
    let id: Int
    let tracks: [MusicSearchResult]
}
