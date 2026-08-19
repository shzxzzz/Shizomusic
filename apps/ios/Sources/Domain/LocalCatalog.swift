import Foundation

struct LocalArtist: Identifiable, Hashable, Sendable {
    let name: String
    let tracks: [PlayableTrack]

    var id: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
    var artworkURL: URL? { tracks.compactMap(\.artworkURL).first }
    var durationSeconds: Int { tracks.reduce(0) { $0 + $1.durationSeconds } }
}

struct LocalRelease: Identifiable, Hashable, Sendable {
    let title: String
    let artist: String
    let tracks: [PlayableTrack]

    var id: String { "\(artist)\u{1f}\(title)" }
    var artworkURL: URL? { tracks.compactMap(\.artworkURL).first }
    var durationSeconds: Int { tracks.reduce(0) { $0 + $1.durationSeconds } }
}

extension Collection where Element == PlayableTrack {
    var localArtists: [LocalArtist] {
        Dictionary(grouping: self, by: \.artist)
            .map { group in
                LocalArtist(
                    name: group.key,
                    tracks: group.value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
            "\(track.artist)\u{1f}\(track.albumTitle ?? "")"
        }
        .compactMap { key, tracks -> LocalRelease? in
            let parts = key.components(separatedBy: "\u{1f}")
            guard parts.count == 2 else { return nil }
            return LocalRelease(
                title: parts[1],
                artist: parts[0],
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
