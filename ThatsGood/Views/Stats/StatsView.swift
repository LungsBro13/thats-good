import SwiftUI
import SwiftData
import Charts

enum RoundFilter: String, CaseIterable, Identifiable {
    case last5, last10, last20, all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last5: return "Last 5"
        case .last10: return "Last 10"
        case .last20: return "Last 20"
        case .all: return "All"
        }
    }

    var limit: Int? {
        switch self {
        case .last5: return 5
        case .last10: return 10
        case .last20: return 20
        case .all: return nil
        }
    }
}

private struct TrendPoint: Identifiable {
    let id: Int
    let date: Date
    let toPar: Int
}

private struct BarItem: Identifiable {
    let label: String
    let value: Double
    var id: String { label }
}

struct StatsView: View {
    @Query(filter: #Predicate<Round> { $0.isComplete }, sort: \Round.playedOn, order: .reverse)
    private var rounds: [Round]
    @State private var filter: RoundFilter = .last10

    var body: some View {
        let chosen = filter.limit.map { Array(rounds.prefix($0)) } ?? rounds
        let data = chosen.map(\.data).filter { !$0.holes.isEmpty }
        let summary = RoundStats.summarize(data)

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SegmentedPicker(options: RoundFilter.allCases, selection: $filter) { $0.label }

                    if data.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No rounds yet").font(.headline)
                            Text("Finish a round to see your stats here. To try it out, load demo rounds in the Bag tab.")
                                .font(.subheadline)
                                .foregroundStyle(Color.tgMuted)
                        }
                    } else {
                        trendSection(data, summary: summary)
                        keyNumbers(summary)
                        byParSection(summary)
                        mixSection(summary)
                        missSection(summary)
                    }
                }
                .padding(20)
            }
            .background(Color.tgBackground)
            .navigationTitle("Stats")
        }
    }

    // MARK: Sections

    private func trendSection(_ data: [RoundData], summary: StatSummary) -> some View {
        let points = data.sorted { $0.date < $1.date }.enumerated().map {
            TrendPoint(id: $0.offset, date: $0.element.date, toPar: $0.element.toPar)
        }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Score to par")
                Spacer()
                if let average = summary.averageScore {
                    Text("Average \(formatDecimal(average))")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Chart {
                RuleMark(y: .value("Par", 0))
                    .foregroundStyle(Color.tgLine)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                ForEach(points) { point in
                    LineMark(x: .value("Round", point.id), y: .value("To par", point.toPar))
                        .foregroundStyle(Color.tgData)
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Round", point.id), y: .value("To par", point.toPar))
                        .foregroundStyle(Color.tgData)
                        .symbolSize(24)
                }
            }
            .chartXAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 160)
            .accessibilityLabel("Score to par for each round, oldest to newest")
        }
    }

    private func keyNumbers(_ s: StatSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
            StatTile(title: "Average score", value: formatDecimal(s.averageScore),
                     detail: s.averageToPar.map { "\(formatDecimal($0)) to par" })
            StatTile(title: "Putts per round", value: formatDecimal(s.puttsPerRound))
            StatTile(title: "Fairways hit", value: formatPercent(s.fairwayPct),
                     detail: "Left \(formatPercent(s.fairwayLeftPct)) · Right \(formatPercent(s.fairwayRightPct))")
            StatTile(title: "Greens in regulation", value: formatPercent(s.girPct))
            StatTile(title: "Up and down", value: formatPercent(s.upAndDownPct),
                     detail: "\(s.upAndDownMade) of \(s.upAndDownAttempts)")
            StatTile(title: "3-putt holes", value: formatPercent(s.threePuttPct),
                     detail: "1-putts \(formatPercent(s.onePuttPct))")
            StatTile(title: "Penalties per round", value: formatDecimal(s.penaltiesPerRound))
            StatTile(title: "Rounds", value: "\(s.roundCount)")
        }
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func byParSection(_ s: StatSummary) -> some View {
        let items = [3, 4, 5].compactMap { par in
            s.averageToParByPar[par].map { BarItem(label: "Par \(par)", value: $0) }
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Average to par by hole type")
            Chart(items) { item in
                BarMark(x: .value("Hole type", item.label), y: .value("To par", item.value))
                    .foregroundStyle(item.value > 0 ? Color.tgLoss : Color.tgAccent)
                    .annotation(position: .top) {
                        Text(String(format: "%+.2f", item.value))
                            .font(.caption.weight(.semibold))
                    }
            }
            .chartYScale(domain: .automatic(includesZero: true))
            .frame(height: 150)
        }
    }

    private func mixSection(_ s: StatSummary) -> some View {
        let items = [
            BarItem(label: "Birdie or better", value: s.mixPerRound.birdiesOrBetter),
            BarItem(label: "Par", value: s.mixPerRound.pars),
            BarItem(label: "Bogey", value: s.mixPerRound.bogeys),
            BarItem(label: "Double or worse", value: s.mixPerRound.doublesOrWorse),
        ]
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Scores per round")
            Chart(items) { item in
                BarMark(x: .value("Per round", item.value), y: .value("Score", item.label))
                    .foregroundStyle(item.label == "Birdie or better" || item.label == "Par" ? Color.tgAccent : Color.tgLoss)
                    .annotation(position: .trailing) {
                        Text(formatDecimal(item.value)).font(.caption.weight(.semibold))
                    }
            }
            .chartXAxis(.hidden)
            .frame(height: 150)
        }
    }

    private func missSection(_ s: StatSummary) -> some View {
        let items = [GreenResult.short, .long, .left, .right].map {
            BarItem(label: $0.label, value: s.greenMissShare($0) ?? 0)
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Where you miss greens")
            Chart(items) { item in
                BarMark(x: .value("Share", item.value), y: .value("Miss", item.label))
                    .foregroundStyle(Color.tgData)
                    .annotation(position: .trailing) {
                        Text(formatPercent(item.value)).font(.caption.weight(.semibold))
                    }
            }
            .chartXAxis(.hidden)
            .chartXScale(domain: 0...1)
            .frame(height: 140)
        }
    }
}
