import Foundation

struct Track: Identifiable, Hashable, Sendable {
    let id: UUID
    var title: String
    var albumTitle: String?
    var duration: TimeInterval
    var sourceState: SourceState

    enum SourceState: String, Sendable {
        case local, pendingSync, synced, retryableFailure
    }
}

protocol TrackRepository: Sendable {
    func tracks() async throws -> [Track]
    func search(query: String) async throws -> [Track]
}
