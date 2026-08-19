import Foundation
import Testing

@testable import ShizoMusic

struct LocalCatalogTests {
    @Test
    func groupsTracksByArtistAndReleaseMetadata() {
        let tracks = [
            track(id: "2", title: "Beta", artist: "Artist", album: "Album"),
            track(id: "1", title: "Alpha", artist: "Artist", album: "Album"),
            track(id: "3", title: "Single", artist: "Other", album: nil)
        ]

        #expect(tracks.localArtists.count == 2)
        #expect(tracks.localArtists.first { $0.name == "Artist" }?.tracks.map(\.title) == ["Alpha", "Beta"])
        #expect(tracks.localReleases.count == 1)
        #expect(tracks.localReleases[0].title == "Album")
        #expect(tracks.localReleases[0].tracks.map(\.id) == ["1", "2"])
    }

    private func track(id: String, title: String, artist: String, album: String?) -> PlayableTrack {
        PlayableTrack(id: id, title: title, artist: artist, albumTitle: album, durationSeconds: 60, artworkName: "MistyLake")
    }
}
