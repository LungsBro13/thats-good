import Foundation

/// A friend's (or your own) form, worked out from their rounds.
struct PlayerProgress {
    var handicap: Double?
    var handicapChange: Double?      // over the period; negative = improving
    var averageScore: Double?        // last 10 complete 18-hole rounds
    var averageScoreChange: Double?  // last 10 now vs last 10 at the start of the period
    var bestRound: Int?              // lowest gross 18-hole score
    var roundCount: Int
    var trend: [Double]              // handicap after each of the last 10 rounds

    static func compute(_ rounds: [RoundData], now: Date = Date(), periodDays: Double = 90) -> PlayerProgress {
        let cutoff = now.addingTimeInterval(-periodDays * 86_400)
        let history = Handicap.history(rounds)
        let current = history.last?.index
        let before = history.last { $0.date <= cutoff }?.index
        let change = (current != nil && before != nil) ? current! - before! : nil

        let full = rounds.filter { $0.holes.count == 18 }.sorted { $0.date > $1.date }
        func average(_ list: [RoundData]) -> Double? {
            let recent = Array(list.prefix(10))
            guard !recent.isEmpty else { return nil }
            return Double(recent.reduce(0) { $0 + $1.strokes }) / Double(recent.count)
        }
        let nowAverage = average(full)
        let thenAverage = average(full.filter { $0.date <= cutoff })
        let scoreChange = (nowAverage != nil && thenAverage != nil) ? nowAverage! - thenAverage! : nil

        return PlayerProgress(
            handicap: current,
            handicapChange: change,
            averageScore: nowAverage,
            averageScoreChange: scoreChange,
            bestRound: full.map(\.strokes).min(),
            roundCount: rounds.filter { !$0.holes.isEmpty }.count,
            trend: history.suffix(10).map(\.index)
        )
    }
}

enum LeaderboardKind: String, CaseIterable, Identifiable {
    case handicap, improved, bestRound, rounds

    var id: String { rawValue }

    var label: String {
        switch self {
        case .handicap: return "Handicap"
        case .improved: return "Most improved"
        case .bestRound: return "Best round"
        case .rounds: return "Rounds"
        }
    }
}

struct LeaderboardEntry<ID: Hashable>: Identifiable {
    let id: ID
    let value: Double
}

enum Leaderboard {
    /// Ranks players. Players with no value for the board are left out.
    static func rank<ID: Hashable>(_ players: [ID: PlayerProgress], by kind: LeaderboardKind) -> [LeaderboardEntry<ID>] {
        let entries: [LeaderboardEntry<ID>] = players.compactMap { id, p in
            let value: Double?
            switch kind {
            case .handicap: value = p.handicap
            case .improved: value = p.handicapChange
            case .bestRound: value = p.bestRound.map(Double.init)
            case .rounds: value = p.roundCount > 0 ? Double(p.roundCount) : nil
            }
            return value.map { LeaderboardEntry(id: id, value: $0) }
        }
        // Lower is better for everything except rounds played.
        return entries.sorted { kind == .rounds ? $0.value > $1.value : $0.value < $1.value }
    }
}
