import Foundation

enum PlaylistCoverStyle: String, CaseIterable, Codable, Hashable, Sendable {
    case violet, mistyLake, sunset, silver, midnight, auroraShore
}

struct PlaylistItem: Identifiable, Hashable, Sendable {
    let id: UUID
    let playlistID: UUID
    let track: PlayableTrack
    let rank: Double
    let createdAt: Date
}

struct Playlist: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var coverStyle: PlaylistCoverStyle
    var items: [PlaylistItem]
    let createdAt: Date
    var updatedAt: Date

    var tracks: [PlayableTrack] { items.map(\.track) }
}

protocol PlaylistRepository: Sendable {
    func fetchAll() async throws -> [Playlist]
    func create(title: String, coverStyle: PlaylistCoverStyle) async throws -> UUID
    func rename(id: UUID, title: String) async throws
    func delete(id: UUID) async throws
    func changeCover(id: UUID, coverStyle: PlaylistCoverStyle) async throws
    func add(trackID: String, to playlistID: UUID) async throws -> UUID
    func remove(itemID: UUID) async throws
    func move(itemID: UUID, to destinationIndex: Int) async throws
}
