import Foundation
import SwiftData

@Model
final class Course {
    var name: String
    var teeName: String
    var courseRating: Double
    var slope: Int
    var holes: [CourseHole]
    var createdAt: Date

    init(name: String, teeName: String, courseRating: Double, slope: Int, holes: [CourseHole]) {
        self.name = name
        self.teeName = teeName
        self.courseRating = courseRating
        self.slope = slope
        self.holes = holes
        self.createdAt = .now
    }

    var par: Int { holes.reduce(0) { $0 + $1.par } }
}

/// A round keeps its own copy of the course details, so editing a course never changes old rounds.
@Model
final class Round {
    var playedOn: Date
    var courseName: String
    var teeName: String
    var courseRating: Double
    var slope: Int
    var holes: [CourseHole]
    var mode: String  // "quick" now, "detailed" in Phase 2
    var handicapIndexAtStart: Double?
    var isComplete: Bool
    @Relationship(deleteRule: .cascade, inverse: \HoleScore.round) var scores: [HoleScore] = []

    init(course: Course, handicapIndex: Double?, playedOn: Date) {
        self.playedOn = playedOn
        self.courseName = course.name
        self.teeName = course.teeName
        self.courseRating = course.courseRating
        self.slope = course.slope
        self.holes = course.holes.sorted { $0.number < $1.number }
        self.mode = "quick"
        self.handicapIndexAtStart = handicapIndex
        self.isComplete = false
    }

    @discardableResult
    static func start(course: Course, handicapIndex: Double?, in context: ModelContext, playedOn: Date = .now) -> Round {
        let round = Round(course: course, handicapIndex: handicapIndex, playedOn: playedOn)
        context.insert(round)
        for hole in round.holes {
            round.scores.append(HoleScore(number: hole.number, par: hole.par))
        }
        return round
    }

    var sortedScores: [HoleScore] { scores.sorted { $0.number < $1.number } }
    var enteredScores: [HoleScore] { sortedScores.filter(\.isEntered) }
    var lastHoleNumber: Int { holes.last?.number ?? 18 }

    func hole(_ number: Int) -> CourseHole? { holes.first { $0.number == number } }
    func score(for number: Int) -> HoleScore? { scores.first { $0.number == number } }

    var totalStrokes: Int { enteredScores.reduce(0) { $0 + $1.strokes } }
    var toPar: Int {
        enteredScores.reduce(0) { total, score in total + score.strokes - (hole(score.number)?.par ?? 4) }
    }

    /// Only holes the player actually entered count.
    var data: RoundData {
        let holeData: [HoleData] = enteredScores.compactMap { score in
            guard let hole = hole(score.number) else { return nil }
            return HoleData(
                par: hole.par,
                strokeIndex: hole.strokeIndex,
                strokes: score.strokes,
                putts: score.putts,
                firstPuttFeet: score.firstPuttFeet > 0 ? score.firstPuttFeet : nil,
                fairway: hole.par >= 4 ? score.fairwayResult : nil,
                green: score.greenResult,
                upAndDown: score.greenResult == .hit ? nil : score.upAndDown,
                penalties: score.penalties
            )
        }
        return RoundData(date: playedOn, courseRating: courseRating, slope: slope,
                         handicapIndex: handicapIndexAtStart, holes: holeData)
    }
}

@Model
final class HoleScore {
    var number: Int
    var strokes: Int
    var putts: Int
    var firstPuttFeet: Int  // 0 = not entered
    var fairway: String?
    var green: String?
    var upAndDown: Bool?
    var penalties: Int
    var isEntered: Bool
    var round: Round?

    init(number: Int, par: Int) {
        self.number = number
        self.strokes = par
        self.putts = 2
        self.firstPuttFeet = 0
        self.fairway = nil
        self.green = nil
        self.upAndDown = nil
        self.penalties = 0
        self.isEntered = false
    }

    var fairwayResult: FairwayResult? {
        get { fairway.flatMap(FairwayResult.init(rawValue:)) }
        set { fairway = newValue?.rawValue }
    }

    var greenResult: GreenResult? {
        get { green.flatMap(GreenResult.init(rawValue:)) }
        set { green = newValue?.rawValue }
    }
}
