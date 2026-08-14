# iOS client

Generate `ShizoMusic.xcodeproj` from `project.yml` through XcodeGen on macOS, then add GRDB 7.x through Swift Package Manager.

Initial logical boundaries are App, Domain, Database, Networking, Sync, Playback, MediaLibrary, Features and DesignSystem. Do not couple SwiftUI views to GRDB or URLSession.
