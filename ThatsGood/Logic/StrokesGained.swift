import Foundation

/// One stroke in Detailed mode: where it was hit from. Putts are not shots; they come from HoleData.putts.
struct ShotData {
    var lie: ShotLie
    var distance: Double  // yards to the hole (feet when the lie is green)
}

enum SGCategory: String, CaseIterable, Identifiable {
    case offTheTee, approach, aroundGreen, putting

    var id: String { rawValue }

    var label: String {
        switch self {
        case .offTheTee: return "Off the tee"
        case .approach: return "Approach"
        case .aroundGreen: return "Short game"
        case .putting: return "Putting"
        }
    }
}

struct SGSummary {
    var totals: [SGCategory: Double] = [:]
    var roundsWithData: [SGCategory: Int] = [:]

    func perRound(_ category: SGCategory) -> Double? {
        guard let n = roundsWithData[category], n > 0 else { return nil }
        return (totals[category] ?? 0) / Double(n)
    }

    var hasData: Bool { roundsWithData.values.contains { $0 > 0 } }
}

enum StrokesGained {
    /// Expected strokes to hole out. Approximate tour averages, based on Mark Broadie's published tables.
    /// Swap in a validated scratch-golfer table when we have one.
    static let baseline: [ShotLie: [(Double, Double)]] = [
        .tee: [(100, 2.92), (120, 2.99), (140, 2.97), (160, 2.99), (180, 3.05), (200, 3.12), (220, 3.17),
               (240, 3.25), (260, 3.45), (280, 3.65), (300, 3.71), (320, 3.79), (340, 3.86), (360, 3.92),
               (380, 3.96), (400, 3.99), (420, 4.02), (440, 4.08), (460, 4.17), (480, 4.28), (500, 4.41),
               (520, 4.54), (540, 4.65), (560, 4.74), (580, 4.79), (600, 4.82)],
        .fairway: [(5, 2.10), (10, 2.18), (20, 2.40), (30, 2.52), (40, 2.60), (50, 2.66), (60, 2.70),
                   (80, 2.75), (100, 2.80), (120, 2.85), (140, 2.91), (160, 2.98), (180, 3.08), (200, 3.19),
                   (220, 3.32), (240, 3.45), (260, 3.58), (280, 3.69), (300, 3.78), (350, 3.97), (400, 4.11)],
        .rough: [(5, 2.20), (10, 2.34), (20, 2.59), (30, 2.70), (40, 2.78), (60, 2.91), (80, 2.96),
                 (100, 3.02), (120, 3.08), (140, 3.15), (160, 3.23), (180, 3.31), (200, 3.42), (220, 3.53),
                 (240, 3.64), (260, 3.74), (280, 3.83), (300, 3.90), (350, 4.05), (400, 4.20)],
        .sand: [(5, 2.35), (10, 2.43), (20, 2.53), (30, 2.66), (40, 2.82), (60, 3.15), (80, 3.24),
                (100, 3.23), (120, 3.21), (140, 3.22), (160, 3.28), (180, 3.40), (200, 3.55), (220, 3.70),
                (240, 3.84), (260, 3.93), (300, 4.05)],
        .recovery: [(20, 3.10), (50, 3.45), (100, 3.80), (150, 3.85), (200, 3.87), (250, 4.10), (300, 4.30)],
        .green: [(1, 1.00), (2, 1.01), (3, 1.04), (4, 1.13), (5, 1.23), (6, 1.34), (7, 1.42), (8, 1.50),
                 (9, 1.56), (10, 1.61), (15, 1.78), (20, 1.87), (25, 1.93), (30, 1.98), (40, 2.06),
                 (50, 2.14), (60, 2.21), (90, 2.40)],
    ]

    static func expected(_ lie: ShotLie, _ distance: Double) -> Double {
        // Short tee shots (par 3s under 100 yards) play like the fairway.
        let table = (lie == .tee && distance < 100) ? baseline[.fairway]! : baseline[lie]!
        if distance <= table[0].0 { return table[0].1 }
        for i in 1..<table.count where distance <= table[i].0 {
            let (x0, y0) = table[i - 1], (x1, y1) = table[i]
            return y0 + (y1 - y0) * (distance - x0) / (x1 - x0)
        }
        return table[table.count - 1].1
    }

    static func category(for shot: ShotData, par: Int) -> SGCategory {
        if shot.lie == .green { return .putting }
        if shot.lie == .tee && par >= 4 { return .offTheTee }
        if shot.lie == .tee || shot.distance > 30 { return .approach }
        return .aroundGreen
    }

    /// Strokes gained on one hole, by category. Missing data just leaves a category out.
    static func holeValues(_ hole: HoleData) -> [SGCategory: Double] {
        var out: [SGCategory: Double] = [:]
        let shots = hole.shots
        for (i, shot) in shots.enumerated() {
            let end: Double
            if i + 1 < shots.count {
                end = expected(shots[i + 1].lie, shots[i + 1].distance)
            } else if hole.putts == 0 {
                end = 0  // holed out
            } else if let feet = hole.firstPuttFeet {
                end = expected(.green, Double(feet))
            } else {
                break  // don't know where the last shot finished
            }
            out[category(for: shot, par: hole.par), default: 0] += expected(shot.lie, shot.distance) - end - 1
        }
        if let first = shots.first, hole.penalties > 0 {
            out[category(for: first, par: hole.par), default: 0] -= Double(hole.penalties)
        }
        if hole.putts > 0, let feet = hole.firstPuttFeet {
            out[.putting, default: 0] += expected(.green, Double(feet)) - Double(hole.putts)
        }
        return out
    }

    /// Average strokes gained per round, counting only rounds that have data for each category.
    static func summarize(_ rounds: [RoundData]) -> SGSummary {
        var summary = SGSummary()
        for round in rounds {
            var roundTotals: [SGCategory: Double] = [:]
            for hole in round.holes {
                for (category, value) in holeValues(hole) {
                    roundTotals[category, default: 0] += value
                }
            }
            for (category, value) in roundTotals {
                summary.totals[category, default: 0] += value
                summary.roundsWithData[category, default: 0] += 1
            }
        }
        return summary
    }
}

struct ClubDistance: Identifiable {
    let club: String
    let count: Int
    let average: Double
    let median: Double
    let spread: Double  // standard deviation in yards

    var id: String { club }
}

enum ClubStats {
    static func summarize(_ samples: [(club: String, yards: Double)], order: [String]) -> [ClubDistance] {
        let grouped = Dictionary(grouping: samples, by: \.club)
        let result = grouped.map { club, items -> ClubDistance in
            let values = items.map(\.yards).sorted()
            let n = Double(values.count)
            let mean = values.reduce(0, +) / n
            let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / n
            let mid = values.count / 2
            let median = values.count % 2 == 0 ? (values[mid - 1] + values[mid]) / 2 : values[mid]
            return ClubDistance(club: club, count: values.count, average: mean, median: median, spread: sqrt(variance))
        }
        return result.sorted {
            let a = order.firstIndex(of: $0.club) ?? Int.max
            let b = order.firstIndex(of: $1.club) ?? Int.max
            return a != b ? a < b : $0.average > $1.average
        }
    }
}
