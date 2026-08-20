import AVFoundation
import CryptoKit
import Foundation
import UIKit

struct MediaLibraryProgress: Equatable, Sendable {
    enum Phase: String, Sendable { case scanning, importing }
    let phase: Phase
    let completed: Int
    let total: Int
    let filename: String?
    var fraction: Double { total > 0 ? min(max(Double(completed) / Double(total), 0), 1) : 0 }
}

struct ImportReport: Identifiable, Equatable, Sendable {
    let id = UUID()
    let imported: [String]
    let duplicates: [String]
    let corrupted: [String]
    let unsupported: [String]
    let failed: [String]
    var requestedCount: Int { imported.count + duplicates.count + corrupted.count + unsupported.count + failed.count }
}

@MainActor
final class LocalMediaLibrary: ObservableObject {
    @Published private(set) var tracks: [PlayableTrack] = []
    @Published private(set) var artists: [LocalArtist] = []
    @Published private(set) var releases: [LocalRelease] = []
    @Published private(set) var searchResults: [PlayableTrack] = []
    @Published private(set) var progress: MediaLibraryProgress?
    @Published private(set) var lastImportReport: ImportReport?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = false
    @Published var sort: LibraryTrackSort = .title
    @Published var availabilityFilter: LibraryAvailabilityFilter = .available

    let musicDirectory: URL
    private let artworkDirectory: URL
    private let repository: any TrackRepository
    private nonisolated static let supportedExtensions = Set(["mp3", "flac", "m4a", "aac", "wav"])

    init(fileManager: FileManager = .default, repository: (any TrackRepository)? = nil) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        musicDirectory = documents.appendingPathComponent("Music", isDirectory: true)
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        artworkDirectory = applicationSupport.appendingPathComponent("ShizoMusic/Artwork", isDirectory: true)
        self.repository = repository ?? GRDBTrackRepository()
        try? fileManager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
    }

    var isBusy: Bool { progress != nil || isLoading }
    var totalBytes: Int64 {
        tracks.reduce(into: 0) { result, track in
            guard let url = track.fileURL, let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return }
            result += Int64(size)
        }
    }

    func load() async { await reloadFromDatabase() }

    func scan() async {
        guard progress == nil else { return }
        await reloadFromDatabase()
        await rescan(phase: .scanning)
    }

    func apply(sort: LibraryTrackSort, filter: LibraryAvailabilityFilter) async {
        self.sort = sort
        availabilityFilter = filter
        await reloadFromDatabase()
    }

    func search(query: String) async {
        do {
            searchResults = try await repository.search(query: query)
            errorMessage = nil
        } catch {
            searchResults = []
            errorMessage = error.localizedDescription
        }
    }

    func searchTracks(query: String) -> [PlayableTrack] {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? tracks : searchResults
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

        let existingFilesTask = Task.detached(
            priority: .userInitiated,
            operation: { try Self.audioFiles(in: directory) }
        )
        let existingFiles = (try? await existingFilesTask.value) ?? []
        var knownHashes = Set<String>()
        for file in existingFiles {
            let hashTask = Task.detached(priority: .utility, operation: { try Self.sha256(file) })
            if let hash = try? await hashTask.value { knownHashes.insert(hash) }
        }

        for (index, source) in urls.enumerated() {
            let filename = source.lastPathComponent
            progress = .init(phase: .importing, completed: index, total: urls.count, filename: filename)
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }
            guard Self.supportedExtensions.contains(source.pathExtension.lowercased()) else {
                unsupported.append(filename)
                continue
            }
            do {
                let hash = try await Task.detached(
                    priority: .userInitiated,
                    operation: { try Self.sha256(source) }
                ).value
                guard knownHashes.insert(hash).inserted else { duplicates.append(filename); continue }
                do {
                    try await Task.detached(
                        priority: .userInitiated,
                        operation: { try await Self.validateAudio(at: source) }
                    ).value
                }
                catch { knownHashes.remove(hash); corrupted.append(filename); continue }
                let destination = try await Task.detached(
                    priority: .userInitiated,
                    operation: { try Self.copyDestination(for: source, in: directory) }
                ).value
                imported.append(destination.lastPathComponent)
            } catch { failed.append(filename) }
        }
        progress = .init(phase: .importing, completed: urls.count, total: urls.count, filename: nil)
        await rescan(phase: .scanning)
        lastImportReport = .init(imported: imported, duplicates: duplicates, corrupted: corrupted, unsupported: unsupported, failed: failed)
    }

    func dismissImportReport() { lastImportReport = nil }

    func removeTrack(_ track: PlayableTrack) async {
        do {
            _ = try await repository.deleteLocalSource(trackID: track.id)
            await rescan(phase: .scanning)
        } catch { errorMessage = error.localizedDescription }
    }

    private func reloadFromDatabase() async {
        isLoading = tracks.isEmpty
        defer { isLoading = false }
        do {
            let snapshot = try await repository.snapshot(sort: sort, filter: availabilityFilter)
            tracks = snapshot.tracks
            artists = snapshot.artists
            releases = snapshot.releases
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    private func rescan(phase: MediaLibraryProgress.Phase) async {
        let directory = musicDirectory
        let artworkDirectory = self.artworkDirectory
        do {
            let files = try await Task.detached(
                priority: .userInitiated,
                operation: { try Self.regularFiles(in: directory) }
            ).value
            let supported = files.filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }
            let unsupported = files.filter { !Self.supportedExtensions.contains($0.pathExtension.lowercased()) }.map(\.lastPathComponent)
            var scanned: [ScannedMediaFile] = []
            var seenHashes = Set<String>()
            var duplicates: [String] = []
            var corrupted: [String] = []
            for (index, url) in supported.enumerated() {
                progress = .init(phase: phase, completed: index, total: supported.count, filename: url.lastPathComponent)
                do {
                    let media = try await Task.detached(
                        priority: .userInitiated,
                        operation: { try await Self.mediaFile(at: url, artworkDirectory: artworkDirectory) }
                    ).value
                    if !seenHashes.insert(media.contentHash).inserted { duplicates.append(url.lastPathComponent) }
                    scanned.append(media)
                } catch { corrupted.append(url.lastPathComponent) }
            }
            progress = .init(phase: phase, completed: supported.count, total: supported.count, filename: nil)
            try await repository.synchronize(files: scanned, scanID: UUID())
            await reloadFromDatabase()
            if phase == .scanning, (!duplicates.isEmpty || !corrupted.isEmpty || !unsupported.isEmpty) {
                lastImportReport = .init(imported: [], duplicates: duplicates, corrupted: corrupted, unsupported: unsupported, failed: [])
            }
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
        progress = nil
    }

    private nonisolated static func mediaFile(at url: URL, artworkDirectory: URL) async throws -> ScannedMediaFile {
        let asset = AVURLAsset(url: url)
        try await validateAudio(asset)
        let duration = try await asset.load(.duration)
        let commonMetadata = try await asset.load(.commonMetadata)
        var allMetadata = commonMetadata
        for format in try await asset.load(.availableMetadataFormats) {
            if let metadata = try? await asset.loadMetadata(for: format) { allMetadata.append(contentsOf: metadata) }
        }
        let hash = try sha256(url)
        let title = await metadataValue(.commonIdentifierTitle, in: allMetadata) ?? url.deletingPathExtension().lastPathComponent
        let artist = await metadataValue(.commonIdentifierArtist, in: allMetadata) ?? String(localized: "library.unknown_artist")
        let album = await metadataValue(.commonIdentifierAlbumName, in: allMetadata)
        let albumArtist = await metadataValue(.iTunesMetadataAlbumArtist, in: allMetadata)
        let artwork = await cachedArtwork(metadata: allMetadata, directory: artworkDirectory)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return ScannedMediaFile(
            fileURL: url,
            contentHash: hash,
            fileSize: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast,
            format: url.pathExtension.lowercased(),
            title: title,
            artistDisplayName: artist,
            artistNames: splitArtistCredits(artist),
            albumTitle: album,
            albumArtist: albumArtist,
            duration: duration.seconds.isFinite ? max(duration.seconds, 0) : 0,
            artworkURL: artwork?.url,
            artworkHash: artwork?.hash
        )
    }

    private nonisolated static func validateAudio(at url: URL) async throws { try await validateAudio(AVURLAsset(url: url)) }
    private nonisolated static func validateAudio(_ asset: AVURLAsset) async throws {
        let playable = try await asset.load(.isPlayable)
        let duration = try await asset.load(.duration)
        guard playable, duration.isValid, duration.seconds.isFinite, duration.seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
    }

    private nonisolated static func metadataValue(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private nonisolated static func cachedArtwork(metadata: [AVMetadataItem], directory: URL) async -> (url: URL, hash: String)? {
        let candidates: [AVMetadataIdentifier] = [.commonIdentifierArtwork, .iTunesMetadataCoverArt]
        for identifier in candidates {
            guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
                  let data = try? await item.load(.dataValue), !data.isEmpty else { continue }
            let hash = sha256(data)
            let destination = directory.appendingPathComponent("\(hash).image")
            guard UIImage(data: data) != nil else { continue }
            if UIImage(contentsOfFile: destination.path) == nil {
                do { try data.write(to: destination, options: .atomic) }
                catch { continue }
            }
            guard UIImage(contentsOfFile: destination.path) != nil else { continue }
            return (destination, hash)
        }
        return nil
    }

    private nonisolated static func splitArtistCredits(_ value: String) -> [String] {
        let pattern = #"(?i)\s+(?:feat\.?|ft\.?|featuring|x)\s+|\s+&\s+|\s*;\s*"#
        let separated = value.replacingOccurrences(
            of: pattern,
            with: "\u{1f}",
            options: .regularExpression
        )
        let result = separated
            .components(separatedBy: "\u{1f}")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return result.isEmpty ? [value] : result
    }

    private nonisolated static func copyDestination(for source: URL, in directory: URL) throws -> URL {
        let manager = FileManager.default
        let base = safeFilename(source.deletingPathExtension().lastPathComponent.isEmpty ? "Track" : source.deletingPathExtension().lastPathComponent)
        let ext = source.pathExtension.lowercased()
        var destination = directory.appendingPathComponent("\(base).\(ext)")
        var suffix = 2
        while manager.fileExists(atPath: destination.path) { destination = directory.appendingPathComponent("\(base) \(suffix).\(ext)"); suffix += 1 }
        try manager.copyItem(at: source, to: destination)
        return destination
    }

    private nonisolated static func audioFiles(in directory: URL) throws -> [URL] { try regularFiles(in: directory).filter { supportedExtensions.contains($0.pathExtension.lowercased()) } }
    private nonisolated static func regularFiles(in directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL, let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true, values.isHidden != true else { return nil }
            return url
        }
    }

    private nonisolated static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private nonisolated static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private nonisolated static func safeFilename(_ value: String) -> String {
        value.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined(separator: "-")
    }
}
