import Foundation

enum ListeningEventKind: String, Codable, CaseIterable, Sendable {
    case started
    case resumed
    case paused
    case seek
    case skip
    case interruption
    case qualified
    case completed
    case stopped
}

struct ListeningEventDraft: Sendable {
    let id: UUID
    let sessionID: UUID
    let trackID: String
    let kind: ListeningEventKind
    let occurredAt: Date
    let position: Double
    let fromPosition: Double?
    let toPosition: Double?
    let listenedSeconds: Double
    let context: QueueSourceContext

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        trackID: String,
        kind: ListeningEventKind,
        occurredAt: Date = Date(),
        position: Double,
        fromPosition: Double? = nil,
        toPosition: Double? = nil,
        listenedSeconds: Double = 0,
        context: QueueSourceContext
    ) {
        self.id = id
        self.sessionID = sessionID
        self.trackID = trackID
        self.kind = kind
        self.occurredAt = occurredAt
        self.position = position
        self.fromPosition = fromPosition
        self.toPosition = toPosition
        self.listenedSeconds = listenedSeconds
        self.context = context
    }
}

enum StatisticsPeriod: String, CaseIterable, Identifiable, Sendable {
    case day
    case month
    case all

    var id: Self { self }
    var localizationKey: String { "statistics.period_\(rawValue)" }

    func startDate(now: Date = Date(), calendar: Calendar = .current) -> Date {
        switch self {
        case .day:
            return calendar.startOfDay(for: now)
        case .month:
            return calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? .distantPast
        case .all:
            return .distantPast
        }
    }
}

struct ListeningRank: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String?
    let artworkURL: URL?
    let listenedSeconds: Double
    let qualifiedPlays: Int
}

struct ListeningHistoryItem: Identifiable, Sendable {
    let id: UUID
    let track: PlayableTrack
    let startedAt: Date
    let endedAt: Date
    let listenedSeconds: Double
    let completed: Bool
}

struct ListeningAggregate: Identifiable, Sendable {
    let id: String
    let label: String
    let listenedSeconds: Double
    let qualifiedPlays: Int
    let completedPlays: Int
}

struct ListeningStatisticsSnapshot: Sendable {
    let totalListeningSeconds: Double
    let qualifiedPlays: Int
    let completedPlays: Int
    let skippedPlays: Int
    let topTracks: [ListeningRank]
    let topArtists: [ListeningRank]
    let topReleases: [ListeningRank]
    let history: [ListeningHistoryItem]
    let daily: [ListeningAggregate]
    let monthly: [ListeningAggregate]

    static let empty = ListeningStatisticsSnapshot(
        totalListeningSeconds: 0,
        qualifiedPlays: 0,
        completedPlays: 0,
        skippedPlays: 0,
        topTracks: [],
        topArtists: [],
        topReleases: [],
        history: [],
        daily: [],
        monthly: []
    )
}

protocol ListeningStatisticsRepository: Sendable {
    func record(_ event: ListeningEventDraft) async throws
    func snapshot(period: StatisticsPeriod) async throws -> ListeningStatisticsSnapshot
}
