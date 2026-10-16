import Foundation

// MARK: - The player's own scoring by distance

/// How many strokes the player takes to hole out from a distance, compared with the baseline.
/// Built from Detailed-mode shots. With little data it falls back to the player's overall level.
struct PlayerModel {
    struct Band: Equatable {
        var lower: Double
        var upper: Double  // exclusive; .infinity for the last band
        var shots: Int
        var totalDiff: Double  // sum of (actual strokes to hole out − baseline)

        var label: String { upper == .infinity ? "\(Int(lower))+ yd" : "\(Int(lower))–\(Int(upper)) yd" }
        var middle: Double { upper == .infinity ? lower + 20 : (lower + upper) / 2 }
    }

    static let edges: [Double] = [0, 30, 60, 90, 120, 150, 180, 210, 240]
    /// How many shots a band needs before it counts as much as the player's overall level.
    static let shrink = 6.0

    var bands: [Band]
    var overall: Double  // average strokes per shot above the baseline
    var shotCount: Int

    static let empty = PlayerModel(
        bands: edges.indices.map { Band(lower: edges[$0], upper: $0 + 1 < edges.count ? edges[$0 + 1] : .infinity, shots: 0, totalDiff: 0) },
        overall: 0, shotCount: 0)

    /// Uses holes with Detailed shots and no penalties, so every remaining stroke is a real shot or putt.
    static func build(_ rounds: [RoundData]) -> PlayerModel {
        var model = empty
        var total = 0.0
        for hole in rounds.flatMap(\.holes) where !hole.shots.isEmpty && hole.penalties == 0 {
            for (i, shot) in hole.shots.enumerated() {
                let actual = Double(hole.shots.count - i + hole.putts)
                let diff = actual - StrokesGained.expected(shot.lie, shot.distance)
                total += diff
                model.shotCount += 1
                if let b = model.bands.firstIndex(where: { shot.distance >= $0.lower && shot.distance < $0.upper }) {
                    model.bands[b].shots += 1
                    model.bands[b].totalDiff += diff
                }
            }
        }
        model.overall = model.shotCount > 0 ? total / Double(model.shotCount) : 0
        return model
    }

    /// The band's strokes above baseline, pulled towards the overall level when it has few shots.
    func diff(_ band: Band) -> Double {
        (band.totalDiff + Self.shrink * overall) / (Double(band.shots) + Self.shrink)
    }

    func band(for distance: Double) -> Band {
        bands.first { distance >= $0.lower && distance < $0.upper } ?? bands[bands.count - 1]
    }

    /// Expected strokes to hole out for this player.
    func expected(_ lie: ShotLie, _ distance: Double) -> Double {
        StrokesGained.expected(lie, distance) + (lie == .green ? 0 : diff(band(for: distance)))
    }

    var hasData: Bool { shotCount >= 20 }

    /// The full-swing distance (60–150 yards) the player scores best from, if the data shows one.
    var favouriteBand: Band? {
        guard hasData else { return nil }
        return bands.filter { $0.lower >= 60 && $0.upper <= 150 && $0.shots >= 4 }.min { diff($0) < diff($1) }
    }
}

// MARK: - Club choice and lay-ups

struct ClubYardage: Equatable {
    var club: String
    var yards: Double
    var fromData: Bool
}

struct LayupPlan: Equatable {
    var club: String
    var leave: Double
    var expected: Double
}

struct CaddieAdvice: Equatable {
    var distance: Double
    var club: ClubYardage?       // club to hit if going for the green
    var canReach: Bool
    var goExpected: Double?      // expected strokes going for the green (nil when it can't be reached)
    var layup: LayupPlan?        // the best lay-up
    var favourite: Double?       // the player's favourite distance, if known

    var recommendsLayup: Bool {
        guard let layup else { return false }
        guard let go = goExpected else { return true }
        return layup.expected < go - 0.05
    }

    /// Strokes saved per hole by following the advice instead of the other option.
    var saving: Double? {
        guard let layup, let go = goExpected else { return nil }
        return abs(go - layup.expected)
    }
}

enum Caddie {
    /// Typical carries for a player around a 7 handicap, used until there's enough of their own data.
    static let typicalYards: [String: Double] = [
        "Dr": 250, "3W": 228, "5W": 213, "4H": 200, "5i": 185, "6i": 173, "7i": 162,
        "8i": 150, "9i": 138, "PW": 126, "GW": 112, "SW": 98, "LW": 82,
    ]

    /// The player's clubs, longest first. A club needs 3 measured shots before its own median is used.
    static func yardages(bag: [String], measured: [ClubDistance]) -> [ClubYardage] {
        let byClub = Dictionary(uniqueKeysWithValues: measured.map { ($0.club, $0) })
        return bag.compactMap { club in
            if let m = byClub[club], m.count >= 3 { return ClubYardage(club: club, yards: m.median, fromData: true) }
            return typicalYards[club].map { ClubYardage(club: club, yards: $0, fromData: false) }
        }
        .sorted { $0.yards > $1.yards }
    }

    /// Driver only off the tee.
    static func usable(_ clubs: [ClubYardage], lie: ShotLie) -> [ClubYardage] {
        lie == .tee ? clubs : clubs.filter { $0.club != "Dr" }
    }

    /// The shortest club that gets there (allowing a few yards short), or the longest if none do.
    static func club(for distance: Double, clubs: [ClubYardage]) -> ClubYardage? {
        let enough = clubs.filter { $0.yards >= distance - 4 }
        return enough.min { $0.yards < $1.yards } ?? clubs.max { $0.yards < $1.yards }
    }

    /// Long clubs find the fairway less often.
    static func fairwayChance(_ club: String) -> Double {
        switch club {
        case "Dr": return 0.55
        case "3W", "5W": return 0.62
        case "4H", "5i", "6i": return 0.68
        default: return 0.78
        }
    }

    static func leaveExpected(_ model: PlayerModel, club: String, leave: Double) -> Double {
        let p = fairwayChance(club)
        return 1 + p * model.expected(.fairway, leave) + (1 - p) * model.expected(.rough, leave)
    }

    static func advise(distance: Double, lie: ShotLie, model: PlayerModel, clubs allClubs: [ClubYardage]) -> CaddieAdvice {
        let clubs = usable(allClubs, lie: lie)
        let longest = clubs.map(\.yards).max() ?? 0
        let canReach = longest >= distance - 10
        var advice = CaddieAdvice(distance: distance, club: club(for: distance, clubs: clubs), canReach: canReach,
                                  goExpected: canReach ? model.expected(lie, distance) : nil,
                                  layup: nil, favourite: model.favouriteBand?.middle)
        guard distance >= 120, lie != .green else { return advice }

        // Every club that stays at least 30 yards short of the green, with what it leaves.
        var best: LayupPlan?
        for c in clubs where c.yards <= distance - 30 {
            let leave = distance - c.yards
            let e = leaveExpected(model, club: c.club, leave: leave)
            if best == nil || e < best!.expected { best = LayupPlan(club: c.club, leave: leave, expected: e) }
        }
        advice.layup = best
        return advice
    }
}

// MARK: - Practice plan

struct PracticeItem: Identifiable, Equatable {
    var category: SGCategory
    var toGain: Double     // strokes a round to reach the scratch target
    var focus: String      // e.g. "Putts from 7–20 ft"
    var detail: String
    var drill: String
    var id: String { category.rawValue }
}

/// One stroke's strokes gained, kept with where it was played from.
struct ShotValue {
    var category: SGCategory
    var distance: Double  // yards, or feet for putts
    var value: Double
}

enum PracticePlan {
    /// What a scratch golfer roughly loses to the tour baseline each round, by category.
    static let scratchTarget: [SGCategory: Double] = [
        .offTheTee: -0.6, .approach: -1.2, .aroundGreen: -0.5, .putting: -0.5,
    ]

    /// Strokes gained shot by shot, matching `StrokesGained.holeValues`.
    static func shotValues(_ hole: HoleData) -> [ShotValue] {
        var out: [ShotValue] = []
        let shots = hole.shots
        for (i, shot) in shots.enumerated() {
            let end: Double
            if i + 1 < shots.count {
                end = StrokesGained.expected(shots[i + 1].lie, shots[i + 1].distance)
            } else if hole.putts == 0 {
                end = 0
            } else if let feet = hole.firstPuttFeet {
                end = StrokesGained.expected(.green, Double(feet))
            } else {
                break
            }
            var value = StrokesGained.expected(shot.lie, shot.distance) - end - 1
            if i == 0 { value -= Double(hole.penalties) }
            out.append(ShotValue(category: StrokesGained.category(for: shot, par: hole.par), distance: shot.distance, value: value))
        }
        if hole.putts > 0, let feet = hole.firstPuttFeet {
            out.append(ShotValue(category: .putting, distance: Double(feet),
                                 value: StrokesGained.expected(.green, Double(feet)) - Double(hole.putts)))
        }
        return out
    }

    /// Strokes gained per round in each distance band of one category. Bands are (label, lower, upper).
    static func bandValues(_ rounds: [RoundData], _ category: SGCategory,
                           bands: [(String, Double, Double)]) -> [(label: String, perRound: Double, count: Int)] {
        let sg = StrokesGained.summarize(rounds)
        let n = Double(max(1, sg.roundsWithData[category] ?? 0))
        let values = rounds.flatMap { $0.holes.flatMap(shotValues) }.filter { $0.category == category }
        return bands.map { label, lower, upper in
            let inBand = values.filter { $0.distance >= lower && $0.distance < upper }
            return (label, inBand.reduce(0) { $0 + $1.value } / n, inBand.count)
        }
    }

    static let puttBands: [(String, Double, Double)] = [("Putts inside 6 ft", 0, 7), ("Putts from 7–20 ft", 7, 21), ("Putts over 20 ft", 21, 999)]
    static let approachBands: [(String, Double, Double)] = [("Approaches inside 100 yd", 0, 100), ("Approaches from 100–150 yd", 100, 150),
                                                            ("Approaches from 150–200 yd", 150, 200), ("Approaches over 200 yd", 200, 999)]

    static func build(_ rounds: [RoundData]) -> [PracticeItem] {
        let sg = StrokesGained.summarize(rounds)
        let stats = RoundStats.summarize(rounds)
        var items: [PracticeItem] = []

        for category in SGCategory.allCases {
            guard let perRound = sg.perRound(category), let target = scratchTarget[category] else { continue }
            let gap = target - perRound
            guard gap > 0.1 else { continue }
            items.append(item(category, gap: gap, perRound: perRound, rounds: rounds, stats: stats))
        }
        return Array(items.sorted { $0.toGain > $1.toGain }.prefix(3))
    }

    private static func worst(_ list: [(label: String, perRound: Double, count: Int)]) -> (label: String, perRound: Double, count: Int)? {
        list.filter { $0.count >= 3 }.min { $0.perRound < $1.perRound }
    }

    private static func item(_ category: SGCategory, gap: Double, perRound: Double, rounds: [RoundData], stats: StatSummary) -> PracticeItem {
        let sgText = String(format: "%+.1f", perRound)
        switch category {
        case .putting:
            let w = worst(bandValues(rounds, .putting, bands: puttBands))
            let label = w?.label ?? "Putting"
            var detail = "Putting \(sgText) a round against tour."
            if let w { detail += " Most lost: \(w.label.lowercased()) (\(String(format: "%+.1f", w.perRound)))." }
            if let three = stats.threePuttPct { detail += " 3-putts on \(formatPct(three)) of holes." }
            let drill: String
            switch label {
            case puttBands[0].0: drill = "Clock drill: 6 balls round the hole at 3 ft, then 5 ft. Hole 30 in a row before you leave."
            case puttBands[1].0: drill = "Gate drill: two tees a ball-width apart, 1 ft in front of the ball. 20 putts from 8–15 ft through the gate. Count the makes."
            default: drill = "Ladder drill: putt to the fringe from 30, 40 and 50 ft. Every ball must finish inside 3 ft."
            }
            return PracticeItem(category: category, toGain: gap, focus: label, detail: detail, drill: drill)

        case .approach:
            let w = worst(bandValues(rounds, .approach, bands: approachBands))
            let label = w?.label ?? "Approach play"
            var detail = "Approach \(sgText) a round against tour."
            if let w { detail += " Most lost: \(w.label.lowercased()) (\(String(format: "%+.1f", w.perRound)))." }
            let misses: [GreenResult] = [.short, .long, .left, .right]
            if let top = misses.max(by: { (stats.greenMissShare($0) ?? 0) < (stats.greenMissShare($1) ?? 0) }),
               let share = stats.greenMissShare(top), share >= 0.35 {
                detail += " \(formatPct(share)) of missed greens are \(top.rawValue)" + (top == .short ? ": take one more club." : ".")
            }
            let drill: String
            switch label {
            case approachBands[0].0: drill = "Wedge ladder: 5 balls each to 50, 60, 70, 80 and 90 yards. Write down the carry. Aim to finish inside 15 ft."
            case approachBands[1].0: drill = "9 balls each with PW, 9i and 8i at one flag. Score how many finish inside 20 ft. Beat it next time."
            case approachBands[2].0: drill = "Aim at the middle of the green, not the flag. Hit 3/4 swings with 7i and 6i to a big target for control."
            default: drill = "From over 200, lay up to your favourite wedge distance. On the range, hybrid and wood off the turf to a 30-yard target."
            }
            return PracticeItem(category: category, toGain: gap, focus: label, detail: detail, drill: drill)

        case .aroundGreen:
            var detail = "Short game \(sgText) a round against tour."
            if let ud = stats.upAndDownPct { detail += " Up and down \(formatPct(ud)) of the time (scratch is about 55%)." }
            return PracticeItem(category: category, toGain: gap, focus: "Chipping and pitching", detail: detail,
                                drill: "Up-and-down game: 9 balls from different lies round the green. Chip, then putt out. Aim for 5 of 9.")

        case .offTheTee:
            var detail = "Driving \(sgText) a round against tour."
            if let fw = stats.fairwayPct { detail += " Fairways \(formatPct(fw))." }
            if let l = stats.fairwayLeftPct, let r = stats.fairwayRightPct, abs(l - r) >= 0.08 {
                detail += " Most misses go \(l > r ? "left" : "right")."
            }
            if let p = stats.penaltiesPerRound, p >= 0.5 { detail += " \(String(format: "%.1f", p)) penalties a round." }
            return PracticeItem(category: category, toGain: gap, focus: "Tee shots", detail: detail,
                                drill: "Pick two targets 30 yards apart on the range. 10 drives: count how many finish between them. Take 3W where the fairway is tight.")
        }
    }

    private static func formatPct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }
}
