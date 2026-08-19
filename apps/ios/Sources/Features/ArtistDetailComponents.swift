import SwiftUI

// Shared artist UI now works directly with LocalArtist, LocalRelease and PlayableTrack.
struct ArtistTrackList: View {
    let tracks: [PlayableTrack]
    let onPlay: (PlayableTrack) -> Void
    var body: some View { SearchTrackResults(tracks: tracks, onPlay: onPlay) }
}
