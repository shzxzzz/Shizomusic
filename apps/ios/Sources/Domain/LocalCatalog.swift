import Foundation

struct LocalArtist: Identifiable, Hashable, Sendable {
    let name: String
    let tracks: [PlayableTrack]

    var id: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
    var artworkURL: URL? { tracks.compactMap(\.artworkURL).first }
    var durationSeconds: Int { tracks.reduce(0) { $0 + $1.durationSeconds } }
}

struct LocalRelease: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let artist: String
    let tracks: [PlayableTrack]

    var artworkURL: URL? { tracks.compactMap(\.artworkURL).first }
    var durationSeconds: Int { tracks.reduce(0) { $0 + $1.durationSeconds } }
}

extension Collection where Element == PlayableTrack {
    var localArtists: [LocalArtist] {
        let pairs = flatMap { track in track.artistNames.map { ($0, track) } }
        return Dictionary(grouping: pairs, by: { $0.0.libraryNormalized })
            .map { group in
                LocalArtist(
                    name: group.value.first?.0 ?? group.key,
                    tracks: group.value.map(\.1).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                )
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var localReleases: [LocalRelease] {
        let withAlbums = filter { track in
            guard let album = track.albumTitle else { return false }
            return !album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return Dictionary(grouping: withAlbums) { track in
            track.releaseID ?? "legacy:\(track.albumTitle?.libraryNormalized ?? "")"
        }
        .compactMap { key, tracks -> LocalRelease? in
            guard let first = tracks.first, let title = first.albumTitle else { return nil }
            return LocalRelease(
                id: key,
                title: title,
                artist: first.albumArtist ?? first.artistNames.first ?? first.artist,
                tracks: tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }
        .sorted {
            let titleComparison = $0.title.localizedStandardCompare($1.title)
            return titleComparison == .orderedSame
                ? $0.artist.localizedStandardCompare($1.artist) == .orderedAscending
                : titleComparison == .orderedAscending
        }
    }
}

extension TimeInterval {
    var trackDurationText: String {
        let seconds = max(Int(self.rounded()), 0)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
