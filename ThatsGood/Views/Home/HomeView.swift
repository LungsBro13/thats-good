import SwiftUI
import SwiftData
import Charts

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Query(filter: #Predicate<Round> { $0.isComplete }, sort: \Round.playedOn, order: .reverse)
    private var rounds: [Round]
    @Query private var imported: [ImportedScore]
    @State private var wrappedRound: Round?

    var body: some View {
        let data = rounds.map(\.data)
        let history = Handicap.history(data, imported: imported.map(\.data))
        let plan = PracticePlan.build(Array(data.prefix(10)))

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        Golfer(style: .dark, height: 30)
                        Wordmark(size: 22)
                        Spacer()
                    }
                    .padding(.bottom, 4)

                    handicapCard(history: history, eligible: Handicap.eligibleRoundCount(data) + imported.count)

                    if let last = rounds.first {
                        HStack(spacing: 12) {
                            lastRoundTile(last)
                            wrappedTile(last)
                        }
                    }

                    if let item = plan.first {
                        workOnNext(item)
                    }

                    if rounds.count > 1 {
                        recentSection
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(Color.tgBackground)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(item: $wrappedRound) { round in
                RoundWrappedView(round: round) { wrappedRound = nil }
            }
        }
    }

    // MARK: Cards

    private func handicapCard(history: [IndexPoint], eligible: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("HANDICAP INDEX")
                .font(.caption.weight(.heavy))
                .tracking(1.5)
                .foregroundStyle(Color.tgPale)
            if let current = history.last {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formatDecimal(current.index))
                        .font(.system(size: 68, weight: .black))
                        .monospacedDigit()
                    if history.count >= 2 {
                        let change = current.index - history[history.count - 2].index
                        if change != 0 {
                            Text("\(change < 0 ? "▼" : "▲") \(formatDecimal(abs(change)))")
                                .font(.subheadline.weight(.heavy))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(change < 0 ? Color.tgFairway : Color.tgSandDeep, in: RoundedRectangle(cornerRadius: 8))
                                .accessibilityLabel(change < 0 ? "Down \(formatDecimal(abs(change)))" : "Up \(formatDecimal(abs(change)))")
                        }
                    }
                }
                if history.count >= 2 {
                    Chart(Array(history.suffix(20))) { point in
                        LineMark(x: .value("Date", point.date), y: .value("Index", point.index))
                            .foregroundStyle(Color.tgPale)
                            .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(width: 170, height: 40)
                    .accessibilityLabel("Handicap trend")
                }
                if !imported.isEmpty {
                    Text("Includes \(imported.count) imported score\(imported.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Color.tgPale)
                }
            } else {
                Text("Play \(max(1, 3 - eligible)) more 18-hole round\(3 - eligible == 1 ? "" : "s") to get your handicap.")
                    .font(.headline)
                    .frame(maxWidth: 220, alignment: .leading)
            }
            Button("Start a round") { selectedTab = .play }
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 170)
        }
        .foregroundStyle(Color(hex: 0xF3F6F2))
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            MowingStripes(base: .tgRough, stripe: .tgRoughStripe, width: 36)
        }
        .overlay(alignment: .bottomTrailing) {
            Golfer(style: .light, height: 96).padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func lastRoundTile(_ round: Round) -> some View {
        NavigationLink {
            RoundSummaryView(round: round)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text("LAST ROUND").font(.caption.weight(.heavy)).tracking(1).foregroundStyle(Color.tgAccent)
                Text("\(round.totalStrokes)").font(.system(size: 42, weight: .black)).monospacedDigit()
                Text("\(round.courseName) · \(formatToPar(round.toPar))")
                    .font(.subheadline.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(Color.tgRough)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background { MowingStripes(base: .tgGreen, stripe: .tgGreenStripe, width: 22) }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func wrappedTile(_ round: Round) -> some View {
        Button { wrappedRound = round } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text("ROUND WRAPPED").font(.caption.weight(.heavy)).tracking(1)
                Image(systemName: "play.fill")
                    .font(.title3)
                    .foregroundStyle(Color.tgSand)
                    .frame(width: 46, height: 46)
                    .background(Color.tgRough, in: Circle())
                Text("Watch your round").font(.subheadline.weight(.bold))
            }
            .foregroundStyle(Color(hex: 0x3D2D12))
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .background(Color.tgSand, in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func workOnNext(_ item: PracticeItem) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "scope")
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(Color.tgSandDeep, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("WORK ON NEXT").font(.caption.weight(.heavy)).tracking(1).foregroundStyle(Color(hex: 0x7A5A25))
                Text(item.focus).font(.headline.weight(.heavy))
                Text(String(format: "%.1f shots a round to find", item.toGain))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.tgSandText)
            }
            Spacer()
        }
        .foregroundStyle(Color.tgRough)
        .padding(16)
        .background(Color.tgSandLight, in: RoundedRectangle(cornerRadius: 14))
        .onTapGesture { selectedTab = .stats }
        .accessibilityAddTraits(.isButton)
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Recent rounds")
            VStack(spacing: 0) {
                let recent = Array(rounds.prefix(6))
                ForEach(recent.indices, id: \.self) { i in
                    let round = recent[i]
                    NavigationLink {
                        RoundSummaryView(round: round)
                    } label: {
                        RoundRow(round: round)
                    }
                    .buttonStyle(.plain)
                    if i < recent.count - 1 { Hairline() }
                }
            }
            .padding(.horizontal, 16)
            .background(Color.tgSurface, in: RoundedRectangle(cornerRadius: 14))
        }
        .padding(.top, 4)
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
