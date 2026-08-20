import SwiftUI

struct StatisticsScreen: View {
    @EnvironmentObject private var statistics: StatisticsStore

    var body: some View {
        NavigationStack {
            ZStack {
                StatisticsBackground()
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        Text("statistics.title")
                            .font(.largeTitle.bold())

                        Picker("statistics.period", selection: $statistics.period) {
                            ForEach(StatisticsPeriod.allCases) { period in
                                Text(LocalizedStringKey(period.localizationKey)).tag(period)
                            }
                        }
                        .pickerStyle(.segmented)

                        if statistics.isLoading {
                            ProgressView("statistics.loading").frame(maxWidth: .infinity).padding(.vertical, 50)
                        } else if let error = statistics.errorMessage {
                            ContentUnavailableView("statistics.error", systemImage: "exclamationmark.triangle", description: Text(verbatim: error))
                        } else if statistics.snapshot.history.isEmpty {
                            ContentUnavailableView(
                                "statistics.empty_title",
                                systemImage: "chart.bar.xaxis",
                                description: Text("statistics.empty_detail")
                            )
                            .frame(maxWidth: .infinity).padding(.vertical, 44)
                        } else {
                            summary
                            aggregateSection
                            rankSection("statistics.top_tracks", values: statistics.snapshot.topTracks)
                            rankSection("statistics.top_artists", values: statistics.snapshot.topArtists)
                            rankSection("statistics.top_releases", values: statistics.snapshot.topReleases)
                            history
                        }
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 18)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity)
                }
                .refreshable { await statistics.load() }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task { await statistics.load() }
        .onChange(of: statistics.period) { Task { await statistics.load() } }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("statistics.listening_time").font(.headline)
            Text(duration(statistics.snapshot.totalListeningSeconds))
                .font(.system(size: 42, weight: .bold, design: .rounded))
            HStack(spacing: 10) {
                metric(value: statistics.snapshot.qualifiedPlays, key: "statistics.qualified")
                metric(value: statistics.snapshot.completedPlays, key: "statistics.completed")
                metric(value: statistics.snapshot.skippedPlays, key: "statistics.skipped")
            }
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24))
    }

    private func metric(value: Int, key: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: "\(value)").font(.title3.bold()).monospacedDigit()
            Text(key).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var aggregateSection: some View {
        let values = statistics.period == .all ? statistics.snapshot.monthly : statistics.snapshot.daily
        if !values.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(LocalizedStringKey(statistics.period == .all ? "statistics.by_month" : "statistics.by_day"))
                    .font(.title3.bold())
                let maximum = max(values.map(\.listenedSeconds).max() ?? 1, 1)
                ForEach(values.prefix(14)) { value in
                    HStack(spacing: 10) {
                        Text(verbatim: value.label).font(.caption.monospacedDigit()).frame(width: 78, alignment: .leading)
                        GeometryReader { geometry in
                            Capsule().fill(.white.opacity(0.08))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(Color.purple.gradient)
                                        .frame(width: geometry.size.width * value.listenedSeconds / maximum)
                                }
                        }
                        .frame(height: 8)
                        Text(duration(value.listenedSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func rankSection(_ title: LocalizedStringKey, values: [ListeningRank]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            ForEach(Array(values.prefix(10).enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 12) {
                    Text(verbatim: "\(index + 1)").font(.caption.bold().monospacedDigit()).frame(width: 18)
                    TrackArtworkView(artworkURL: item.artworkURL, fallbackName: "MistyLake")
                        .scaledToFill().frame(width: 46, height: 46).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: item.title).font(.subheadline.bold()).lineLimit(1)
                        if let subtitle = item.subtitle, !subtitle.isEmpty {
                            Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    Spacer()
                    Text(duration(item.listenedSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("statistics.history").font(.title3.bold())
            ForEach(statistics.snapshot.history) { item in
                HStack(spacing: 12) {
                    TrackArtworkView(artworkURL: item.track.artworkURL, fallbackName: item.track.artworkName)
                        .scaledToFill().frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 9))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: item.track.title).font(.subheadline.bold()).lineLimit(1)
                        Text(item.endedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: item.completed ? "checkmark.circle.fill" : "forward.end.fill")
                        .foregroundStyle(item.completed ? .green : .secondary)
                    Text(duration(item.listenedSeconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func duration(_ seconds: Double) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = seconds >= 3_600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: max(seconds, 0)) ?? "0m"
    }
}

private struct StatisticsBackground: View {
    var body: some View {
        ZStack {
            Color(red: 0.025, green: 0.027, blue: 0.038)
            RadialGradient(colors: [.purple.opacity(0.23), .clear], center: .topTrailing, startRadius: 8, endRadius: 520)
            RadialGradient(colors: [.cyan.opacity(0.08), .clear], center: .bottomLeading, startRadius: 10, endRadius: 420)
        }
        .ignoresSafeArea()
    }
}
