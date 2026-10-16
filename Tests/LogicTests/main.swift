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

// Side matches
let matchHoles = (0..<18).map { MatchHoleInfo(number: $0 + 1, par: pars[$0], strokeIndex: strokeIndexes[$0]) }
func setup(_ format: MatchFormat, basis: HandicapBasis = .gross, players: [MatchPlayerInfo]) -> MatchSetup {
    MatchSetup(format: format, basis: basis, allowance: .full, holes: matchHoles,
               courseRating: 72, slope: 113, players: players)
}
let sam = MatchPlayerInfo(key: "sam", name: "Sam", handicapIndex: 7)
let dave = MatchPlayerInfo(key: "dave", name: "Dave", handicapIndex: 9)
let tom = MatchPlayerInfo(key: "tom", name: "Tom", handicapIndex: 5)
func card(_ overPar: [Int]) -> [Int: Int] {
    Dictionary(uniqueKeysWithValues: (0..<overPar.count).map { ($0 + 1, pars[$0] + overPar[$0]) })
}

// Handicaps: match play plays off the lowest; stroke play is absolute
let mpNet = setup(.matchplay, basis: .net, players: [sam, dave])
check(MatchEngine.playingHandicaps(mpNet) == ["sam": 0, "dave": 2], "match play: Dave gets the 2-shot difference")
check(MatchEngine.playingHandicaps(setup(.stroke, basis: .net, players: [sam, dave])) == ["sam": 7, "dave": 9], "stroke play: full course handicaps")
var whsStroke = setup(.stroke, basis: .net, players: [sam])
whsStroke.allowance = .whs
check(MatchEngine.playingHandicaps(whsStroke)["sam"] == 7, "95% of 7 rounds to 7")
check(MatchEngine.playingHandicaps(setup(.stroke, players: [sam, dave])) == ["sam": 0, "dave": 0], "gross: no strokes")

// Match play, gross: Sam wins holes 1 and 2, then all halved → 2 UP thru 5
var mp = setup(.matchplay, players: [sam, dave])
var mpScores: ScoreTable = ["sam": card([0, 0, 0, 0, 0]), "dave": card([1, 1, 0, 0, 0])]
var out = MatchEngine.outcome(mp, mpScores)
check(out.status == "Sam 2 UP thru 5", "match play live status")
check(out.standings.first?.key == "sam" && out.standings.first?.value == "2 UP", "leader shown first")
check(!out.isFinished, "match play not finished thru 5")
// Sam wins 7 of the first 12 and halves the rest → 7 up with 6 to play → 7&6
mpScores = ["sam": card(Array(repeating: 0, count: 12)), "dave": card([1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0])]
out = MatchEngine.outcome(mp, mpScores)
check(out.status == "Sam 7&6", "closed out 7&6")
check(out.isFinished, "closed-out match is finished")
check(MatchEngine.pairResult(mp, mpScores, "sam", "dave") == .win, "Sam beat Dave")
check(MatchEngine.pairResult(mp, mpScores, "dave", "sam") == .loss, "Dave lost to Sam")

// Net match play: Dave's 2 strokes come on SI 1 and 2 (holes 5 and 12)
mp = mpNet
mpScores = ["sam": card(Array(repeating: 0, count: 18)), "dave": card(Array(repeating: 0, count: 18))]
check(MatchEngine.outcome(mp, mpScores).status == "Dave 2&1", "net: level gross scores, Dave wins his stroke holes (holes 5 and 12) and closes it out 2&1")

// Nassau: Sam wins the front by one, Dave the back by one, overall halved
let nassau = setup(.nassau, players: [sam, dave])
let front = [0, 0, 0, 0, 0, 0, 0, 0, 0], back = [0, 0, 0, 0, 0, 0, 0, 0, 0]
var samCard = front + back, daveCard = front + back
daveCard[0] = 1  // Sam wins hole 1
samCard[9] = 1   // Dave wins hole 10
out = MatchEngine.outcome(nassau, ["sam": card(samCard), "dave": card(daveCard)])
check(out.status == "Front: Sam 1 UP · Back: Dave 1 UP · Overall: Halved", "Nassau three bets")
check(out.isFinished, "Nassau finished after 18")
check(MatchEngine.pairResult(nassau, ["sam": card(samCard), "dave": card(daveCard)], "sam", "dave") == .halve, "Nassau overall halved")

// Skins: hole 1 tied (carry), Tom wins hole 2 for 2 skins, Sam wins hole 3
let skinsMatch = setup(.skins, players: [sam, dave, tom])
let skinScores: ScoreTable = ["sam": card([0, 0, -1]), "dave": card([0, 1, 0]), "tom": card([0, -1, 0])]
let skinResult = MatchEngine.skins(skinsMatch, skinScores)
check(skinResult.won == ["sam": 1, "dave": 0, "tom": 2], "skins carry over")
check(skinResult.carrying == 0, "nothing carrying after a won hole")
check(MatchEngine.skins(skinsMatch, ["sam": card([0]), "dave": card([0]), "tom": card([0])]).carrying == 1, "a tied hole carries")
check(MatchEngine.outcome(skinsMatch, skinScores).standings.first?.key == "tom", "most skins leads")

// Stableford: par = 2, birdie = 3, bogey = 1, double = 0
check(MatchEngine.stablefordPoints(par: 4, net: 4) == 2 && MatchEngine.stablefordPoints(par: 4, net: 3) == 3, "stableford points")
check(MatchEngine.stablefordPoints(par: 4, net: 6) == 0 && MatchEngine.stablefordPoints(par: 4, net: 9) == 0, "no negative points")
let stable = setup(.stableford, players: [sam, dave])
out = MatchEngine.outcome(stable, ["sam": card([0, -1]), "dave": card([1, 0])])
check(out.standings.map(\.value) == ["5 pts", "3 pts"], "stableford totals")

// Stroke play with ties
let strokeMatch = setup(.stroke, players: [sam, dave, tom])
out = MatchEngine.outcome(strokeMatch, ["sam": card([1, 0]), "dave": card([0, 1]), "tom": card([0, 0])])
check(out.standings.map(\.positionLabel) == ["1", "T2", "T2"], "stroke play ties share a position")
check(out.standings.first?.value == "E", "level par shows E")

// Rivalry record
let record = RivalryRecord.build([(.matchplay, .win), (.nassau, .halve), (.matchplay, .loss), (.stroke, .win)])
check(record.wins == 2 && record.losses == 1 && record.halves == 1 && record.played == 4, "rivalry totals")
check(record.byFormat[.matchplay]?.wins == 1 && record.byFormat[.matchplay]?.losses == 1, "rivalry by format")
check(record.form.first == .win, "form is most recent first")


// MARK: Tournaments

func tp(_ key: String, _ index: Double? = nil, team: Int? = nil) -> TourPlayer {
    TourPlayer(key: key, name: key.capitalized, handicapIndex: index, team: team)
}
func tour(_ scoring: TourScoring, _ mode: TourMode, basis: HandicapBasis = .gross, players: [TourPlayer]) -> TourSetup {
    TourSetup(scoring: scoring, mode: mode, basis: basis, holes: matchHoles, courseRating: 72, slope: 113, players: players)
}

check(TournamentEngine.seedOrder(8) == [1, 8, 4, 5, 2, 7, 3, 6], "knockout seeding: 1 v 8, 4 v 5, 2 v 7, 3 v 6")
check(TournamentEngine.formatPoints(7.5) == "7½" && TournamentEngine.formatPoints(0.5) == "½" && TournamentEngine.formatPoints(8) == "8", "half points")

// WHS allowances (course handicap = index on this course)
let netTour = tour(.stroke, .pairs, basis: .net, players: [tp("a", 10), tp("b", 20)])
check(TournamentEngine.sharedHandicap(netTour, netTour.players, format: .foursomes) == 15, "foursomes: 50% of combined")
check(TournamentEngine.sharedHandicap(netTour, netTour.players, format: .scramble) == 7, "scramble: 35% low + 15% high")
check(TournamentEngine.playerUnit(netTour, tp("a", 10), allowance: 0.95).handicap == 10, "individual stroke 95% of 10 rounds to 10")
check(TournamentEngine.playerUnit(netTour, tp("b", 20), allowance: 0.85).handicap == 17, "fourball stroke 85%")
let singlesGame = TournamentEngine.makeGame("s1", title: "", TournamentEngine.singleSide(netTour, tp("x", 5), matchPlay: true),
                                            TournamentEngine.singleSide(netTour, tp("y", 9), matchPlay: true))
check(singlesGame.a?.units.first?.handicap == 0 && singlesGame.b?.units.first?.handicap == 4, "singles: lower plays off zero")

// Match play game state
let ko = tour(.match, .individual, players: [tp("p1"), tp("p2"), tp("p3")])
let duel = TournamentEngine.makeGame("k1-2", title: "", TournamentEngine.singleSide(ko, tp("p2"), matchPlay: true),
                                     TournamentEngine.singleSide(ko, tp("p3"), matchPlay: true))
var tourScores: TourScores = ["k1-2": ["p2": card([-1, -1, -1]), "p3": card([0, 0, 0])]]
var gs = TournamentEngine.gameState(ko, tourScores, duel, suddenDeath: true)
check(gs.status == "3 UP" && gs.leader == 0 && !gs.finished, "3 up after 3")
tourScores["k1-2"] = ["p2": card([-1, -1, -1, -1, -1] + Array(repeating: 0, count: 13)), "p3": card(Array(repeating: 0, count: 18))]
gs = TournamentEngine.gameState(ko, tourScores, duel, suddenDeath: true)
check(gs.status == "5&4" && gs.winner == 0 && gs.finished, "five up with four to play is 5&4")

// Halved after 18: sudden death
var level = ["p2": card(Array(repeating: 0, count: 18)), "p3": card(Array(repeating: 0, count: 18))]
tourScores["k1-2"] = level
check(TournamentEngine.group(ko, tourScores, duel, suddenDeath: true).holes.last?.number == 19, "halved knockout adds the 19th")
check(TournamentEngine.extraHole(ko, 1).par == pars[0], "19th plays as the 1st")
level["p2"]?[19] = pars[0] - 1
level["p3"]?[19] = pars[0]
tourScores["k1-2"] = level
gs = TournamentEngine.gameState(ko, tourScores, duel, suddenDeath: true)
check(gs.winner == 0 && gs.status == "Won at the 19th", "won at the 19th")

// Bracket with a bye
var bracket = TournamentEngine.bracket(ko, [:])
check(bracket.rounds.count == 2 && bracket.rounds[0][0].isBye && bracket.rounds[0][0].winner?.key == "p1", "top seed gets the bye")
check(bracket.rounds[1][0].game.a?.key == "p1" && bracket.rounds[1][0].game.b == nil, "final waits for the semi")
bracket = TournamentEngine.bracket(ko, tourScores)
check(bracket.rounds[1][0].game.b?.key == "p2" && bracket.champion == nil, "semi winner goes through to the final")
check(TournamentEngine.scoringGroups(ko, tourScores).map(\.game) == ["k1-2", "k2-1"], "scorers see ready matches")

// Ryder Cup style
let cupPlayers = ["a1", "a2", "a3", "a4"].map { tp($0, team: 0) } + ["b1", "b2", "b3", "b4"].map { tp($0, team: 1) }
let cupTour = tour(.match, .teams, players: cupPlayers)
let games = TournamentEngine.cupGames(cupTour)
check(games.count == 8, "2 fourballs, 2 foursomes, 4 singles")
check(games.first { $0.key == "fs1" }.map { [$0.a?.key, $0.b?.key] } == ["a1+a3", "b2+b4"], "foursomes mix pairs and opponents")
let halved = card(Array(repeating: 0, count: 18))
let cupScores: TourScores = ["s1": ["a1": card(Array(repeating: -1, count: 10)), "b1": card(Array(repeating: 0, count: 10))],
                             "s2": ["a2": halved, "b2": halved]]
let cupResult = TournamentEngine.cup(cupTour, cupScores)
check(cupResult.points == [1.5, 0.5] && cupResult.total == 8 && cupResult.toWin == 4.5, "cup points and points to win")
check(cupResult.projected == [4.5, 3.5], "projected: unplayed matches count as halves")
check(cupResult.sessionPoints(.singles) == [1.5, 0.5] && cupResult.winner == nil, "session points")
check(TournamentEngine.problem(tour(.match, .teams, players: cupPlayers.dropLast())) != nil, "uneven teams are flagged")

// Stroke play leaderboard over two rounds, with movement
var two = tour(.stroke, .individual, players: [tp("p1"), tp("p2")])
two.rounds = 2
let strokeScores: TourScores = [
    "r1": ["p1": card([1, 1] + Array(repeating: 0, count: 16)), "p2": card(Array(repeating: 0, count: 18))],
    "r2": ["p1": card([-1, 0, 0]), "p2": card([1, 1])],
]
let twoBoard = TournamentEngine.leaderboard(two, strokeScores)
check(twoBoard.currentRound == 2 && twoBoard.rows.map(\.key) == ["p1", "p2"], "leader after two rounds")
check(twoBoard.rows[0].today == -1 && twoBoard.rows[0].thru == 3 && twoBoard.rows[0].total == 1, "today, thru and total")
check(twoBoard.rows[0].movement == 1 && twoBoard.rows[1].movement == -1, "movement since last round")

// Team stroke play, best 2 per hole
let teamTour = tour(.stroke, .teams, players: [tp("a1", team: 0), tp("a2", team: 0), tp("a3", team: 0), tp("b1", team: 1), tp("b2", team: 1)])
let teamBoard = TournamentEngine.leaderboard(teamTour, ["r1": ["a1": card([-1]), "a2": card([0]), "a3": card([2]), "b1": card([0]), "b2": card([0])]])
check(teamBoard.rows.map(\.total) == [-1, 0], "best 2 scores count for each team")

// Fourball pairs: best ball
let fbTour = tour(.stroke, .pairs, players: [tp("a"), tp("b"), tp("c"), tp("d")])
let fbBoard = TournamentEngine.leaderboard(fbTour, ["r1": ["a": card([1, 0]), "b": card([0, 2]), "c": card([1, 1]), "d": card([1, 1])]])
check(fbBoard.rows.first?.key == "a+b" && fbBoard.rows.first?.total == 0, "fourball takes the better ball")

// Feed
let feedItems = TournamentEngine.feed(two, strokeScores, events: [
    TourScoreEvent(game: "r2", unit: "p1", hole: 1, strokes: pars[0] - 1, time: Date(timeIntervalSince1970: 10)),
])
check(feedItems.first?.text == "birdie on 1" && feedItems.first?.name == "P1", "feed shows birdies")


// MARK: Smart caddie

let emptyModel = PlayerModel.build([])
check(close(emptyModel.expected(.fairway, 150), StrokesGained.expected(.fairway, 150)), "no data: the caddie uses the baseline")

let oneHole = HoleData(par: 4, strokeIndex: 1, strokes: 4, putts: 2, firstPuttFeet: 12, fairway: .hit, green: .hit,
                       upAndDown: nil, penalties: 0, shots: [ShotData(lie: .tee, distance: 400), ShotData(lie: .fairway, distance: 150)])
let builtModel = PlayerModel.build([RoundData(date: .now, courseRating: 72, slope: 113, handicapIndex: nil, holes: [oneHole])])
check(builtModel.shotCount == 2 && close(builtModel.overall, (0.01 + 0.055) / 2), "player model: strokes to hole out against baseline")

let bagYards = Caddie.yardages(bag: ["Dr", "7i", "8i", "PW"],
                               measured: [ClubDistance(club: "7i", count: 5, average: 158, median: 157, spread: 6),
                                          ClubDistance(club: "8i", count: 2, average: 170, median: 170, spread: 6)])
check(bagYards.first { $0.club == "7i" } == ClubYardage(club: "7i", yards: 157, fromData: true), "own median once a club has 3 shots")
check(bagYards.first { $0.club == "8i" }?.fromData == false, "typical yardage until then")

let fullBag = Caddie.yardages(bag: Array(Caddie.typicalYards.keys), measured: [])
check(Caddie.club(for: 158, clubs: Caddie.usable(fullBag, lie: .fairway))?.club == "7i", "158 yards is a 7 iron")
check(Caddie.club(for: 300, clubs: Caddie.usable(fullBag, lie: .fairway))?.club == "3W", "too far: longest club, no driver off the deck")

var layupModel = PlayerModel.empty
layupModel.overall = 0.2
layupModel.shotCount = 60
for i in layupModel.bands.indices {
    if layupModel.bands[i].lower == 210 { layupModel.bands[i].shots = 30; layupModel.bands[i].totalDiff = 18 }
    if layupModel.bands[i].lower == 90 { layupModel.bands[i].shots = 30; layupModel.bands[i].totalDiff = -9 }
}
let layupAdvice = Caddie.advise(distance: 225, lie: .fairway, model: layupModel, clubs: fullBag)
check(layupAdvice.recommendsLayup && layupAdvice.layup?.club == "PW", "weak from 225, strong from 100: lay up with PW")
check(layupModel.favouriteBand?.lower == 90, "favourite distance is the 90–120 band")
check(!Caddie.advise(distance: 225, lie: .fairway, model: emptyModel, clubs: fullBag).recommendsLayup, "baseline player goes for it")

// Practice plan: lots of 3-putts from 10 ft
let puttHole = HoleData(par: 4, strokeIndex: 1, strokes: 5, putts: 3, firstPuttFeet: 10, fairway: .hit, green: .hit,
                        upAndDown: nil, penalties: 0)
let puttRound = RoundData(date: .now, courseRating: 72, slope: 113, handicapIndex: nil, holes: Array(repeating: puttHole, count: 18))
let plan = PracticePlan.build([puttRound])
check(plan.first?.category == .putting && plan.first?.focus == "Putts from 7–20 ft", "practice plan finds the putting leak")
check(PracticePlan.build([]).isEmpty, "no data, no plan")


// MARK: Importing scores

check(ImportedRound(date: .now, courseName: "A", teeName: "", adjustedGross: 78, courseRating: 69.7, slope: 118).differential == 7.9,
      "differential: 113/118 × (78 − 69.7) = 7.9")
check(ImportedRound(date: .now, courseName: "A", teeName: "", adjustedGross: 80, courseRating: 70.8, slope: 128, pcc: -1).differential == 9.0,
      "differential with PCC −1")

let csv = """
Date,Course,Tee,Adj Gross,Course Rating,Slope,PCC,Holes,Pars
08/10/2026,"Links, North",Blue,78,69.7,118,0,,
2026-09-15,Hill Club,Blue,84,70.8,128,0,4 4 1 5 3 3 3 5 4 7 7 7 5 3 4 3 4 4,4 4 3 4 3 4 3 3 4 5 3 5 4 3 4 3 4 4
31/02/2026,Bad,Blue,80,70,120,0,,
"""
let parsed = ScoreImport.parse(csv)
check(parsed.rounds.count == 2 && parsed.problems.count == 1, "CSV: two good rows, one bad date")
check(parsed.rounds.first?.courseName == "Links, North", "CSV: quoted course name with a comma")
check(parsed.rounds.last?.holeStrokes.count == 18 && parsed.rounds.last?.holePars.reduce(0, +) == 67, "CSV: hole-by-hole card")
let tsv = "date\tcourse\tscore\trating\tslope\n12/06/2023\tShort Course\t75\t65.9\t112\n"
check(ScoreImport.parse(tsv).rounds.first?.adjustedGross == 75, "pasted from a spreadsheet (tabs)")
check(ScoreImport.parse("hello\n1,2").rounds.isEmpty, "no header, nothing imported")
check(ScoreImport.newOnly(parsed.rounds, existing: [parsed.rounds[0]]).count == 1, "already imported scores are skipped")

// 20 imported differentials: the best 8 average to the index
let diffs = [11.9, 11.8, 12.7, 10.6, 7.5, 7.6, 7.2, 9.4, 13.8, 17.2, 12.0, 9.0, 9.0, 10.8, 8.9, 10.8, 11.7, 12.7, 9.9, 7.9]
let importedTwenty = diffs.enumerated().map { i, d in
    // slope 113, rating 70: the differential is just score − 70 (scores are whole, so use PCC to hit .x)
    ImportedRound(date: Date(timeIntervalSince1970: Double(i) * 86_400), courseName: "C\(i)", teeName: "",
                  adjustedGross: 90, courseRating: 90 - d, slope: 113)
}
check(close(Handicap.currentIndex([], imported: importedTwenty), 8.3), "best 8 of 20 imported differentials: 8.3")


// MARK: Course catalog

let goodTee = CatalogTee(name: "Blue", gender: "male", rating: 69.7, slope: 118, par: 70, yards: 6100,
                         holes: (0..<18).map { CatalogHole(par: pars[$0], yards: 300 + $0, si: strokeIndexes[$0]) })
let goodHoles = CourseCatalog.holes(for: goodTee)
check(!goodHoles.strokeIndexGuessed && goodHoles.holes.map(\.strokeIndex) == strokeIndexes, "catalog: stroke indexes kept")
check(goodHoles.holes[3].par == 5 && goodHoles.holes[3].yards == 303, "catalog: par and yards per hole")

var noSI = goodTee
noSI.holes = (0..<18).map { CatalogHole(par: 4, yards: 300 + $0 * 10, si: nil) }
let guessed = CourseCatalog.holes(for: noSI)
check(guessed.strokeIndexGuessed && Set(guessed.holes.map(\.strokeIndex)) == Set(1...18), "catalog: missing SI is guessed, each used once")
check(guessed.holes[8].strokeIndex == 1 && guessed.holes[17].strokeIndex == 2, "catalog: longest front-nine hole is SI 1, back nine SI 2")
check(CourseCatalog.holes(for: CatalogTee(name: "x", gender: "male", holes: [])).holes.count == 18, "catalog: no holes gives an 18-hole card to fill in")

let club = CatalogCourse(id: 1, club: "Royal Auckland and Grange", course: "Grange/Middlemore", tees: [goodTee])
check(club.displayName == "Royal Auckland and Grange – Grange/Middlemore", "catalog: club and course name")
check(CatalogCourse(id: 2, club: "Chisholm Links", course: "Chisholm Links", tees: []).displayName == "Chisholm Links", "catalog: same club and course name once")

print(failures == 0 ? "\nAll logic tests passed." : "\n\(failures) logic test(s) failed.")
exit(failures == 0 ? 0 : 1)
