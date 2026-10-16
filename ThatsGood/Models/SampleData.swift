import Foundation
import SwiftData

/// Demo course and rounds for trying the app before playing. Same rounds every time.
enum SampleData {
    static let courseName = "Demo Golf Club"

    static func load(into context: ModelContext) {
        let pars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
        let strokeIndexes = [7, 3, 15, 11, 1, 9, 17, 5, 13, 8, 16, 2, 12, 6, 10, 18, 4, 14]
        let yards = [392, 418, 168, 512, 441, 377, 152, 405, 530, 386, 175, 433, 498, 401, 365, 141, 420, 545]
        let holes = (0..<18).map {
            CourseHole(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0], yards: yards[$0])
        }
        let course = Course(name: courseName, teeName: "White", courseRating: 71.8, slope: 128, holes: holes)
        context.insert(course)

        var rng = SeededGenerator(seed: 7)
        var previous: [RoundData] = []
        let roundCount = 12

        for i in 0..<roundCount {
            let daysAgo = Double((roundCount - i) * 9)
            let date = Date.now.addingTimeInterval(-daysAgo * 86_400)
            let detailed = i >= roundCount - 4  // the latest 4 rounds have marked shots
            let round = Round.start(course: course, handicapIndex: Handicap.currentIndex(previous), in: context,
                                    playedOn: date, mode: detailed ? "detailed" : "quick")
            let skill = Double(i) / Double(roundCount)  // improves a little each round

            for score in round.scores {
                guard let hole = round.hole(score.number) else { continue }
                if detailed {
                    simulateDetailed(score, hole: hole, round: round, rng: &rng)
                } else {
                    simulate(score, par: hole.par, skill: skill, rng: &rng)
                }
                score.isEntered = true
            }
            round.isComplete = true
            previous.append(round.data)
        }
    }

    private static func simulate(_ score: HoleScore, par: Int, skill: Double, rng: inout SeededGenerator) {
        func roll() -> Double { Double.random(in: 0..<1, using: &rng) }

        var fairwayMissed = false
        if par >= 4 {
            let r = roll()
            score.fairwayResult = r < 0.55 ? .hit : (r < 0.78 ? .left : .right)
            fairwayMissed = score.fairwayResult != .hit
        }

        let penalty = roll() < 0.03 ? 1 : 0
        score.penalties = penalty
        let girChance = 0.38 + 0.10 * skill - (fairwayMissed ? 0.14 : 0)

        if roll() < girChance {
            score.greenResult = .hit
            score.upAndDown = nil
            let r = roll()
            score.putts = r < 0.12 ? 1 : (r < 0.93 ? 2 : 3)
            score.firstPuttFeet = Int.random(in: 6...45, using: &rng)
            score.strokes = par - 2 + score.putts + penalty
        } else {
            let r = roll()
            score.greenResult = r < 0.36 ? .short : (r < 0.66 ? .right : (r < 0.86 ? .left : .long))
            if roll() < 0.32 + 0.10 * skill {
                score.upAndDown = true
                score.putts = 1
                score.firstPuttFeet = Int.random(in: 2...9, using: &rng)
                score.strokes = par + penalty
            } else {
                score.upAndDown = false
                score.putts = 2
                score.firstPuttFeet = Int.random(in: 8...30, using: &rng)
                score.strokes = par + 1 + (roll() < 0.2 ? 1 : 0) + penalty
            }
        }
    }

    /// The demo player's typical carry for each club.
    static let clubYards: [(String, Double)] = [
        ("Dr", 255), ("3W", 232), ("5W", 215), ("4H", 200), ("5i", 186), ("6i", 174), ("7i", 162),
        ("8i", 150), ("9i", 138), ("PW", 126), ("GW", 112), ("SW", 96), ("LW", 78),
    ]

    /// Plays a hole shot by shot on a straight line, marking each ball like a player would.
    private static func simulateDetailed(_ score: HoleScore, hole: CourseHole, round: Round, rng: inout SeededGenerator) {
        func roll() -> Double { Double.random(in: 0..<1, using: &rng) }
        func gaussian() -> Double {
            let u1 = max(1e-9, roll()), u2 = roll()
            return sqrt(-2 * log(u1)) * cos(2 * .pi * u2)
        }

        let par = hole.par
        let length = Double(hole.yards > 0 ? hole.yards : (par == 3 ? 165 : par == 4 ? 400 : 520))
        let tee = GeoPoint(lat: 51.40 + Double(hole.number) * 0.01, lon: -1.30)
        func position(along: Double, side: Double) -> GeoPoint {
            let forward = Geo.offset(tee, bearing: 0, meters: along / Geo.yardsPerMeter)
            return Geo.offset(forward, bearing: 90, meters: side / Geo.yardsPerMeter)
        }

        var along = 0.0, side = 0.0
        var remaining = length
        var lie = ShotLie.tee
        var strokes = 0
        var secondLie: ShotLie?
        var index = 0

        func mark(_ club: String?, _ lie: ShotLie, toGreen: Double) {
            index += 1
            round.shots.append(Shot(holeNumber: hole.number, index: index, club: club, lie: lie,
                                    point: position(along: along, side: side), yardsToGreen: toGreen))
        }

        // Full shots until the ball is near the green.
        while remaining > 30 && strokes < 6 {
            let club: String
            if lie == .tee && par >= 4 {
                club = remaining > 260 ? "Dr" : "3W"
            } else {
                club = clubYards.min { abs($0.1 - remaining) < abs($1.1 - remaining) }!.0
            }
            mark(club, lie, toGreen: remaining)
            strokes += 1

            let carry = clubYards.first { $0.0 == club }!.1
            var hit = carry * (1 + 0.065 * gaussian())
            if lie == .rough { hit *= 0.93 }
            if lie == .sand { hit *= 0.85 }
            if club != "Dr" && club != "3W" { hit = min(hit, remaining + 15) }
            along += hit
            side += gaussian() * carry * 0.045
            remaining = sqrt(pow(length - along, 2) + side * side)

            if remaining < 17 {
                lie = .green
            } else if remaining <= 30 {
                lie = roll() < 0.25 ? .sand : .rough
            } else {
                lie = roll() < (strokes == 1 ? 0.55 : 0.7) ? .fairway : .rough
            }
            if strokes == 1 { secondLie = lie }
            if lie == .green { break }
        }

        // A chip or bunker shot if the ball isn't on the green yet.
        let firstPutt: Double
        let reachedInRegulation = lie == .green && strokes <= par - 2
        if lie != .green {
            mark(lie == .sand ? "SW" : "LW", lie, toGreen: remaining)
            strokes += 1
            firstPutt = max(2, 13 + 6 * gaussian())
            along = length - firstPutt / 3
            side = 0
        } else {
            firstPutt = max(3, remaining * 3 + 6 * gaussian())
        }
        mark(nil, .green, toGreen: firstPutt / 3)

        let makeChance: Double = firstPutt <= 3 ? 0.95 : firstPutt <= 6 ? 0.6 : firstPutt <= 10 ? 0.4 : firstPutt <= 20 ? 0.15 : 0.07
        let threePuttChance: Double = firstPutt > 35 ? 0.15 : firstPutt > 20 ? 0.06 : 0.02
        let r = roll()
        let putts = r < makeChance ? 1 : (r < makeChance + threePuttChance ? 3 : 2)

        score.putts = putts
        score.firstPuttFeet = Int(firstPutt.rounded())
        score.penalties = 0
        score.strokes = strokes + putts
        if par >= 4 {
            score.fairwayResult = secondLie == .fairway ? .hit : (side < 0 ? .left : .right)
        }
        if reachedInRegulation {
            score.greenResult = .hit
            score.upAndDown = nil
        } else {
            score.greenResult = roll() < 0.4 ? .short : (side < 0 ? .left : .right)
            score.upAndDown = score.strokes <= par
        }
    }
}

/// Simple repeatable random numbers, so demo data is the same each time.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}
