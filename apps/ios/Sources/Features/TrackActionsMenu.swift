import SwiftUI

struct TrackActionsMenu: View {
    @EnvironmentObject private var playback: PlaybackCoordinator
    @EnvironmentObject private var playlistStore: PlaylistStore
    @EnvironmentObject private var catalogTransfers: CatalogTransferManager
    @EnvironmentObject private var localLibrary: LocalMediaLibrary
    @State private var confirmsLocalRemoval = false
    @State private var remainingRemoteSources = 0

    let track: PlayableTrack
    var removeTitle: String? = nil
    var onRemove: () -> Void = {}

    var body: some View {
        Menu {
            Button("collection.play_next") { playback.playNext(track) }
            Button("collection.add_to_queue") { playback.addToQueue(track) }
            if let addedBy = track.addedByName {
                Text("\(String(localized: "catalog.added_by")) \(addedBy)")
            }
            if let url = track.fileURL, !url.isFileURL {
                Button("downloads.make_offline") { Task { await catalogTransfers.download(trackID: track.id) } }
            } else if track.fileURL?.isFileURL == true {
                Button("downloads.remove_local", role: .destructive) {
                    Task {
                        remainingRemoteSources = await catalogTransfers.remoteSourceCount(trackID: track.id)
                        confirmsLocalRemoval = true
                    }
                }
            }

            Menu("collection.add_to_playlist") {
                if playlistStore.playlists.isEmpty {
                    Text("library.playlists_empty_title")
                } else {
                    ForEach(playlistStore.playlists) { playlist in
                        Button {
                            Task { await playlistStore.add(track: track, to: playlist.id) }
                        } label: {
                            if playlist.items.contains(where: { $0.track.id == track.id }) {
                                Label(playlist.title, systemImage: "checkmark")
                            } else {
                                Text(verbatim: playlist.title)
                            }
                        }
                        .disabled(playlist.items.contains(where: { $0.track.id == track.id }))
                    }
                }
            }

            Divider()
            if track.artistNames.count > 1 {
                Menu("collection.go_to_artist") {
                    ForEach(track.artistNames, id: \.self) { artist in
                        NavigationLink(value: ArtistDetailDestination(name: artist)) {
                            Text(verbatim: artist)
                        }
                    }
                }
            } else if let artist = track.artistNames.first {
                NavigationLink(value: ArtistDetailDestination(name: artist)) {
                    Label("collection.go_to_artist", systemImage: "person")
                }
            }
            if let releaseID = track.releaseID, let albumTitle = track.albumTitle {
                NavigationLink(
                    value: CollectionDetailDestination.release(
                        id: releaseID,
                        title: albumTitle,
                        artist: track.albumArtist ?? track.artist
                    )
                ) {
                    Label("collection.go_to_release", systemImage: "square.stack")
                }
            }

            if let removeTitle {
                Divider()
                Button(LocalizedStringKey(removeTitle), role: .destructive, action: onRemove)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white.opacity(0.56))
                .frame(width: 32, height: 44)
        }
        .accessibilityLabel(Text("collection.more_actions"))
        .accessibilityValue(Text(verbatim: track.title))
        .confirmationDialog("downloads.remove_warning", isPresented: $confirmsLocalRemoval, titleVisibility: .visible) {
            Button("downloads.remove_local", role: .destructive) {
                Task {
                    _ = await catalogTransfers.deleteLocalCopy(trackID: track.id)
                    await localLibrary.load()
                }
            }
            Button("common.cancel", role: .cancel) {}
        } message: {
            if remainingRemoteSources > 0 {
                Text("downloads.remaining_sources_warning")
            } else {
                Text("downloads.no_remaining_source_warning")
            }
        }
    }
}
