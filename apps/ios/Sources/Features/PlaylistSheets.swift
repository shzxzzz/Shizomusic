import PhotosUI
import SwiftUI

struct PlaylistTrackPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlistStore: PlaylistStore
    let playlist: Playlist
    let tracks: [PlayableTrack]

    private var existingTrackIDs: Set<String> {
        let current = playlistStore.playlists.first { $0.id == playlist.id } ?? playlist
        return Set(current.items.map(\.track.id))
    }

    var body: some View {
        NavigationStack {
            List(tracks) { track in
                HStack(spacing: 12) {
                    TrackArtworkView(artworkURL: track.artworkURL, fallbackName: track.artworkName)
                        .scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading) {
                        Text(verbatim: track.title).lineLimit(1)
                        Text(verbatim: track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button {
                        Task { await playlistStore.add(track: track, to: playlist.id) }
                    } label: {
                        Image(systemName: existingTrackIDs.contains(track.id) ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                    .disabled(existingTrackIDs.contains(track.id))
                    .accessibilityLabel(Text("collection.add_to_playlist"))
                }
            }
            .navigationTitle("collection.add_tracks")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("queue.done") { dismiss() } }
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct PlaylistCoverPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playlistStore: PlaylistStore
    let playlist: Playlist
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var importError: String?

    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        Label("playlist.cover_upload", systemImage: "photo.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(PlaylistCoverStyle.allCases, id: \.self) { style in
                            Button {
                                Task {
                                    await playlistStore.changeCover(id: playlist.id, coverStyle: style)
                                    dismiss()
                                }
                            } label: {
                                LibraryArtwork(style: style)
                                    .aspectRatio(1, contentMode: .fit)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                playlist.customCoverURL == nil && style == playlist.coverStyle ? .white : .white.opacity(0.12),
                                                lineWidth: playlist.customCoverURL == nil && style == playlist.coverStyle ? 3 : 1
                                            )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let importError {
                        Text(verbatim: importError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .navigationTitle("collection.change_cover")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("playlist_create.cancel") { dismiss() } } }
            .onChange(of: selectedPhoto) {
                guard let selectedPhoto else { return }
                Task {
                    do {
                        guard let data = try await selectedPhoto.loadTransferable(type: Data.self), !data.isEmpty else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        await playlistStore.setCustomCover(id: playlist.id, imageData: data)
                        dismiss()
                    } catch {
                        importError = error.localizedDescription
                    }
                }
            }
        }
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
    }
}

struct PlaylistResultsList: View {
    let playlists: [Playlist]

    var body: some View {
        if !playlists.isEmpty {
            LazyVStack(spacing: 10) {
                ForEach(playlists) { playlist in
                    NavigationLink(value: CollectionDetailDestination.playlist(id: playlist.id)) {
                        HStack(spacing: 12) {
                            LibraryArtwork(style: playlist.coverStyle, customCoverURL: playlist.customCoverURL)
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 11))
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: playlist.title).font(.headline).lineLimit(1)
                                Text("\(playlist.items.count) \(String(localized: "collection.tracks_unit"))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
