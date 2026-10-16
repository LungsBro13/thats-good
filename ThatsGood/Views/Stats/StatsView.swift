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
                        strokesGainedSection(StrokesGained.summarize(data))
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

    private func strokesGainedSection(_ sg: SGSummary) -> some View {
        let rows: [(SGCategory, Double)] = SGCategory.allCases.compactMap { category in
            sg.perRound(category).map { (category, $0) }
        }
        let total = rows.reduce(0.0) { $0 + $1.1 }
        let scale = max(2.0, rows.map { abs($0.1) }.max() ?? 0)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Strokes gained per round")
                Spacer()
                if !rows.isEmpty {
                    Text(String(format: "%+.1f", total))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(total < 0 ? Color.tgLoss : Color.tgAccent)
                }
            }
            if rows.isEmpty {
                Text("Enter the first putt length, or play in Detailed mode, to see strokes gained.")
                    .font(.footnote)
                    .foregroundStyle(Color.tgMuted)
            } else {
                ForEach(rows.map { $0.0 }) { category in
                    SGBarRow(label: category.label, value: sg.perRound(category) ?? 0, scale: scale,
                             rounds: sg.roundsWithData[category] ?? 0)
                }
                Text("Compared with tour averages (approximate). Putting uses first putt length. Tee, approach and short game need Detailed mode.")
                    .font(.caption)
                    .foregroundStyle(Color.tgMuted)
            }
        }
    }

    private func keyNumbers(_ s: StatSummary) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
            StatTile(title: "Average score", value: formatDecimal(s.averageScore),
                     detail: s.averageToPar.map { String(format: "%+.1f to par", $0) })
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


/// A bar that grows left for strokes lost and right for strokes gained.
struct SGBarRow: View {
    let label: String
    let value: Double
    let scale: Double
    let rounds: Int

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.subheadline)
                Text("\(rounds) round\(rounds == 1 ? "" : "s")").font(.caption2).foregroundStyle(Color.tgMuted)
            }
            .frame(width: 96, alignment: .leading)
            GeometryReader { proxy in
                let half = proxy.size.width / 2
                let width = min(half, half * abs(value) / scale)
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.tgLine).frame(width: 1).offset(x: half)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(value < 0 ? Color.tgLoss : Color.tgAccent)
                        .frame(width: width, height: 14)
                        .offset(x: value < 0 ? half - width : half)
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 30)
            Text(String(format: "%+.1f", value))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(value < 0 ? Color.tgLoss : Color.tgAccent)
                .frame(width: 44, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(String(format: "%+.1f", value)) strokes per round")
    }
}
