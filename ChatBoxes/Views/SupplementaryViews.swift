import AppKit
import MapKit
import SwiftUI

struct ThinkingDetailSheet: View {
    let message: ChatMessage

    @State private var showAllResults = false

    private var headerTitle: String {
        if message.searchInProgress == true { return "正在思考" }
        return reasoningDurationTitle(seconds: message.reasoningDurationSec)
    }

    private var searchResults: [WebSearchResultItem] {
        message.searchResults ?? []
    }

    private var visibleResults: [WebSearchResultItem] {
        showAllResults ? searchResults : Array(searchResults.prefix(6))
    }

    private var remainingResultCount: Int {
        max(0, searchResults.count - 6)
    }

    private var hasSearchStep: Bool {
        message.searchInProgress == true
            || !searchResults.isEmpty
            || !(message.searchQuery ?? "").isEmpty
            || !(message.searchSummary ?? "").isEmpty
    }

    private var isFinished: Bool {
        message.generating != true && message.searchInProgress != true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(headerTitle)
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 0) {
                if hasSearchStep {
                    searchTimelineStep
                }

                ForEach(Array(reasoningSteps.enumerated()), id: \.offset) { index, step in
                    reasoningTimelineStep(step, showLineBelow: index < reasoningSteps.count - 1 || isFinished)
                }

                if isFinished {
                    completionTimelineStep
                }
            }
        }
        .padding(16)
        .frame(width: 380, alignment: .leading)
    }

    @ViewBuilder
    private var searchTimelineStep: some View {
        HStack(alignment: .top, spacing: 12) {
            ThinkingTimelineRail(showLineBelow: !reasoningSteps.isEmpty || isFinished) {
                WebSearchGlobeIcon()
                    .frame(width: 13, height: 13)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(searchStepTitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if let query = message.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
                    ThinkingQueryChip(text: query)
                }

                if message.searchInProgress == true {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在检索…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                if !visibleResults.isEmpty {
                    ThinkingResultChipGrid(results: visibleResults)

                    if !showAllResults, remainingResultCount > 0 {
                        Button {
                            withAnimation(.chatBoxQuick) {
                                showAllResults = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("再显示 \(remainingResultCount) 个")
                                    .font(.system(size: 12))
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.bottom, 14)
        }
    }

    @ViewBuilder
    private func reasoningTimelineStep(_ text: String, showLineBelow: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ThinkingTimelineRail(showLineBelow: showLineBelow) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
            }

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)
                .padding(.top, 4)
        }
    }

    private var completionTimelineStep: some View {
        HStack(alignment: .top, spacing: 12) {
            ThinkingTimelineRail(showLineBelow: false, tint: .secondary) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 13))
            }

            Text("完成")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.top, 1)
        }
    }

    private var searchStepTitle: String {
        let query = message.searchQuery?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !query.isEmpty {
            return "搜索 \(query)"
        }
        return "搜索网页"
    }

    private var reasoningSteps: [String] {
        (message.reasoningContent ?? "")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct ThinkingTimelineRail<Icon: View>: View {
    let showLineBelow: Bool
    var tint: Color = .secondary
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(spacing: 0) {
            icon()
                .foregroundStyle(tint)
                .frame(width: 20, height: 20)

            if showLineBelow {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 4)
            }
        }
        .frame(width: 20)
    }
}

private struct ThinkingQueryChip: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
            Text(text)
                .lineLimit(2)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

private struct ThinkingResultChipGrid: View {
    let results: [WebSearchResultItem]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(results) { result in
                Button {
                    if let url = URL(string: result.url) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 5) {
                        ThinkingSiteIcon(url: result.url)
                        Text(thinkingDomain(from: result.url))
                            .lineLimit(1)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct ThinkingSiteIcon: View {
    let url: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.08))
                .frame(width: 14, height: 14)
            Text(thinkingDomain(from: url).prefix(1).uppercased())
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
        }
    }
}

private func thinkingDomain(from urlString: String) -> String {
    guard let host = URL(string: urlString)?.host else { return urlString }
    return host.replacingOccurrences(of: "www.", with: "")
}

struct PlaceDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let mapCard: MapCardPayload
    let detailText: String

    @State private var showDirections = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(mapCard.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(16)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(latitude: mapCard.latitude, longitude: mapCard.longitude),
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    ))) {
                        Marker(mapCard.title, coordinate: CLLocationCoordinate2D(latitude: mapCard.latitude, longitude: mapCard.longitude))
                    }
                    .frame(height: 160)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)

                    HStack(spacing: 8) {
                        Button("Apple 地图") {
                            MapNavigation.openAppleMaps(title: mapCard.title, latitude: mapCard.latitude, longitude: mapCard.longitude)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                        Button(MapNavigation.canOpenGoogleMapsApp ? "Google 地图 App" : "Google 地图") {
                            MapNavigation.openGoogleMapsApp(title: mapCard.title, latitude: mapCard.latitude, longitude: mapCard.longitude)
                        }
                        .controlSize(.small)

                        Button("Google 网页") {
                            MapNavigation.openGoogleMapsWeb(latitude: mapCard.latitude, longitude: mapCard.longitude)
                        }
                        .controlSize(.small)

                        if let website = mapCard.website, !website.isEmpty {
                            Button("网站") { openURL(website) }
                                .controlSize(.small)
                        }
                    }

                    if let address = mapCard.address { metaRow("mappin", address) }
                    if let hours = mapCard.openingHours { metaRow("clock", hours) }
                    if let phone = mapCard.phone { metaRow("phone", phone) }
                    metaRow("location", mapCard.coordinateText)

                    if !detailText.isEmpty {
                        MarkdownHTMLBlock(text: detailText, baseFontSize: AppLayout.bodySize, expandToWidth: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 480, height: 600)
    }

    private func metaRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 16)
            Text(text).font(.system(size: AppLayout.bodySize))
        }
    }

    private func openURL(_ value: String) {
        let candidate = value.hasPrefix("http") ? value : "https://\(value)"
        if let url = URL(string: candidate) { NSWorkspace.shared.open(url) }
    }
}

struct WeatherDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let weatherCard: WeatherCardPayload
    let detailText: String

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(weatherCard.location)
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(16)

            Divider()

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    WeatherCardView(card: weatherCard, detailText: "")
                    if !detailText.isEmpty {
                        MarkdownHTMLBlock(text: detailText, baseFontSize: AppLayout.bodySize, expandToWidth: true)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 440, height: 520)
    }
}
