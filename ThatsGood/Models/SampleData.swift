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
            let round = Round.start(course: course, handicapIndex: Handicap.currentIndex(previous), in: context, playedOn: date)
            let skill = Double(i) / Double(roundCount)  // improves a little each round

            for score in round.scores {
                guard let hole = round.hole(score.number) else { continue }
                simulate(score, par: hole.par, skill: skill, rng: &rng)
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
