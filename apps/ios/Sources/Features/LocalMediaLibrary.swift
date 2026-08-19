import AVFoundation
import CryptoKit
import Foundation

@MainActor
final class LocalMediaLibrary: ObservableObject {
    @Published private(set) var tracks: [PlayableTrack] = []
    @Published private(set) var isScanning = false
    @Published private(set) var errorMessage: String?

    let musicDirectory: URL

    private nonisolated static let supportedExtensions = Set(["mp3", "flac", "m4a", "aac", "wav"])

    init(fileManager: FileManager = .default) {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        musicDirectory = documents.appendingPathComponent("Music", isDirectory: true)
        try? fileManager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
    }

    var totalBytes: Int64 {
        tracks.reduce(into: Int64(0)) { result, track in
            guard let url = track.fileURL,
                  let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return }
            result += Int64(values.fileSize ?? 0)
        }
    }

    func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }

        let directory = musicDirectory
        do {
            tracks = try await Task.detached(priority: .userInitiated) {
                try await Self.scanDirectory(directory)
            }.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func importFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        isScanning = true
        defer { isScanning = false }
        let directory = musicDirectory

        do {
            try await Task.detached(priority: .userInitiated) {
                let manager = FileManager.default
                let existingFiles = try Self.audioFiles(in: directory)
                var existingHashes = Set(try existingFiles.map(Self.sha256))

                for source in urls {
                    let accessing = source.startAccessingSecurityScopedResource()
                    defer { if accessing { source.stopAccessingSecurityScopedResource() } }

                    guard Self.supportedExtensions.contains(source.pathExtension.lowercased()) else { continue }
                    let hash = try Self.sha256(source)
                    guard existingHashes.insert(hash).inserted else { continue }

                    let preferredName = source.deletingPathExtension().lastPathComponent
                    let safeBase = Self.safeFilename(preferredName.isEmpty ? "Track" : preferredName)
                    let ext = source.pathExtension.lowercased()
                    var destination = directory.appendingPathComponent("\(safeBase).\(ext)")
                    var suffix = 2
                    while manager.fileExists(atPath: destination.path) {
                        destination = directory.appendingPathComponent("\(safeBase) \(suffix).\(ext)")
                        suffix += 1
                    }
                    try manager.copyItem(at: source, to: destination)
                }
            }.value
            tracks = try await Task.detached(priority: .userInitiated) {
                try await Self.scanDirectory(directory)
            }.value
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private nonisolated static func scanDirectory(_ directory: URL) async throws -> [PlayableTrack] {
        let urls = try audioFiles(in: directory)
        var result: [PlayableTrack] = []
        result.reserveCapacity(urls.count)

        for url in urls {
            do {
                let asset = AVURLAsset(url: url)
                guard asset.isPlayable else { continue }
                let duration = try await asset.load(.duration)
                let metadata = try await asset.load(.commonMetadata)
                let title = await metadataValue(.commonIdentifierTitle, in: metadata)
                    ?? url.deletingPathExtension().lastPathComponent
                let artist = await metadataValue(.commonIdentifierArtist, in: metadata)
                    ?? String(localized: "library.unknown_artist")
                let seconds = duration.seconds.isFinite ? max(Int(duration.seconds.rounded()), 0) : 0
                result.append(
                    PlayableTrack(
                        id: try sha256(url),
                        title: title,
                        artist: artist,
                        durationSeconds: seconds,
                        artworkName: "MistyLake",
                        fileURL: url
                    )
                )
            } catch {
                // A corrupt or unsupported file stays in Files but is not offered for playback.
                continue
            }
        }

        return result.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private nonisolated static func audioFiles(in directory: URL) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        return enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  supportedExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  values.isHidden != true else { return nil }
            return url
        }
    }

    private nonisolated static func metadataValue(
        _ identifier: AVMetadataIdentifier,
        in metadata: [AVMetadataItem]
    ) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue) else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty ? nil : normalized
    }

    private nonisolated static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return value.components(separatedBy: invalid).joined(separator: "-")
    }
}
