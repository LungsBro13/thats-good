import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Query(filter: #Predicate<Round> { $0.isComplete }, sort: \Round.playedOn, order: .reverse)
    private var rounds: [Round]
    @Query private var imported: [ImportedScore]

    var body: some View {
        let data = rounds.map(\.data)
        let history = Handicap.history(data, imported: imported.map(\.data))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("THAT'S GOOD")
                        .font(.caption.weight(.bold))
                        .tracking(2)

                    handicapSection(history: history, eligible: Handicap.eligibleRoundCount(data) + imported.count)

                    Button("Start a round") { selectedTab = .play }
                        .buttonStyle(PrimaryButtonStyle())

                    if let last = rounds.first {
                        lastRoundSection(last)
                    }

                    if rounds.count > 1 {
                        recentSection
                    }
                }
                .padding(20)
            }
            .background(Color.tgBackground)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func handicapSection(history: [IndexPoint], eligible: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Handicap index (estimate)")
            HStack(alignment: .bottom) {
                if let current = history.last {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(formatDecimal(current.index))
                            .font(.system(size: 64, weight: .semibold))
                            .monospacedDigit()
                        if history.count >= 2 {
                            let change = current.index - history[history.count - 2].index
                            Text(change == 0 ? "No change since last round"
                                 : "\(change < 0 ? "−" : "+")\(formatDecimal(abs(change))) since last round")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(change <= 0 ? Color.tgAccent : Color.tgLoss)
                        }
                        if !imported.isEmpty {
                            Text("Includes \(imported.count) imported score\(imported.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Color.tgMuted)
                        }
                    }
                } else {
                    Text("Play \(max(1, 3 - eligible)) more 18-hole round\(3 - eligible == 1 ? "" : "s") to get your handicap estimate.")
                        .font(.body)
                        .foregroundStyle(Color.tgMuted)
                }
                Spacer()
                if history.count >= 2 {
                    Chart(history) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Index", point.index))
                            .foregroundStyle(Color.tgAccent)
                            .interpolationMethod(.monotone)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 130, height: 56)
                    .accessibilityLabel("Handicap trend")
                }
            }
            .padding(.bottom, 20)
            Hairline()
        }
    }

    private func lastRoundSection(_ round: Round) -> some View {
        let stats = RoundStats.summarize([round.data])
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Last round · \(round.playedOn.formatted(date: .abbreviated, time: .omitted))")
            NavigationLink {
                RoundSummaryView(round: round)
            } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(round.totalStrokes)")
                        .font(.system(size: 40, weight: .semibold))
                        .monospacedDigit()
                    Text(formatToPar(round.toPar))
                        .font(.headline)
                        .foregroundStyle(scoreColor(round.toPar))
                    Spacer()
                    Text(round.courseName)
                        .font(.subheadline)
                        .foregroundStyle(Color.tgMuted)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Color.tgMuted)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 0) {
                StatTile(title: "Fairways", value: "\(stats.fairwayHits)/\(stats.fairwayAttempts)")
                StatTile(title: "Greens", value: "\(stats.greenHits)/\(stats.greenAttempts)")
                StatTile(title: "Putts", value: "\(stats.totalPutts)")
            }
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Recent rounds")
                .padding(.bottom, 6)
            ForEach(Array(rounds.prefix(6))) { round in
                NavigationLink {
                    RoundSummaryView(round: round)
                } label: {
                    RoundRow(round: round)
                }
                .buttonStyle(.plain)
                Hairline()
            }
        }
    }
}

struct RoundRow: View {
    let round: Round

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(round.courseName).font(.body.weight(.semibold)).lineLimit(1)
                Text(round.playedOn.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(Color.tgMuted)
            }
            Spacer()
            Text("\(round.totalStrokes)")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(formatToPar(round.toPar))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(scoreColor(round.toPar))
                .frame(width: 36, alignment: .trailing)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
