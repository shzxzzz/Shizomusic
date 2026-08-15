import SwiftUI

enum SearchCategory: String, CaseIterable, Hashable, Sendable {
    case all
    case tracks
    case artists
    case releases
    case playlists

    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "search.category_all"
        case .tracks: "search.category_tracks"
        case .artists: "search.category_artists"
        case .releases: "search.category_releases"
        case .playlists: "search.category_playlists"
        }
    }
}

enum SearchPreviewScenario: Hashable, Sendable {
    case idle
    case results
    case loading
    case providerError
    case empty
    case offlineEmpty
}

@MainActor
final class MockSearchViewModel: ObservableObject {
    @Published var query: String
    @Published var selectedCategory: SearchCategory = .all
    @Published private(set) var scenario: SearchPreviewScenario
    @Published private(set) var recentQueries = ["Skrillex", "ambient focus", "In Rainbows"]

    init(scenario: SearchPreviewScenario = .idle) {
        self.scenario = scenario
        self.query = scenario == .idle ? "" : "Skrillex"
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func queryDidChange() {
        if hasQuery {
            if scenario == .idle || scenario == .empty || scenario == .offlineEmpty {
                scenario = .results
            }
        } else {
            scenario = .idle
            selectedCategory = .all
        }
    }

    func submitSearch() {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        recentQueries.removeAll { $0.localizedCaseInsensitiveCompare(normalized) == .orderedSame }
        recentQueries.insert(normalized, at: 0)
        scenario = .results
    }

    func useRecent(_ value: String) {
        query = value
        scenario = .results
        selectedCategory = .all
    }

    func clearQuery() {
        query = ""
        queryDidChange()
    }

    func clearRecent() {
        recentQueries.removeAll()
    }
}

struct SearchScreen: View {
    @EnvironmentObject private var playback: MockPlaybackState
    @StateObject private var viewModel: MockSearchViewModel

    init(scenario: SearchPreviewScenario = .idle) {
        _viewModel = StateObject(wrappedValue: MockSearchViewModel(scenario: scenario))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                SearchBackground()

                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Text("search.title")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                            .padding(.bottom, 14)

                        Section {
                            content
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                                .padding(.bottom, 34)
                        } header: {
                            SearchPinnedHeader(viewModel: viewModel)
                        }
                    }
                }
            }
            .navigationDestination(for: CollectionDetailDestination.self) { destination in
                CollectionDetailScreen(destination: destination)
            }
            .navigationDestination(for: ArtistDetailDestination.self) { destination in
                ArtistDetailScreen(destination: destination)
            }
            .navigationDestination(for: ArtistSectionDestination.self) { destination in
                ArtistSectionListScreen(destination: destination)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var content: some View {
        if !viewModel.hasQuery {
            SearchRecentSection(
                queries: viewModel.recentQueries,
                onSelect: viewModel.useRecent,
                onClear: viewModel.clearRecent
            )
        } else {
            switch viewModel.scenario {
            case .idle, .results, .loading, .providerError:
                resultsContent
            case .empty:
                SearchEmptyState(isOffline: false)
            case .offlineEmpty:
                SearchEmptyState(isOffline: true)
            }
        }
    }

    private var resultsContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            if viewModel.scenario == .providerError {
                SearchStatusBanner(kind: .providerError)
            }

            categoryContent

            if viewModel.scenario == .loading {
                SearchStatusBanner(kind: .loading)
            }
        }
    }

    @ViewBuilder
    private var categoryContent: some View {
        switch viewModel.selectedCategory {
        case .all:
            SearchAllResults(onPlayTrack: playTrack)
        case .tracks:
            SearchTracksResults(onPlayTrack: playTrack)
        case .artists:
            SearchArtistsResults()
        case .releases:
            SearchReleasesResults()
        case .playlists:
            SearchPlaylistsResults()
        }
    }

    private func playTrack(_ track: SearchTrackPreview) {
        playback.play(track.playableTrack)
    }
}

private struct SearchPinnedHeader: View {
    @ObservedObject var viewModel: MockSearchViewModel

    var body: some View {
        VStack(spacing: 12) {
            SearchField(
                query: $viewModel.query,
                onQueryChanged: viewModel.queryDidChange,
                onSubmit: viewModel.submitSearch,
                onClear: viewModel.clearQuery
            )

            if viewModel.hasQuery {
                SearchCategoryBar(selection: $viewModel.selectedCategory)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider().overlay(.white.opacity(0.08))
        }
    }
}

private struct SearchRecentSection: View {
    let queries: [String]
    let onSelect: (String) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("search.recent")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                Spacer()
                if !queries.isEmpty {
                    Button("search.clear", action: onClear)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.52))
                }
            }

            ForEach(queries, id: \.self) { query in
                Button { onSelect(query) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.white.opacity(0.42))
                        Text(verbatim: query)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                        Spacer()
                        Image(systemName: "arrow.up.left")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .foregroundStyle(.white)
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SearchBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.028, blue: 0.038)
            RadialGradient(colors: [.purple.opacity(0.20), .clear], center: .topLeading, startRadius: 10, endRadius: 500)
            RadialGradient(colors: [.cyan.opacity(0.07), .clear], center: .bottomTrailing, startRadius: 10, endRadius: 440)
        }
        .ignoresSafeArea()
    }
}

#Preview("Search idle") {
    SearchScreen(scenario: .idle).environmentObject(MockPlaybackState())
}

#Preview("Search results") {
    SearchScreen(scenario: .results).environmentObject(MockPlaybackState())
}

#Preview("Search loading") {
    SearchScreen(scenario: .loading).environmentObject(MockPlaybackState())
}

#Preview("Search provider error") {
    SearchScreen(scenario: .providerError).environmentObject(MockPlaybackState())
}

#Preview("Search empty") {
    SearchScreen(scenario: .empty).environmentObject(MockPlaybackState())
}

#Preview("Search offline empty") {
    SearchScreen(scenario: .offlineEmpty).environmentObject(MockPlaybackState())
}
