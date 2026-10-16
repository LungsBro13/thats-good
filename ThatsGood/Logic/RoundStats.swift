import Foundation

struct ScoreMix {
    var birdiesOrBetter = 0.0
    var pars = 0.0
    var bogeys = 0.0
    var doublesOrWorse = 0.0
}

struct StatSummary {
    var roundCount = 0
    var holeCount = 0

    var averageScore: Double?
    var averageToPar: Double?

    var fairwayHits = 0
    var fairwayLefts = 0
    var fairwayRights = 0
    var fairwayAttempts = 0

    var greenHits = 0
    var greenAttempts = 0
    var greenMisses: [GreenResult: Int] = [:]

    var upAndDownMade = 0
    var upAndDownAttempts = 0

    var totalPutts = 0
    var onePutts = 0
    var threePutts = 0
    var totalPenalties = 0

    var averageToParByPar: [Int: Double] = [:]
    var mixPerRound = ScoreMix()

    var fairwayPct: Double? { ratio(fairwayHits, fairwayAttempts) }
    var fairwayLeftPct: Double? { ratio(fairwayLefts, fairwayAttempts) }
    var fairwayRightPct: Double? { ratio(fairwayRights, fairwayAttempts) }
    var girPct: Double? { ratio(greenHits, greenAttempts) }
    var upAndDownPct: Double? { ratio(upAndDownMade, upAndDownAttempts) }
    var onePuttPct: Double? { ratio(onePutts, holeCount) }
    var threePuttPct: Double? { ratio(threePutts, holeCount) }
    var puttsPerRound: Double? { roundCount > 0 ? Double(totalPutts) / Double(roundCount) : nil }
    var penaltiesPerRound: Double? { roundCount > 0 ? Double(totalPenalties) / Double(roundCount) : nil }

    /// Share of missed greens that went each way.
    func greenMissShare(_ miss: GreenResult) -> Double? {
        let missed = greenMisses.values.reduce(0, +)
        return ratio(greenMisses[miss] ?? 0, missed)
    }

    private func ratio(_ part: Int, _ whole: Int) -> Double? {
        whole > 0 ? Double(part) / Double(whole) : nil
    }
}

enum RoundStats {
    static func summarize(_ rounds: [RoundData]) -> StatSummary {
        var s = StatSummary()
        let played = rounds.filter { !$0.holes.isEmpty }
        s.roundCount = played.count
        guard !played.isEmpty else { return s }

        let full = played.filter { $0.holes.count == 18 }
        if !full.isEmpty {
            s.averageScore = Double(full.reduce(0) { $0 + $1.strokes }) / Double(full.count)
            s.averageToPar = Double(full.reduce(0) { $0 + $1.toPar }) / Double(full.count)
        }

        var toParByPar: [Int: (total: Int, holes: Int)] = [:]
        var mix = ScoreMix()

        for hole in played.flatMap(\.holes) {
            s.holeCount += 1
            s.totalPutts += hole.putts
            s.totalPenalties += hole.penalties
            if hole.putts == 1 { s.onePutts += 1 }
            if hole.putts >= 3 { s.threePutts += 1 }

            if hole.par >= 4, let fairway = hole.fairway {
                s.fairwayAttempts += 1
                switch fairway {
                case .hit: s.fairwayHits += 1
                case .left: s.fairwayLefts += 1
                case .right: s.fairwayRights += 1
                }
            }

            if let green = hole.green {
                s.greenAttempts += 1
                if green == .hit {
                    s.greenHits += 1
                } else {
                    s.greenMisses[green, default: 0] += 1
                }
            }

            if let upAndDown = hole.upAndDown {
                s.upAndDownAttempts += 1
                if upAndDown { s.upAndDownMade += 1 }
            }

            let diff = hole.strokes - hole.par
            let current = toParByPar[hole.par] ?? (0, 0)
            toParByPar[hole.par] = (current.total + diff, current.holes + 1)

            switch diff {
            case ..<0: mix.birdiesOrBetter += 1
            case 0: mix.pars += 1
            case 1: mix.bogeys += 1
            default: mix.doublesOrWorse += 1
            }
        }

        for (par, value) in toParByPar {
            s.averageToParByPar[par] = Double(value.total) / Double(value.holes)
        }

        let n = Double(played.count)
        s.mixPerRound = ScoreMix(
            birdiesOrBetter: mix.birdiesOrBetter / n,
            pars: mix.pars / n,
            bogeys: mix.bogeys / n,
            doublesOrWorse: mix.doublesOrWorse / n
        )
        return s
    }
}
