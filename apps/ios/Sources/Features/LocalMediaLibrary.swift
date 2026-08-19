import AVFoundation
import CryptoKit
import Foundation

struct MediaLibraryProgress: Equatable, Sendable {
    enum Phase: String, Sendable { case scanning, importing }
    let phase: Phase
    let completed: Int
    let total: Int
    let filename: String?

    var fraction: Double {
        guard total > 0 else { return 0 }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

struct ImportReport: Identifiable, Equatable, Sendable {
    let id = UUID()
    let imported: [String]
    let duplicates: [String]
    let corrupted: [String]
    let unsupported: [String]
    let failed: [String]

    var requestedCount: Int {
        imported.count + duplicates.count + corrupted.count + unsupported.count + failed.count
    }
}

@MainActor
final class LocalMediaLibrary: ObservableObject {
    @Published private(set) var tracks: [PlayableTrack] = []
    @Published private(set) var progress: MediaLibraryProgress?
    @Published private(set) var lastImportReport: ImportReport?
    @Published private(set) var errorMessage: String?

    let musicDirectory: URL
    private let artworkDirectory: URL

    private nonisolated static let supportedExtensions = Set(["mp3", "flac", "m4a", "aac", "wav"])

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        musicDirectory = documents.appendingPathComponent("Music", isDirectory: true)
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        artworkDirectory = applicationSupport
            .appendingPathComponent("ShizoMusic", isDirectory: true)
            .appendingPathComponent("Artwork", isDirectory: true)
        try? fileManager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }

    var isBusy: Bool { progress != nil }
    var artists: [LocalArtist] { tracks.localArtists }
    var releases: [LocalRelease] { tracks.localReleases }

    var totalBytes: Int64 {
        tracks.reduce(into: Int64(0)) { result, track in
            guard let url = track.fileURL,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return }
            result += Int64(values.fileSize ?? 0)
        }
    }

    func searchTracks(query: String) -> [PlayableTrack] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return tracks }
        return tracks.filter {
            $0.title.localizedCaseInsensitiveContains(normalized)
                || $0.artist.localizedCaseInsensitiveContains(normalized)
                || ($0.albumTitle?.localizedCaseInsensitiveContains(normalized) ?? false)
        }
    }

    func scan() async {
        guard progress == nil else { return }
        await rescan(phase: .scanning)
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty, progress == nil else { return }
        errorMessage = nil
        lastImportReport = nil

        var imported: [String] = []
        var duplicates: [String] = []
        var corrupted: [String] = []
        var unsupported: [String] = []
        var failed: [String] = []
        let directory = musicDirectory

        let existingFiles = (try? await Task.detached(priority: .userInitiated) {
            try Self.audioFiles(in: directory)
        }.value) ?? []
        var knownHashes = Set<String>()
        for file in existingFiles {
            if let hash = try? await Task.detached(priority: .utility, operation: { try Self.sha256(file) }).value {
                knownHashes.insert(hash)
            }
        }

        for (index, source) in urls.enumerated() {
            let filename = source.lastPathComponent
            progress = MediaLibraryProgress(phase: .importing, completed: index, total: urls.count, filename: filename)
            let accessing = source.startAccessingSecurityScopedResource()

            if !Self.supportedExtensions.contains(source.pathExtension.lowercased()) {
                unsupported.append(filename)
                if accessing { source.stopAccessingSecurityScopedResource() }
                continue
            }

            do {
                let hash = try await Task.detached(priority: .userInitiated) { try Self.sha256(source) }.value
                guard knownHashes.insert(hash).inserted else {
                    duplicates.append(filename)
                    if accessing { source.stopAccessingSecurityScopedResource() }
                    continue
                }
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try await Self.validateAudio(at: source)
                    }.value
                } catch {
                    knownHashes.remove(hash)
                    corrupted.append(filename)
                    if accessing { source.stopAccessingSecurityScopedResource() }
                    continue
                }
                let destination = try await Task.detached(priority: .userInitiated) {
                    try Self.copyDestination(for: source, in: directory)
                }.value
                imported.append(destination.lastPathComponent)
            } catch {
                failed.append(filename)
            }
            if accessing { source.stopAccessingSecurityScopedResource() }
        }

        progress = MediaLibraryProgress(phase: .importing, completed: urls.count, total: urls.count, filename: nil)
        await rescan(phase: .scanning)
        lastImportReport = ImportReport(
            imported: imported,
            duplicates: duplicates,
            corrupted: corrupted,
            unsupported: unsupported,
            failed: failed
        )
    }

    func dismissImportReport() { lastImportReport = nil }

    func removeTrack(_ track: PlayableTrack) async {
        guard let url = track.fileURL else { return }
        let artworkURL = track.artworkURL
        do {
            try await Task.detached(priority: .userInitiated) {
                try FileManager.default.removeItem(at: url)
                if let artworkURL, FileManager.default.fileExists(atPath: artworkURL.path) {
                    try? FileManager.default.removeItem(at: artworkURL)
                }
            }.value
            await rescan(phase: .scanning)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rescan(phase: MediaLibraryProgress.Phase) async {
        let directory = musicDirectory
        let artworkDirectory = self.artworkDirectory
        do {
            let files = try await Task.detached(priority: .userInitiated) {
                try Self.regularFiles(in: directory)
            }.value
            let urls = files.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            let unsupported = files
                .filter { !Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
                .map(\.lastPathComponent)
            var scanned: [PlayableTrack] = []
            var identifiers = Set<String>()
            var duplicates: [String] = []
            var corrupted: [String] = []
            for (index, url) in urls.enumerated() {
                progress = MediaLibraryProgress(phase: phase, completed: index, total: urls.count, filename: url.lastPathComponent)
                do {
                    let track = try await Task.detached(priority: .userInitiated) {
                        try await Self.track(at: url, artworkDirectory: artworkDirectory)
                    }.value
                    if identifiers.insert(track.id).inserted {
                        scanned.append(track)
                    } else {
                        duplicates.append(url.lastPathComponent)
                    }
                } catch {
                    corrupted.append(url.lastPathComponent)
                }
            }
            tracks = scanned.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if phase == .scanning,
               (!duplicates.isEmpty || !corrupted.isEmpty || !unsupported.isEmpty) {
                lastImportReport = ImportReport(
                    imported: [],
                    duplicates: duplicates,
                    corrupted: corrupted,
                    unsupported: unsupported,
                    failed: []
                )
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        progress = nil
    }

    private nonisolated static func track(at url: URL, artworkDirectory: URL) async throws -> PlayableTrack {
        let asset = AVURLAsset(url: url)
        try await validateAudio(asset)
        let duration = try await asset.load(.duration)
        let metadata = try await asset.load(.commonMetadata)
        let identifier = try sha256(url)
        let title = await metadataValue(.commonIdentifierTitle, in: metadata) ?? url.deletingPathExtension().lastPathComponent
        let artist = await metadataValue(.commonIdentifierArtist, in: metadata) ?? String(localized: "library.unknown_artist")
        let albumTitle = await metadataValue(.commonIdentifierAlbumName, in: metadata)
        let seconds = duration.seconds.isFinite ? max(Int(duration.seconds.rounded()), 0) : 0
        let artworkURL = await cachedArtwork(identifier: identifier, metadata: metadata, directory: artworkDirectory)
        return PlayableTrack(
            id: identifier,
            title: title,
            artist: artist,
            albumTitle: albumTitle,
            durationSeconds: seconds,
            artworkName: "MistyLake",
            artworkURL: artworkURL,
            fileURL: url
        )
    }

    private nonisolated static func validateAudio(at url: URL) async throws {
        try await validateAudio(AVURLAsset(url: url))
    }

    private nonisolated static func validateAudio(_ asset: AVURLAsset) async throws {
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        guard playable, duration.isValid, duration.seconds.isFinite, duration.seconds > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    private nonisolated static func copyDestination(for source: URL, in directory: URL) throws -> URL {
        let manager = FileManager.default
        let preferredName = source.deletingPathExtension().lastPathComponent
        let safeBase = safeFilename(preferredName.isEmpty ? "Track" : preferredName)
        let ext = source.pathExtension.lowercased()
        var destination = directory.appendingPathComponent("\(safeBase).\(ext)")
        var suffix = 2
        while manager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(safeBase) \(suffix).\(ext)")
            suffix += 1
        }
        try manager.copyItem(at: source, to: destination)
        return destination
    }

    private nonisolated static func audioFiles(in directory: URL) throws -> [URL] {
        try regularFiles(in: directory).filter {
            supportedExtensions.contains($0.pathExtension.lowercased())
        }
    }

    private nonisolated static func regularFiles(in directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isHidden != true else { return nil }
            return url
        }
    }

    private nonisolated static func metadataValue(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private nonisolated static func cachedArtwork(identifier: String, metadata: [AVMetadataItem], directory: URL) async -> URL? {
        let destination = directory.appendingPathComponent("\(identifier).image")
        if FileManager.default.fileExists(atPath: destination.path) { return destination }
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
              let data = try? await item.load(.dataValue), !data.isEmpty else { return nil }
        do {
            try data.write(to: destination, options: .atomic)
            return destination
        } catch { return nil }
    }

    private nonisolated static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "-")
    }
}
