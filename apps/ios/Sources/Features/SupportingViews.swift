import SwiftUI

struct SearchView: View {
    @State private var query = ""

    var body: some View {
        NavigationStack {
            ZStack {
                ShizoPalette.background.ignoresSafeArea()

                ContentUnavailableView(
                    "search.empty_title",
                    systemImage: "waveform.badge.magnifyingglass",
                    description: Text("search.empty_subtitle")
                )
                .foregroundStyle(.white)
            }
            .navigationTitle("search.title")
            .searchable(text: $query, prompt: Text("search.prompt"))
        }
    }
}

struct PlaceholderTabView: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let systemImage: String

    var body: some View {
        NavigationStack {
            ZStack {
                ShizoPalette.background.ignoresSafeArea()

                ContentUnavailableView(
                    title,
                    systemImage: systemImage,
                    description: Text(subtitle)
                )
                .foregroundStyle(.white)
            }
            .navigationTitle(title)
        }
    }
}

enum ArtworkStyle: Sendable {
    case hero
    case violet
    case sunset
    case ocean

    var colors: [Color] {
        switch self {
        case .hero:
            [Color(red: 0.10, green: 0.08, blue: 0.22), Color(red: 0.95, green: 0.21, blue: 0.18)]
        case .violet:
            [Color(red: 0.15, green: 0.08, blue: 0.28), Color(red: 0.55, green: 0.22, blue: 0.95)]
        case .sunset:
            [Color(red: 0.98, green: 0.54, blue: 0.18), Color(red: 0.88, green: 0.12, blue: 0.34)]
        case .ocean:
            [Color(red: 0.03, green: 0.22, blue: 0.31), Color(red: 0.05, green: 0.68, blue: 0.76)]
        }
    }

    var symbol: String {
        switch self {
        case .hero: "waveform.path"
        case .violet: "sparkles"
        case .sunset: "sun.horizon.fill"
        case .ocean: "water.waves"
        }
    }
}

struct ArtworkView: View {
    let style: ArtworkStyle

    var body: some View {
        ZStack {
            LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)

            Circle()
                .fill(.white.opacity(0.10))
                .frame(width: 96, height: 96)
                .offset(x: 38, y: -35)

            Circle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
                .frame(width: 72, height: 72)

            Image(systemName: style.symbol)
                .font(.system(size: 31, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.13), lineWidth: 1)
        }
    }
}

enum ShizoPalette {
    static let background = Color(red: 0.035, green: 0.035, blue: 0.052)
    static let backgroundElevated = Color(red: 0.055, green: 0.055, blue: 0.075)
    static let surface = Color.white.opacity(0.065)
    static let stroke = Color.white.opacity(0.075)
    static let strokeStrong = Color.white.opacity(0.13)
    static let accent = Color(red: 1.0, green: 0.29, blue: 0.20)
    static let accentDeep = Color(red: 0.55, green: 0.08, blue: 0.13)
    static let success = Color(red: 0.31, green: 0.86, blue: 0.52)
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.39)
    static let ink = Color(red: 0.055, green: 0.045, blue: 0.06)
}
