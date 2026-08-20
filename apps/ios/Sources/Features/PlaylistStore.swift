import Foundation
import UIKit

@MainActor
final class PlaylistStore: ObservableObject {
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let repository: any PlaylistRepository

    init(repository: any PlaylistRepository = GRDBPlaylistRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = playlists.isEmpty
        defer { isLoading = false }
        do {
            playlists = try await repository.fetchAll()
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }

    @discardableResult
    func create(title: String, coverStyle: PlaylistCoverStyle) async -> UUID? {
        await mutate { try await self.repository.create(title: title, coverStyle: coverStyle) }
    }

    func rename(id: UUID, title: String) async { _ = await mutate { try await self.repository.rename(id: id, title: title) } }
    func delete(id: UUID) async { _ = await mutate { try await self.repository.delete(id: id) } }
    func changeCover(id: UUID, coverStyle: PlaylistCoverStyle) async { _ = await mutate { try await self.repository.changeCover(id: id, coverStyle: coverStyle) } }
    func setCustomCover(id: UUID, imageData: Data) async {
        do {
            let fileURL = try await Task.detached(priority: .userInitiated) {
                guard let source = UIImage(data: imageData) else { throw CocoaError(.fileReadCorruptFile) }
                let maximum: CGFloat = 768
                let ratio = min(1, maximum / max(source.size.width, source.size.height))
                let size = CGSize(width: max(source.size.width * ratio, 1), height: max(source.size.height * ratio, 1))
                let renderer = UIGraphicsImageRenderer(size: size)
                let rendered = renderer.image { _ in source.draw(in: CGRect(origin: .zero, size: size)) }
                guard let normalizedData = rendered.jpegData(compressionQuality: 0.76) else { throw CocoaError(.fileWriteUnknown) }
                let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                    .appendingPathComponent("ShizoMusic/PlaylistArtwork", isDirectory: true)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let url = root.appendingPathComponent("\(id.uuidString).image")
                try normalizedData.write(to: url, options: .atomic)
                return url
            }.value
            _ = await mutate { try await self.repository.setCustomCover(id: id, fileURL: fileURL) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    func add(track: PlayableTrack, to playlistID: UUID) async { _ = await mutate { try await self.repository.add(trackID: track.id, to: playlistID) } }
    func remove(itemID: UUID) async { _ = await mutate { try await self.repository.remove(itemID: itemID) } }
    func move(itemID: UUID, to destinationIndex: Int) async { _ = await mutate { try await self.repository.move(itemID: itemID, to: destinationIndex) } }

    private func mutate<Result>(_ operation: () async throws -> Result) async -> Result? {
        do {
            let result = try await operation()
            playlists = try await repository.fetchAll()
            errorMessage = nil
            return result
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }
}
