import SwiftUI
import SwiftData

/// Club and lay-up advice for the shot the player is about to hit, from their own data.
struct CaddieCard: View {
    let distance: Double
    let lie: ShotLie
    /// A small box for the corner of the map: just the advice.
    var compact = false

    @Query(filter: #Predicate<Round> { $0.isComplete }) private var finished: [Round]
    @Query(filter: #Predicate<Club> { $0.inBag }, sort: \Club.sortOrder) private var clubs: [Club]

    var body: some View {
        let model = PlayerModel.build(finished.map(\.data))
        let measured = ClubStats.summarize(finished.flatMap(\.clubSamples), order: clubs.map(\.name))
        let yardages = Caddie.yardages(bag: clubs.isEmpty ? Club.defaultNames : clubs.map(\.name), measured: measured)
        let advice = Caddie.advise(distance: distance, lie: lie, model: model, clubs: yardages)

        if compact {
            VStack(alignment: .leading, spacing: 1) {
                Text("CADDIE").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Color.tgAccent)
                Text(shortHeadline(advice)).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
        } else {
            full(advice, model: model)
        }
    }

    private func full(_ advice: CaddieAdvice, model: PlayerModel) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Caddie")
                Spacer()
                Text("\(Int(distance.rounded())) to the middle").font(.caption).foregroundStyle(Color.tgMuted)
            }
            Text(headline(advice))
                .font(.title3.weight(.semibold))
                .foregroundStyle(advice.recommendsLayup ? Color.tgAccent : Color.primary)
            ForEach(details(advice, model: model), id: \.self) { line in
                Text(line).font(.footnote).foregroundStyle(Color.tgMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.tgLine))
        .accessibilityElement(children: .combine)
    }

    private func shortHeadline(_ a: CaddieAdvice) -> String {
        if a.recommendsLayup, let l = a.layup { return "\(l.club), leave \(Int(l.leave.rounded()))" }
        return a.club?.club ?? "–"
    }

    private func headline(_ a: CaddieAdvice) -> String {
        if a.recommendsLayup, let l = a.layup {
            return (a.canReach ? "Lay up: " : "") + "\(l.club) to leave \(Int(l.leave.rounded()))"
        }
        guard let c = a.club else { return "No clubs in the bag" }
        return "\(c.club) · \(c.fromData ? "your" : "typical") \(c.club) goes \(Int(c.yards.rounded()))"
    }

    private func details(_ a: CaddieAdvice, model: PlayerModel) -> [String] {
        var lines: [String] = []
        if let go = a.goExpected, let l = a.layup {
            lines.append("Going for it: you average \(String(format: "%.1f", go)) from here. Laying up to \(Int(l.leave.rounded())): \(String(format: "%.1f", l.expected)).")
        } else if !a.canReach, a.layup != nil {
            lines.append("Out of range. This leaves the distance you score best from.")
        }
        if let fav = a.favourite { lines.append("Your best full-swing distance: about \(Int(fav)) yd.") }
        if !model.hasData { lines.append("Using typical numbers until you've played more Detailed rounds.") }
        return lines
    }
}
