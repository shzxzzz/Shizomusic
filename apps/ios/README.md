# iOS client

Generate `ShizoMusic.xcodeproj` from `project.yml` through XcodeGen on macOS, then add GRDB 7.x through Swift Package Manager.

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

`PlaybackCoordinator` is the single owner of `AVPlayer`, the persisted queue and
playback state. It handles seeking, previous/next history, shuffle, repeat-one/all,
background audio, interruptions, headphone removal and Control Center commands.

The device regression checklist is in
[`PHYSICAL_DEVICE_TEST_PLAN.md`](PHYSICAL_DEVICE_TEST_PLAN.md).
