import SwiftUI
import SwiftData

struct RoundSummaryView: View {
    let round: Round
    var onDone: (() -> Void)? = nil

    var body: some View {
        let data = round.data
        let stats = RoundStats.summarize([data])
        let differential = Handicap.scoreDifferential(data)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    SectionLabel("\(round.playedOn.formatted(date: .abbreviated, time: .omitted)) · \(round.teeName) tees")
                    Text(round.courseName).font(.title2.weight(.semibold))
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(round.totalStrokes)")
                            .font(.system(size: 56, weight: .semibold))
                            .monospacedDigit()
                        Text(formatToPar(round.toPar))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(scoreColor(round.toPar))
                    }
                }

                ScorecardGrid(round: round)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                    StatTile(title: "Fairways", value: "\(stats.fairwayHits)/\(stats.fairwayAttempts)")
                    StatTile(title: "Greens", value: "\(stats.greenHits)/\(stats.greenAttempts)")
                    StatTile(title: "Putts", value: "\(stats.totalPutts)")
                    StatTile(title: "Up and down", value: "\(stats.upAndDownMade)/\(stats.upAndDownAttempts)")
                    StatTile(title: "3-putts", value: "\(stats.threePutts)")
                    StatTile(title: "Penalties", value: "\(stats.totalPenalties)")
                }
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }

                if let differential {
                    VStack(alignment: .leading, spacing: 4) {
                        SectionLabel("Score differential")
                        Text(formatDecimal(differential)).font(.title2.weight(.semibold))
                        Text("Your handicap estimate uses your best 8 of your last 20 differentials.")
                            .font(.footnote)
                            .foregroundStyle(Color.tgMuted)
                    }
                } else {
                    Text("Only complete 18-hole rounds count towards your handicap.")
                        .font(.footnote)
                        .foregroundStyle(Color.tgMuted)
                }

                if let onDone {
                    Button("Done", action: onDone)
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(20)
        }
        .background(Color.tgBackground)
        .navigationTitle("Round summary")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Front nine and back nine, with hole, par and score rows.
struct ScorecardGrid: View {
    let round: Round

    var body: some View {
        let holes = round.holes
        VStack(spacing: 16) {
            nine(Array(holes.prefix(9)), totalLabel: "Out")
            if holes.count > 9 {
                nine(Array(holes.dropFirst(9)), totalLabel: "In")
            }
        }
    }

    private func nine(_ holes: [CourseHole], totalLabel: String) -> some View {
        let entered = holes.compactMap { hole in round.score(for: hole.number).flatMap { $0.isEntered ? $0 : nil } }
        let parTotal = holes.reduce(0) { $0 + $1.par }
        let scoreTotal = entered.reduce(0) { $0 + $1.strokes }

        return Grid(horizontalSpacing: 0, verticalSpacing: 6) {
            GridRow {
                label("Hole")
                ForEach(holes) { hole in cell("\(hole.number)", color: Color.tgMuted) }
                cell(totalLabel, color: Color.tgMuted, bold: true)
            }
            GridRow {
                label("Par")
                ForEach(holes) { hole in cell("\(hole.par)", color: Color.tgMuted) }
                cell("\(parTotal)", color: Color.tgMuted, bold: true)
            }
            GridRow {
                label("Score")
                ForEach(holes) { hole in
                    if let score = round.score(for: hole.number), score.isEntered {
                        cell("\(score.strokes)", color: scoreColor(score.strokes - hole.par), bold: true)
                    } else {
                        cell("–", color: Color.tgMuted)
                    }
                }
                cell(entered.isEmpty ? "–" : "\(scoreTotal)", color: .primary, bold: true)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(Color.tgMuted)
            .frame(width: 40, alignment: .leading)
    }

    private func cell(_ text: String, color: Color, bold: Bool = false) -> some View {
        Text(text)
            .fontWeight(bold ? .semibold : .regular)
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
    }
}
