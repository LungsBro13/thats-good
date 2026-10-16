import SwiftUI

/// One friend: their form, a stat-by-stat comparison with you, and their recent rounds.
struct FriendDetailView: View {
    let player: PlayerSnapshot
    let me: PlayerSnapshot?

    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @State private var confirmRemove = false

    private struct Comparison: Identifiable {
        let label: String
        let mine: String
        let theirs: String
        let mineBetter: Bool?
        var id: String { label }
    }

    private func comparisons() -> [Comparison] {
        let theirData = Array(player.rounds.prefix(20)).map(\.data)
        let myData = Array((me?.rounds ?? []).prefix(20)).map(\.data)
        let t = RoundStats.summarize(theirData), m = RoundStats.summarize(myData)
        let tsg = StrokesGained.summarize(theirData).perRound(.putting)
        let msg = StrokesGained.summarize(myData).perRound(.putting)

        func row(_ label: String, _ mine: Double?, _ theirs: Double?, lowerIsBetter: Bool,
                 format: (Double?) -> String) -> Comparison {
            var better: Bool?
            if let mine, let theirs, mine != theirs { better = lowerIsBetter ? mine < theirs : mine > theirs }
            return Comparison(label: label, mine: format(mine), theirs: format(theirs), mineBetter: better)
        }
        return [
            row("Handicap", me?.progress.handicap, player.progress.handicap, lowerIsBetter: true) { formatDecimal($0) },
            row("Avg score", m.averageScore, t.averageScore, lowerIsBetter: true) { formatDecimal($0) },
            row("Fairways", m.fairwayPct, t.fairwayPct, lowerIsBetter: false, format: formatPercent),
            row("Greens", m.girPct, t.girPct, lowerIsBetter: false, format: formatPercent),
            row("Putts / round", m.puttsPerRound, t.puttsPerRound, lowerIsBetter: true) { formatDecimal($0) },
            row("Up and down", m.upAndDownPct, t.upAndDownPct, lowerIsBetter: false, format: formatPercent),
            row("SG putting", msg, tsg, lowerIsBetter: false) { $0.map { String(format: "%+.1f", $0) } ?? "–" },
        ]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 14) {
                    Avatar(initials: player.profile.initials).scaleEffect(1.4).frame(width: 50, height: 50)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.isMe ? "You" : player.profile.displayName).font(.title2.weight(.semibold))
                        Text("@\(player.profile.username) · \(player.progress.roundCount) rounds")
                            .font(.subheadline)
                            .foregroundStyle(Color.tgMuted)
                    }
                }

                HStack(spacing: 0) {
                    StatTile(title: "Handicap", value: formatDecimal(player.progress.handicap))
                    StatTile(title: "90-day change", value: player.progress.handicapChange.map { String(format: "%+.1f", $0) } ?? "–")
                    StatTile(title: "Best round", value: player.progress.bestRound.map(String.init) ?? "–")
                }
                .overlay(alignment: .top) { Hairline() }
                .overlay(alignment: .bottom) { Hairline() }

                if !player.isMe {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("You").font(.subheadline.weight(.semibold))
                            Spacer()
                            SectionLabel("Last 20 rounds")
                            Spacer()
                            Text(player.profile.displayName).font(.subheadline.weight(.semibold))
                        }
                        .padding(.bottom, 8)
                        ForEach(comparisons()) { row in
                            HStack {
                                Text(row.mine)
                                    .fontWeight(row.mineBetter == true ? .bold : .regular)
                                    .foregroundStyle(row.mineBetter == true ? Color.tgAccent : Color.primary)
                                    .frame(width: 70, alignment: .leading)
                                Spacer()
                                Text(row.label).font(.caption).foregroundStyle(Color.tgMuted)
                                Spacer()
                                Text(row.theirs)
                                    .fontWeight(row.mineBetter == false ? .bold : .regular)
                                    .foregroundStyle(row.mineBetter == false ? Color.tgAccent : Color.primary)
                                    .frame(width: 70, alignment: .trailing)
                            }
                            .monospacedDigit()
                            .frame(minHeight: 40)
                            Hairline()
                        }
                        Text("Head-to-head match records arrive with side matches.")
                            .font(.caption)
                            .foregroundStyle(Color.tgMuted)
                            .padding(.top, 8)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Recent rounds").padding(.bottom, 6)
                    if player.rounds.isEmpty {
                        Text("No rounds shared yet.").font(.footnote).foregroundStyle(Color.tgMuted)
                    }
                    ForEach(Array(player.rounds.prefix(15))) { round in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(round.courseName).font(.body.weight(.semibold)).lineLimit(1)
                                Text(round.date.formatted(date: .abbreviated, time: .omitted))
                                    .font(.caption)
                                    .foregroundStyle(Color.tgMuted)
                            }
                            Spacer()
                            Text("\(round.strokes)").font(.title3.weight(.semibold)).monospacedDigit()
                            Text(formatToPar(round.toPar))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(scoreColor(round.toPar))
                                .frame(width: 36, alignment: .trailing)
                        }
                        .frame(minHeight: 52)
                        Hairline()
                    }
                }

                if !player.isMe {
                    Button("Remove friend", role: .destructive) { confirmRemove = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(20)
        }
        .background(Color.tgBackground)
        .navigationTitle(player.isMe ? "You" : player.profile.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Remove \(player.profile.displayName)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                Task {
                    await backend.remove(player.profile)
                    dismiss()
                }
            }
        }
    }
}
