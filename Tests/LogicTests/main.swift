import Foundation

// Plain test runner for the Logic/ folder. CI compiles it with:
//   swiftc ThatsGood/Logic/*.swift Tests/LogicTests/main.swift -o logic-tests && ./logic-tests

var failures = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   \(message)")
    } else {
        print("FAIL \(message)")
        failures += 1
    }
}

func close(_ a: Double?, _ b: Double, _ tolerance: Double = 0.0001) -> Bool {
    guard let a else { return false }
    return abs(a - b) < tolerance
}

let pars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
let strokeIndexes = [7, 3, 15, 11, 1, 9, 17, 5, 13, 8, 16, 2, 12, 6, 10, 18, 4, 14]

func makeRound(strokes: [Int], index: Double? = nil, rating: Double = 72.0, slope: Int = 113, daysAgo: Double = 0) -> RoundData {
    let holes = (0..<18).map { i in
        HoleData(par: pars[i], strokeIndex: strokeIndexes[i], strokes: strokes[i], putts: 2,
                 firstPuttFeet: nil, fairway: nil, green: nil, upAndDown: nil, penalties: 0)
    }
    return RoundData(date: Date(timeIntervalSince1970: 1_700_000_000 - daysAgo * 86_400),
                     courseRating: rating, slope: slope, handicapIndex: index, holes: holes)
}

// Course handicap
check(Handicap.courseHandicap(index: 7.2, slope: 128, rating: 71.8, par: 72) == 8, "course handicap 7.2 on slope 128 is 8")
check(Handicap.courseHandicap(index: 0, slope: 113, rating: 72, par: 72) == 0, "scratch on a neutral course is 0")

// Strokes received
check(Handicap.strokesReceived(courseHandicap: 7, strokeIndex: 7) == 1, "CH 7 gets a stroke on SI 7")
check(Handicap.strokesReceived(courseHandicap: 7, strokeIndex: 8) == 0, "CH 7 gets no stroke on SI 8")
check(Handicap.strokesReceived(courseHandicap: 20, strokeIndex: 2) == 2, "CH 20 gets 2 strokes on SI 2")
check(Handicap.strokesReceived(courseHandicap: 20, strokeIndex: 3) == 1, "CH 20 gets 1 stroke on SI 3")
check(Handicap.strokesReceived(courseHandicap: -2, strokeIndex: 17) == -1, "plus 2 gives a stroke back on SI 17")
check(Handicap.strokesReceived(courseHandicap: -2, strokeIndex: 16) == 0, "plus 2 gives nothing back on SI 16")

// Adjusted gross score and differential
let bogeyRound = makeRound(strokes: pars.map { $0 + 1 })
check(Handicap.adjustedGrossScore(bogeyRound) == 90, "all bogeys is 90")
check(close(Handicap.scoreDifferential(bogeyRound), 18.0), "90 on 72.0 / 113 is a differential of 18.0")

var blowUp = pars.map { $0 + 1 }
blowUp[0] = 12  // par 4: capped at 9 with no index
check(Handicap.adjustedGrossScore(makeRound(strokes: blowUp)) == 94, "no index: hole capped at par + 5")
// With index 0: par 4 cap is double bogey = 6
check(Handicap.adjustedGrossScore(makeRound(strokes: blowUp, index: 0)) == 91, "scratch: hole capped at double bogey")

check(close(Handicap.scoreDifferential(makeRound(strokes: pars.map { $0 + 1 }, rating: 71.8, slope: 128)), 16.1),
      "90 on 71.8 / 128 is 16.1")

// Index table
check(Handicap.index(fromDifferentials: [18, 20]) == nil, "no index with 2 rounds")
check(close(Handicap.index(fromDifferentials: [18, 20, 22]), 16.0), "3 rounds: lowest 1 minus 2")
check(close(Handicap.index(fromDifferentials: [10, 12, 14, 16, 18, 20]), 10.0), "6 rounds: average of lowest 2 minus 1")
let twenty = (1...20).map(Double.init)
check(close(Handicap.index(fromDifferentials: twenty), 4.5), "20 rounds: average of lowest 8")
check(close(Handicap.index(fromDifferentials: twenty + [0, 0, 0]), 4.5), "only the most recent 20 count")
check(Handicap.index(fromDifferentials: [80, 80, 80]) == Handicap.maxIndex, "index is capped at 54")

// History ordering
let rounds = [
    makeRound(strokes: pars.map { $0 + 2 }, daysAgo: 30),
    makeRound(strokes: pars.map { $0 + 1 }, daysAgo: 20),
    makeRound(strokes: pars, daysAgo: 10),
]
let history = Handicap.history(rounds)
check(history.count == 1, "history has a point once there are 3 rounds")
check(close(history.last?.index, -2.0), "best differential 0 minus 2")

// Stats
var statHoles: [HoleData] = []
for i in 0..<18 {
    statHoles.append(HoleData(
        par: pars[i], strokeIndex: strokeIndexes[i], strokes: pars[i] + (i % 3 == 0 ? 1 : 0),
        putts: i == 0 ? 3 : (i == 1 ? 1 : 2), firstPuttFeet: 20,
        fairway: pars[i] >= 4 ? (i % 2 == 0 ? .hit : .left) : nil,
        green: i < 9 ? .hit : .short, upAndDown: i < 9 ? nil : (i % 2 == 0),
        penalties: i == 5 ? 1 : 0))
}
let statRound = RoundData(date: Date(), courseRating: 72, slope: 113, handicapIndex: nil, holes: statHoles)
let summary = RoundStats.summarize([statRound])
check(summary.roundCount == 1, "stats count rounds")
check(summary.holeCount == 18, "stats count holes")
check(summary.fairwayAttempts == 14, "14 fairway attempts on a par 72 with four par 3s")
check(summary.greenHits == 9 && summary.greenAttempts == 18, "9 of 18 greens")
check(close(summary.girPct, 0.5), "GIR is 50%")
check(close(summary.greenMissShare(.short), 1.0), "all misses were short")
check(summary.upAndDownAttempts == 9, "9 up-and-down chances")
check(summary.threePutts == 1 && summary.onePutts == 1, "one 3-putt and one 1-putt")
check(summary.totalPutts == 36, "36 putts")
check(summary.totalPenalties == 1, "one penalty")
check(close(summary.averageScore, 78), "6 bogeys on par 72 is 78")
check(close(summary.mixPerRound.bogeys, 6), "6 bogeys per round")

// Geo
let origin = GeoPoint(lat: 56.3433, lon: -2.8030)
let north150 = Geo.offset(origin, bearing: 0, meters: 150 / Geo.yardsPerMeter)
check(abs(Geo.yards(origin, north150) - 150) < 0.5, "offset then distance round-trips 150 yards")
check(abs(Geo.bearing(origin, north150)) < 0.5 || abs(Geo.bearing(origin, north150) - 360) < 0.5, "due north bearing is 0")
let east = Geo.offset(origin, bearing: 90, meters: 100)
check(abs(Geo.bearing(origin, east) - 90) < 0.5, "due east bearing is 90")

// A square green 20 m across, centred 150 yards north
let greenCenter = north150
let greenOutline = [0.0, 90, 180, 270].map { Geo.offset(greenCenter, bearing: $0, meters: 10) }
let fmb = Geo.frontMiddleBack(from: origin, greenCenter: greenCenter, outline: greenOutline)
check(abs(fmb.middle - 150) < 0.5, "middle of green is 150")
check(abs((fmb.front ?? 0) - (150 - 10.94)) < 0.6, "front is about 11 yards short of the middle")
check(abs((fmb.back ?? 0) - (150 + 10.94)) < 0.6, "back is about 11 yards past the middle")
check(Geo.contains(greenOutline, greenCenter), "green contains its centre")
check(!Geo.contains(greenOutline, origin), "green does not contain the tee")

// Course geo
var course = CourseGeo(holes: [], features: [MapFeature(kind: .green, points: greenOutline)])
check(course.lie(at: greenCenter) == .green, "lie on the green")
check(course.lie(at: origin) == .rough, "lie off any mapped area is rough")
check(CourseGeo().lie(at: origin) == nil, "no lie guess without map data")
course.setGreen(hole: 3, at: Geo.offset(greenCenter, bearing: 45, meters: 3))
check(course.hole(3)?.greenOutline.count == 4, "tapping inside a mapped green snaps to it")
check(abs(Geo.meters(course.hole(3)!.greenCenter, greenCenter)) < 1, "snapped green centre is the polygon centre")

// OSM parsing
let greenGeometry = greenOutline.map { p in "{\"lat\":\(p.lat),\"lon\":\(p.lon)}" }.joined(separator: ",")
let osmJSON = """
{"elements":[
 {"type":"way","id":1,"tags":{"golf":"hole","ref":"1","par":"4"},
  "geometry":[{"lat":\(origin.lat),"lon":\(origin.lon)},{"lat":\(greenCenter.lat),"lon":\(greenCenter.lon)}]},
 {"type":"way","id":2,"tags":{"golf":"green"},
  "geometry":[\(greenGeometry)]},
 {"type":"way","id":3,"tags":{"natural":"water"},
  "geometry":[{"lat":1,"lon":1},{"lat":1,"lon":2},{"lat":2,"lon":2}]},
 {"type":"node","id":4}
]}
"""
if let parsed = try? OSMParser.parse(Data(osmJSON.utf8)) {
    check(parsed.holes.count == 1 && parsed.holes[0].number == 1 && parsed.holes[0].par == 4, "OSM hole 1 par 4 parsed")
    check(parsed.holes[0].greenOutline.count == 4, "OSM hole matched to its green")
    check(parsed.features.count == 2, "OSM green and water kept as areas")
} else {
    check(false, "OSM JSON parses")
}

// Strokes gained
check(close(StrokesGained.expected(.green, 10), 1.61), "baseline: 10 ft putt is 1.61")
check(close(StrokesGained.expected(.fairway, 150), 2.945), "baseline interpolates between 140 and 160")
check(close(StrokesGained.expected(.tee, 80), StrokesGained.expected(.fairway, 80)), "short tee shots use the fairway table")

// Par 4: drive from 400 to the fairway at 140, approach to 20 ft, two putts
var sgHole = HoleData(par: 4, strokeIndex: 1, strokes: 4, putts: 2, firstPuttFeet: 20,
                      fairway: .hit, green: .hit, upAndDown: nil, penalties: 0,
                      shots: [ShotData(lie: .tee, distance: 400), ShotData(lie: .fairway, distance: 140)])
var sg = StrokesGained.holeValues(sgHole)
check(close(sg[.offTheTee], 3.99 - 2.91 - 1), "drive SG = 0.08")
check(close(sg[.approach], 2.91 - 1.87 - 1), "approach SG = 0.04")
check(close(sg[.putting], 1.87 - 2), "two putts from 20 ft SG = -0.13")
sgHole.penalties = 1
sg = StrokesGained.holeValues(sgHole)
check(close(sg[.offTheTee], 3.99 - 2.91 - 1 - 1), "penalty comes off the tee shot")

// Chip-in from 15 yards in the rough
let chipIn = HoleData(par: 4, strokeIndex: 1, strokes: 3, putts: 0, firstPuttFeet: nil,
                      fairway: nil, green: .short, upAndDown: true, penalties: 0,
                      shots: [ShotData(lie: .rough, distance: 15)])
check(close(StrokesGained.holeValues(chipIn)[.aroundGreen], StrokesGained.expected(.rough, 15) - 1), "chip-in SG")

// Quick mode: putting only
let quickHole = HoleData(par: 3, strokeIndex: 1, strokes: 3, putts: 1, firstPuttFeet: 10,
                         fairway: nil, green: .hit, upAndDown: nil, penalties: 0)
let quickSG = StrokesGained.holeValues(quickHole)
check(quickSG.count == 1 && close(quickSG[.putting], 0.61), "Quick mode gives putting SG only")
let sgSummary = StrokesGained.summarize([RoundData(date: Date(), courseRating: 72, slope: 113, handicapIndex: nil, holes: [quickHole, quickHole])])
check(close(sgSummary.perRound(.putting), 1.22) && sgSummary.perRound(.approach) == nil, "SG summary per round")

// Club stats
let clubSamples: [(club: String, yards: Double)] = [("7i", 150), ("7i", 160), ("7i", 170), ("Dr", 250), ("Dr", 260)]
let clubs = ClubStats.summarize(clubSamples, order: ["Dr", "7i"])
check(clubs.map(\.club) == ["Dr", "7i"], "clubs follow bag order")
check(close(clubs[1].average, 160) && close(clubs[1].median, 160) && clubs[1].count == 3, "7i average and median")
check(close(clubs[0].median, 255), "even-count median")
check(close(clubs[1].spread, (200.0 / 3).squareRoot()), "spread is the standard deviation")

// Friends' progress and leaderboards
let progressRounds = (0..<8).map { i in
    makeRound(strokes: pars.map { $0 + (i < 4 ? 1 : 0) }, daysAgo: Double(200 - i * 20))  // 4 bogey rounds, then 4 level par
}
let now = Date(timeIntervalSince1970: 1_700_000_000)
let progress = PlayerProgress.compute(progressRounds, now: now, periodDays: 90)
check(progress.roundCount == 8, "progress counts rounds")
check(progress.bestRound == 72, "best round is level par")
check(close(progress.handicap, 0), "8 rounds: lowest 2 differentials (0) average 0")
// 90 days ago (cutoff at day 90): rounds at 200,180,160,140,120,100 days ago are older -> 4 bogey + 2 par
check(close(progress.handicapChange, 0 - (-1.0)), "handicap change is now minus 90 days ago")
check(progress.trend.count == 6, "trend has a point per round once 3 are played")

let board = Leaderboard.rank(["me": progress,
                              "tom": PlayerProgress(handicap: 4.8, handicapChange: 0.2, averageScore: 75, averageScoreChange: nil, bestRound: 70, roundCount: 30, trend: []),
                              "new": PlayerProgress(handicap: nil, handicapChange: nil, averageScore: nil, averageScoreChange: nil, bestRound: nil, roundCount: 0, trend: [])],
                             by: .handicap)
check(board.map(\.id) == ["me", "tom"], "handicap board: lowest first, players without one left out")
check(Leaderboard.rank(["a": progress, "b": PlayerProgress(handicap: 1, handicapChange: nil, averageScore: nil, averageScoreChange: nil, bestRound: 75, roundCount: 30, trend: [])], by: .rounds).first?.id == "b",
      "rounds board: most first")

// Server URL clean-up
check(ServerURL.normalize("https://abcdefghijklmnop.supabase.co")?.absoluteString == "https://abcdefghijklmnop.supabase.co", "project URL kept")
check(ServerURL.normalize("  https://abcdefghijklmnop.supabase.co/rest/v1/ ")?.absoluteString == "https://abcdefghijklmnop.supabase.co", "extra path and spaces removed")
check(ServerURL.normalize("abcdefghijklmnop.supabase.co")?.absoluteString == "https://abcdefghijklmnop.supabase.co", "https added")
check(ServerURL.normalize("https://supabase.com/dashboard/project/abcdefghijklmnop/settings/api-keys")?.absoluteString == "https://abcdefghijklmnop.supabase.co", "dashboard link turned into the project URL")
check(ServerURL.normalize("https://supabase.com/dashboard") == nil, "the website itself is rejected")
check(ServerURL.normalize("hello") == nil, "junk is rejected")

print(failures == 0 ? "\nAll logic tests passed." : "\n\(failures) logic test(s) failed.")
exit(failures == 0 ? 0 : 1)
