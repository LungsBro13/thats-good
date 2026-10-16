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
    var geoData: Data? = nil  // CourseGeo as JSON (OpenStreetMap areas and greens the player marked)
    @Relationship(deleteRule: .nullify, inverse: \Round.course) var rounds: [Round] = []

    init(name: String, teeName: String, courseRating: Double, slope: Int, holes: [CourseHole]) {
        self.name = name
        self.teeName = teeName
        self.courseRating = courseRating
        self.slope = slope
        self.holes = holes
        self.createdAt = .now
    }

    var par: Int { holes.reduce(0) { $0 + $1.par } }

    var geo: CourseGeo? {
        get { CourseGeo.decode(geoData) }
        set { geoData = newValue?.encoded() }
    }
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
    @Relationship(deleteRule: .cascade, inverse: \Shot.round) var shots: [Shot] = []
    var course: Course?
    var remoteID: UUID?    // id on the server, set on first upload
    var uploadedAt: Date?  // nil = not shared with friends yet

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
    static func start(course: Course, handicapIndex: Double?, in context: ModelContext,
                      playedOn: Date = .now, mode: String = "quick") -> Round {
        let round = Round(course: course, handicapIndex: handicapIndex, playedOn: playedOn)
        round.mode = mode
        context.insert(round)
        round.course = course
        for hole in round.holes {
            round.scores.append(HoleScore(number: hole.number, par: hole.par))
        }
        return round
    }

    var sortedScores: [HoleScore] { scores.sorted { $0.number < $1.number } }
    var enteredScores: [HoleScore] { sortedScores.filter(\.isEntered) }
    var lastHoleNumber: Int { holes.last?.number ?? 18 }
    var isDetailed: Bool { mode == "detailed" }

    /// Shots on one hole in the order they were marked, including the "on green" marker.
    func shots(onHole number: Int) -> [Shot] {
        shots.filter { $0.holeNumber == number }.sorted { $0.index < $1.index }
    }

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
                penalties: score.penalties,
                shots: shotData(onHole: score.number)
            )
        }
        return RoundData(date: playedOn, courseRating: courseRating, slope: slope,
                         handicapIndex: handicapIndexAtStart, holes: holeData)
    }

    /// Strokes for strokes gained. Empty if any stroke has no distance to the green.
    private func shotData(onHole number: Int) -> [ShotData] {
        let strokes = shots(onHole: number).filter { $0.lieValue != .green }
        let data = strokes.compactMap { shot in shot.yardsToGreen.map { ShotData(lie: shot.lieValue, distance: $0) } }
        return data.count == strokes.count ? data : []
    }

    /// How far each club went: from where a shot was hit to where the next one was marked.
    var clubSamples: [(club: String, yards: Double)] {
        var samples: [(club: String, yards: Double)] = []
        for number in Set(shots.map(\.holeNumber)) {
            let hole = shots(onHole: number)
            for (shot, next) in zip(hole, hole.dropFirst()) {
                guard let club = shot.club, shot.lieValue != .green, shot.lieValue != .recovery else { continue }
                let yards = Geo.yards(shot.point, next.point)
                if yards >= 20 { samples.append((club, yards)) }
            }
        }
        return samples
    }
}

/// Where a ball was played from in Detailed mode. The "on green" marker has lie green and no club.
@Model
final class Shot {
    var holeNumber: Int
    var index: Int
    var club: String?
    var lie: String
    var latitude: Double
    var longitude: Double
    var yardsToGreen: Double?
    var round: Round?

    init(holeNumber: Int, index: Int, club: String?, lie: ShotLie, point: GeoPoint, yardsToGreen: Double?) {
        self.holeNumber = holeNumber
        self.index = index
        self.club = club
        self.lie = lie.rawValue
        self.latitude = point.lat
        self.longitude = point.lon
        self.yardsToGreen = yardsToGreen
    }

    var lieValue: ShotLie { ShotLie(rawValue: lie) ?? .rough }
    var point: GeoPoint { GeoPoint(lat: latitude, lon: longitude) }
}

@Model
final class Club {
    var name: String
    var sortOrder: Int
    var inBag: Bool

    init(name: String, sortOrder: Int, inBag: Bool = true) {
        self.name = name
        self.sortOrder = sortOrder
        self.inBag = inBag
    }

    static let defaultNames = ["Dr", "3W", "5W", "4H", "5i", "6i", "7i", "8i", "9i", "PW", "GW", "SW", "LW"]

    static func ensureDefaults(in context: ModelContext) {
        guard (try? context.fetchCount(FetchDescriptor<Club>())) == 0 else { return }
        for (i, name) in defaultNames.enumerated() {
            context.insert(Club(name: name, sortOrder: i))
        }
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

/// A score brought in from another app or a national handicap system (raw facts only).
@Model
final class ImportedScore {
    var playedOn: Date
    var courseName: String
    var teeName: String
    var adjustedGross: Int
    var courseRating: Double
    var slope: Int
    var pcc: Int
    var holeStrokes: [Int]
    var holePars: [Int]
    var importedAt: Date

    init(_ r: ImportedRound) {
        playedOn = r.date
        courseName = r.courseName
        teeName = r.teeName
        adjustedGross = r.adjustedGross
        courseRating = r.courseRating
        slope = r.slope
        pcc = r.pcc
        holeStrokes = r.holeStrokes
        holePars = r.holePars
        importedAt = .now
    }

    var data: ImportedRound {
        ImportedRound(date: playedOn, courseName: courseName, teeName: teeName, adjustedGross: adjustedGross,
                      courseRating: courseRating, slope: slope, pcc: pcc, holeStrokes: holeStrokes, holePars: holePars)
    }
}
