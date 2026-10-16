import Foundation

struct IndexPoint: Identifiable {
    let date: Date
    let index: Double

    var id: Date { date }
}

/// Handicap estimate using the World Handicap System formulas.
/// It's an estimate only: official indexes come from a golf association.
enum Handicap {
    static let maxIndex = 54.0

    static func courseHandicap(index: Double, slope: Int, rating: Double, par: Int) -> Int {
        Int((index * Double(slope) / 113.0 + (rating - Double(par))).rounded())
    }

    /// Strokes a player gets (or gives back, for plus handicaps) on one hole.
    static func strokesReceived(courseHandicap: Int, strokeIndex: Int, holeCount: Int = 18) -> Int {
        if courseHandicap >= 0 {
            let extra = courseHandicap % holeCount
            return courseHandicap / holeCount + (strokeIndex <= extra ? 1 : 0)
        }
        let plus = -courseHandicap
        let extra = plus % holeCount
        return -(plus / holeCount + (strokeIndex > holeCount - extra ? 1 : 0))
    }

    /// Gross score with each hole capped at net double bogey (par + 5 before the player has an index).
    static func adjustedGrossScore(_ round: RoundData) -> Int? {
        guard round.holes.count == 18 else { return nil }
        let playerCourseHandicap = round.handicapIndex.map {
            courseHandicap(index: $0, slope: round.slope, rating: round.courseRating, par: round.par)
        }
        return round.holes.reduce(0) { total, hole in
            let cap: Int
            if let playerCourseHandicap {
                cap = hole.par + 2 + strokesReceived(courseHandicap: playerCourseHandicap, strokeIndex: hole.strokeIndex)
            } else {
                cap = hole.par + 5
            }
            return total + min(hole.strokes, cap)
        }
    }

    static func scoreDifferential(_ round: RoundData) -> Double? {
        guard let ags = adjustedGrossScore(round), round.slope > 0 else { return nil }
        let raw = 113.0 / Double(round.slope) * (Double(ags) - round.courseRating)
        return (raw * 10).rounded() / 10
    }

    /// How many of the lowest differentials count, and the adjustment, for a given number of rounds.
    static func rule(forRoundCount n: Int) -> (count: Int, adjustment: Double)? {
        switch n {
        case ..<3: return nil
        case 3: return (1, -2.0)
        case 4: return (1, -1.0)
        case 5: return (1, 0)
        case 6: return (2, -1.0)
        case 7...8: return (2, 0)
        case 9...11: return (3, 0)
        case 12...14: return (4, 0)
        case 15...16: return (5, 0)
        case 17...18: return (6, 0)
        case 19: return (7, 0)
        default: return (8, 0)
        }
    }

    /// Index from differentials, most recent first. Only the latest 20 count.
    static func index(fromDifferentials differentials: [Double]) -> Double? {
        let recent = Array(differentials.prefix(20))
        guard let rule = rule(forRoundCount: recent.count) else { return nil }
        let lowest = recent.sorted().prefix(rule.count)
        let average = lowest.reduce(0, +) / Double(rule.count)
        let value = ((average + rule.adjustment) * 10).rounded() / 10
        return min(value, maxIndex)
    }

    /// The index after each eligible round, oldest first.
    static func history(_ rounds: [RoundData]) -> [IndexPoint] {
        var differentials: [Double] = []
        var points: [IndexPoint] = []
        for round in rounds.sorted(by: { $0.date < $1.date }) {
            guard let differential = scoreDifferential(round) else { continue }
            differentials.insert(differential, at: 0)
            if let value = index(fromDifferentials: differentials) {
                points.append(IndexPoint(date: round.date, index: value))
            }
        }
        return points
    }

    static func currentIndex(_ rounds: [RoundData]) -> Double? {
        history(rounds).last?.index
    }

    static func eligibleRoundCount(_ rounds: [RoundData]) -> Int {
        rounds.filter { $0.holes.count == 18 }.count
    }
}
