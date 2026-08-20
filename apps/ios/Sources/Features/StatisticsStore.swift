import Foundation

@MainActor
final class StatisticsStore: ObservableObject {
    @Published private(set) var snapshot = ListeningStatisticsSnapshot.empty
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published var period: StatisticsPeriod = .month

    private let repository: any ListeningStatisticsRepository

    init(repository: any ListeningStatisticsRepository = GRDBListeningStatisticsRepository()) {
        self.repository = repository
    }

    func load() async {
        isLoading = snapshot.history.isEmpty
        defer { isLoading = false }
        do {
            snapshot = try await repository.snapshot(period: period)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
