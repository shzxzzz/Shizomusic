# iOS client

Generate `ShizoMusic.xcodeproj` from `project.yml` through XcodeGen on macOS. GRDB 7.8.0 is pinned and linked by the project specification.

Initial logical boundaries are App, Domain, Database, Networking, Sync, Playback, MediaLibrary, Features and DesignSystem. Do not couple SwiftUI views to GRDB or URLSession.

## Local playback

The application creates `Documents/Music` on first launch and exposes Documents in
the iOS Files app. Put MP3, FLAC, M4A, AAC or WAV files into **On My iPhone →
ShizoMusic → Music**, then return to the application. The directory is rescanned
whenever the app becomes active. Files can also be copied into the same managed
directory with **Library → Offline → Add track**.

After changing `project.yml`, regenerate the project with `xcodegen generate`.
The generated `Sources/App/Info.plist` contains the required `audio` background
mode and Files sharing keys; opening an older generated `.xcodeproj` won’t pick up
those capabilities.

`PlaybackCoordinator` is the single owner of `AVPlayer`; its queue, history and source context are persisted in SQLite through GRDB. The domain media library stores logical tracks separately from physical `TrackSource` files, so moved or rediscovered files retain their track identity.
It handles seeking, previous/next history, shuffle, repeat-one/all,
background audio, interruptions, headphone removal and Control Center commands.

Player backgrounds extract several colors from the current embedded artwork and blend them as animated radial gradients. Playlists and their custom uploaded covers are persisted locally. A track can occur only once in a playlist; every item owns a stable UUID and a fractional rank, so local reordering does not rewrite the whole list during normal use.

Listening sessions are recorded as local events for start, pause, seek, skip, interruption, qualified play and completion. The Statistics tab builds daily/monthly totals, history and top tracks, artists and releases from SQLite.

The authorization flow accepts one-time invitations, stores refresh tokens in Keychain and supports device/user revocation. Selecting local-only mode keeps the complete media workflow available without a server or internet connection.

Playlist mutations and their `SyncOperation` outbox records are committed in one SQLite transaction. `SyncEngine` pushes idempotent UUID operations in batches, pulls an Int64 cursor change log, applies tombstones, retries with exponential backoff and jitter, and preserves conflict diagnostics. Playlist cards expose local/pending/synced/failed state; the compact banner offers manual retry.

The device regression checklist is in
[`PHYSICAL_DEVICE_TEST_PLAN.md`](PHYSICAL_DEVICE_TEST_PLAN.md).

## Shared catalog and transfers

After an authenticated scan, local sources are persisted as upload transfers and sent in resumable parts by a background `URLSession`. The server catalog is merged into the same logical `Track` records by content hash, while remote and downloaded files remain separate `TrackSource` rows. Playback chooses local, then downloaded, then remote streaming sources.

Open the transfer manager from Library to inspect upload/download progress and use pause, resume, cancel, retry, or clear downloaded copies. Removing an offline copy keeps the logical track when a server source is available.
