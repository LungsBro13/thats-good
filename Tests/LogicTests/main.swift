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

print(failures == 0 ? "\nAll logic tests passed." : "\n\(failures) logic test(s) failed.")
exit(failures == 0 ? 0 : 1)
