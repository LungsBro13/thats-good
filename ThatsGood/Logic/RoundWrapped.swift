import Foundation

/// One slide of Round Wrapped: a short story of the round, told with big numbers.
struct WrappedSlide: Identifiable, Equatable {
    enum Kind: String {
        case headline, streak, shotOfTheDay, birdies, greens, fairways, putting, scrambling,
             damage, strokesGained, nines, handicap, outro
    }

    var kind: Kind
    var eyebrow: String     // small label at the top, e.g. "YOUR ROUND"
    var big: String         // the big number or words
    var countTo: Int?       // when set, the big number counts up to this
    var caption: String
    var detail: String?
    var id: String { kind.rawValue }
}

/// What Round Wrapped needs to know.
struct WrappedContext {
    var round: RoundData
    var courseName: String
    var previous: [RoundData] = []  // earlier finished rounds, newest first
    var handicapBefore: Double?
    var handicapAfter: Double?
}

/// A plain written summary of the round, shown after the slides.
struct RoundReport: Equatable {
    var good: [String]
    var costly: [String]
    var focus: String
    var drill: String?
}

enum RoundWrapped {
    static let maxSlides = 10

    // MARK: Helpers

    static func number(_ hole: HoleData, _ index: Int) -> Int { hole.number > 0 ? hole.number : index + 1 }

    static func scoreName(_ hole: HoleData) -> String {
        if hole.strokes == 1 { return "hole in one" }
        switch hole.strokes - hole.par {
        case ...(-3): return "albatross"
        case -2: return "eagle"
        case -1: return "birdie"
        case 0: return "par"
        case 1: return "bogey"
        case 2: return "double"
        default: return "+\(hole.strokes - hole.par)"
        }
    }

    /// "3", "3 and 7", "3, 7 and 12"
    static func list(_ numbers: [Int]) -> String {
        let s = numbers.map(String.init)
        guard s.count > 1 else { return s.first ?? "" }
        return s.dropLast().joined(separator: ", ") + " and " + s.last!
    }

    static func ordinal(_ n: Int) -> String { TournamentEngine.ordinal(n) }

    static func plural(_ n: Int, _ word: String, _ many: String? = nil) -> String {
        "\(n) \(n == 1 ? word : (many ?? word + "s"))"
    }

    /// The longest run of par or better, as (first index, length).
    static func bestRun(_ holes: [HoleData]) -> (start: Int, length: Int)? {
        var best: (Int, Int)?
        var start = 0, length = 0
        for (i, h) in holes.enumerated() {
            if h.strokes <= h.par {
                if length == 0 { start = i }
                length += 1
                if length > (best?.1 ?? 0) { best = (start, length) }
            } else {
                length = 0
            }
        }
        return best.map { (start: $0.0, length: $0.1) }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private static func recent(_ ctx: WrappedContext) -> [RoundData] { Array(ctx.previous.prefix(10)) }

    // MARK: Slides

    static func slides(_ ctx: WrappedContext) -> [WrappedSlide] {
        let round = ctx.round
        let holes = round.holes
        guard !holes.isEmpty else { return [] }
        let stats = RoundStats.summarize([round])
        var slides: [WrappedSlide] = [headline(ctx)]

        // Hot streak
        if let run = bestRun(holes), run.length >= 3 {
            let part = Array(holes[run.start..<(run.start + run.length)])
            let first = number(holes[run.start], run.start), last = number(holes[run.start + run.length - 1], run.start + run.length - 1)
            slides.append(WrappedSlide(kind: .streak, eyebrow: "HOT STREAK", big: "\(first)–\(last)", countTo: nil,
                                       caption: "Par or better on \(run.length) holes in a row",
                                       detail: run.length <= 5 ? part.map(scoreName).joined(separator: ", ").capitalizedFirst : nil))
        } else {
            // Best 3-hole stretch, if it was level par or better.
            var best: (Int, Int)?
            for i in 0..<max(0, holes.count - 2) {
                let sum = holes[i..<(i + 3)].reduce(0) { $0 + $1.strokes - $1.par }
                if best == nil || sum < best!.1 { best = (i, sum) }
            }
            if let b = best, b.1 <= 0 {
                let i = b.0, sum = b.1
                slides.append(WrappedSlide(kind: .streak, eyebrow: "BEST STRETCH",
                                           big: "\(number(holes[i], i))–\(number(holes[i + 2], i + 2))", countTo: nil,
                                           caption: "\(MatchEngine.toParText(sum)) over 3 holes",
                                           detail: holes[i..<(i + 3)].map(scoreName).joined(separator: ", ").capitalizedFirst))
            }
        }

        // Shot of the day: hole in one or eagle
        if let i = holes.firstIndex(where: { $0.strokes == 1 }) ?? holes.firstIndex(where: { $0.strokes - $0.par <= -2 }) {
            let h = holes[i]
            slides.append(WrappedSlide(kind: .shotOfTheDay, eyebrow: "SHOT OF THE DAY", big: "Hole \(number(h, i))", countTo: nil,
                                       caption: h.strokes == 1 ? "HOLE IN ONE!" : "\(scoreName(h).capitalized) on the par \(h.par)",
                                       detail: h.strokes == 1 ? "Drinks are on you." : nil))
        }

        // Birdies
        let birdieHoles = holes.enumerated().filter { $0.element.strokes - $0.element.par == -1 }
        if !birdieHoles.isEmpty {
            let numbers = birdieHoles.map { number($0.element, $0.offset) }
            let hardest = birdieHoles.min { $0.element.strokeIndex < $1.element.strokeIndex }!
            var detail = "On \(numbers.count == 1 ? "hole " : "")\(list(numbers))."
            if hardest.element.strokeIndex <= 3 {
                detail += " Including the \(hardest.element.strokeIndex == 1 ? "hardest hole" : "\(ordinal(hardest.element.strokeIndex)) hardest hole") on the course."
            }
            if let avg = average(recent(ctx).map { r in Double(r.holes.filter { $0.strokes - $0.par == -1 }.count) }),
               Double(numbers.count) >= avg + 1 {
                detail += " You average \(String(format: "%.1f", avg))."
            }
            slides.append(WrappedSlide(kind: .birdies, eyebrow: "BIRDIES", big: "\(numbers.count)", countTo: numbers.count,
                                       caption: numbers.count == 1 ? "birdie" : "birdies", detail: detail))
        }

        // Greens in regulation, against the last round that has them
        if stats.greenAttempts > 0 {
            var detail = "of \(stats.greenAttempts)"
            if let last = ctx.previous.first(where: { RoundStats.summarize([$0]).greenAttempts > 0 }) {
                let diff = stats.greenHits - RoundStats.summarize([last]).greenHits
                detail += diff == 0 ? " · same as last round" : " · \(abs(diff)) \(diff > 0 ? "more" : "fewer") than last round"
            }
            slides.append(WrappedSlide(kind: .greens, eyebrow: "GREENS", big: "\(stats.greenHits)", countTo: stats.greenHits,
                                       caption: "greens in regulation", detail: detail))
        }

        // Fairways
        if stats.fairwayAttempts > 0, let pct = stats.fairwayPct {
            var detail = "of \(stats.fairwayAttempts)"
            let past = recent(ctx).compactMap { RoundStats.summarize([$0]).fairwayPct }
            if past.count >= 3, let best = past.max(), pct > best {
                detail += " · your best in \(past.count) rounds"
            } else if let l = stats.fairwayLeftPct, let r = stats.fairwayRightPct, l + r > 0 {
                detail += " · misses \(l > r ? "left" : (r > l ? "right" : "both ways"))"
            }
            slides.append(WrappedSlide(kind: .fairways, eyebrow: "OFF THE TEE", big: "\(stats.fairwayHits)", countTo: stats.fairwayHits,
                                       caption: "fairways hit", detail: detail))
        }

        // Putting
        if stats.totalPutts > 0 {
            var parts: [String] = []
            if stats.onePutts > 0 { parts.append(plural(stats.onePutts, "one-putt")) }
            if stats.threePutts > 0 { parts.append(plural(stats.threePutts, "three-putt")) }
            if let avg = average(recent(ctx).map { Double($0.holes.reduce(0) { $0 + $1.putts }) }), recent(ctx).count >= 3 {
                let diff = Int((avg - Double(stats.totalPutts)).rounded())
                if diff != 0 { parts.append("\(abs(diff)) \(diff > 0 ? "fewer" : "more") than your average") }
            }
            slides.append(WrappedSlide(kind: .putting, eyebrow: "ON THE GREENS", big: "\(stats.totalPutts)", countTo: stats.totalPutts,
                                       caption: "putts", detail: parts.isEmpty ? nil : parts.joined(separator: " · ")))
        }

        // Scrambling
        if stats.upAndDownAttempts >= 2 && stats.upAndDownMade >= 1 {
            slides.append(WrappedSlide(kind: .scrambling, eyebrow: "SCRAMBLING", big: "\(stats.upAndDownMade)/\(stats.upAndDownAttempts)",
                                       countTo: nil, caption: "up and downs", detail: stats.upAndDownMade * 2 >= stats.upAndDownAttempts
                                           ? "Great short game." : "Every one saved is a shot back."))
        }

        // Shots lost to doubles
        let doubles = holes.enumerated().filter { $0.element.strokes - $0.element.par >= 2 }
        if !doubles.isEmpty {
            let lost = doubles.reduce(0) { $0 + $1.element.strokes - $1.element.par - 1 }
            slides.append(WrappedSlide(kind: .damage, eyebrow: "SHOTS TO SAVE", big: "\(lost)", countTo: lost,
                                       caption: "shot\(lost == 1 ? "" : "s") lost to \(plural(doubles.count, "double bogey", "double bogeys")) or worse",
                                       detail: "Hole\(doubles.count == 1 ? "" : "s") \(list(doubles.map { number($0.element, $0.offset) })). Turn them into bogeys and you shoot \(round.strokes - lost)."))
        }

        // Strokes gained, against the player's own average
        let mine = StrokesGained.summarize([round])
        let theirs = StrokesGained.summarize(Array(ctx.previous.prefix(20)))
        let gains = SGCategory.allCases.compactMap { c -> (SGCategory, Double)? in
            guard let now = mine.perRound(c), let usual = theirs.perRound(c), (theirs.roundsWithData[c] ?? 0) >= 3 else { return nil }
            return (c, now - usual)
        }
        if let best = gains.max(by: { $0.1 < $1.1 }), best.1 >= 0.5 {
            slides.append(WrappedSlide(kind: .strokesGained, eyebrow: "STRONGEST AREA", big: String(format: "+%.1f", best.1), countTo: nil,
                                       caption: "\(best.0.label) against your average", detail: "Shots gained compared with your usual round."))
        }

        // Front and back nine
        if holes.count == 18 {
            let front = holes.prefix(9).reduce(0) { $0 + $1.strokes }, back = holes.suffix(9).reduce(0) { $0 + $1.strokes }
            if abs(front - back) >= 3 {
                let backBetter = back < front
                slides.append(WrappedSlide(kind: .nines, eyebrow: backBetter ? "STRONG FINISH" : "FAST START",
                                           big: "\(min(front, back))", countTo: min(front, back),
                                           caption: "on the \(backBetter ? "back" : "front") nine",
                                           detail: "\(abs(front - back)) better than the \(backBetter ? "front" : "back")."))
            }
        }

        // Handicap
        if let before = ctx.handicapBefore, let after = ctx.handicapAfter, abs(after - before) >= 0.05 {
            slides.append(WrappedSlide(kind: .handicap, eyebrow: "HANDICAP", big: String(format: "%.1f", after), countTo: nil,
                                       caption: "new handicap estimate",
                                       detail: "\(after < before ? "Down" : "Up") from \(String(format: "%.1f", before))."))
        }

        slides = Array(slides.prefix(maxSlides - 1))
        slides.append(WrappedSlide(kind: .outro, eyebrow: "THAT'S GOOD", big: "\(round.strokes)", countTo: nil,
                                   caption: ctx.courseName,
                                   detail: round.date.formatted(date: .long, time: .omitted)))
        return slides
    }

    static func headline(_ ctx: WrappedContext) -> WrappedSlide {
        let round = ctx.round
        let same = ctx.previous.filter { $0.holes.count == round.holes.count }
        var detail: String?
        if same.count >= 2 {
            let better = same.filter { $0.strokes < round.strokes }.count
            let equal = same.contains { $0.strokes == round.strokes }
            if better == 0 {
                detail = equal ? "Equal best round you've logged." : "Your best round yet."
            } else if better <= 2 {
                detail = "Your \(ordinal(better + 1)) best round."
            } else if let avg = average(Array(same.prefix(10)).map { Double($0.strokes) }) {
                let diff = Int((avg - Double(round.strokes)).rounded())
                detail = diff > 0 ? "\(diff) better than your average." : (diff < 0 ? "\(-diff) above your average." : "Right on your average.")
            }
        }
        let holesText = round.holes.count == 18 ? "" : " (\(round.holes.count) holes)"
        return WrappedSlide(kind: .headline, eyebrow: "YOUR ROUND", big: "\(round.strokes)", countTo: round.strokes,
                            caption: "\(MatchEngine.toParText(round.toPar)) at \(ctx.courseName)\(holesText)", detail: detail)
    }

    // MARK: Written report

    static func report(_ ctx: WrappedContext) -> RoundReport {
        let round = ctx.round
        let s = RoundStats.summarize([round])
        let past = recent(ctx)
        let usual = past.count >= 3 ? RoundStats.summarize(past) : nil
        var good: [(String, Double)] = []    // (text, importance)
        var costly: [(String, Double, String)] = []  // (text, shots, focus key)

        func pct(_ x: Double) -> String { "\(Int((x * 100).rounded()))%" }

        if let f = s.fairwayPct {
            let base = usual?.fairwayPct ?? 0.55
            let label = usual == nil ? "a good target" : "your average"
            if f >= base + 0.1 { good.append(("Driving: \(s.fairwayHits) of \(s.fairwayAttempts) fairways, above \(label) of \(pct(base)).", f - base)) }
            if f <= base - 0.15 { costly.append(("Driving: \(s.fairwayHits) of \(s.fairwayAttempts) fairways, below \(label) of \(pct(base)).", (base - f) * 4, "fairways")) }
        }
        if let g = s.girPct {
            let base = usual?.girPct ?? 0.5
            if g >= base + 0.1 { good.append(("Iron play: \(s.greenHits) greens in regulation (usually \(pct(base))).", g - base)) }
            if g <= base - 0.15 { costly.append(("Iron play: only \(s.greenHits) greens in regulation (usually \(pct(base))).", (base - g) * 6, "greens")) }
        }
        if s.totalPutts > 0 {
            let base = usual?.puttsPerRound ?? 31
            let putts = Double(s.totalPutts) * 18 / Double(max(1, round.holes.count))
            if putts <= base - 2 { good.append(("Putting: \(s.totalPutts) putts, \(Int((base - putts).rounded())) fewer than usual.", (base - putts) / 4)) }
            if putts >= base + 2 { costly.append(("Putting: \(s.totalPutts) putts, \(Int((putts - base).rounded())) more than usual.", putts - base, "putting")) }
            if s.threePutts >= 2 { costly.append(("\(plural(s.threePutts, "three-putt")).", Double(s.threePutts), "putting")) }
        }
        if s.upAndDownAttempts >= 3, let ud = s.upAndDownPct {
            if ud >= 0.5 { good.append(("Short game: up and down \(s.upAndDownMade) of \(s.upAndDownAttempts) times.", ud)) }
            if ud < 0.25 { costly.append(("Short game: up and down \(s.upAndDownMade) of \(s.upAndDownAttempts) times.", Double(s.upAndDownAttempts - s.upAndDownMade) * 0.5, "shortgame")) }
        }
        let doubles = round.holes.filter { $0.strokes - $0.par >= 2 }
        if !doubles.isEmpty {
            let lost = doubles.reduce(0) { $0 + $1.strokes - $1.par - 1 }
            costly.append(("\(plural(doubles.count, "double bogey", "double bogeys")) or worse cost you \(plural(lost, "shot")).", Double(lost), "doubles"))
        }
        if s.totalPenalties > 0 {
            costly.append(("\(plural(s.totalPenalties, "penalty shot")).", Double(s.totalPenalties), "penalties"))
        }
        let birdies = round.holes.filter { $0.strokes < $0.par }.count
        if birdies >= 2 { good.append(("\(plural(birdies, "birdie")) or better.", Double(birdies) / 2)) }
        if let run = bestRun(round.holes), run.length >= 4 {
            good.append(("\(run.length) holes in a row at par or better.", Double(run.length) / 4))
        }

        let focusKey = costly.max { $0.1 < $1.1 }?.2
        let plan: (focus: String, drill: String?)
        switch focusKey {
        case "doubles": plan = ("Course management. When you're in trouble, chip back out and play for bogey.", "Next round, count how many times you take the safe option. Aim for no doubles.")
        case "penalties": plan = ("Keep the ball in play. Take the safe line where there's water or out of bounds.", "On the range, hit 10 tee shots at a target 25 yards wide and count how many stay in.")
        case "putting": plan = ("Putting, especially speed from long range.", "Ladder drill: putt to the fringe from 30, 40 and 50 ft. Every ball must finish inside 3 ft.")
        case "greens": plan = ("Iron play. Aim for the middle of the green, not the flag.", "9 balls each with three irons at one flag. Count how many finish on the green.")
        case "fairways": plan = ("Tee shots. Pick a smaller target and commit to it.", "Pick two targets 30 yards apart. Hit 10 drives and count how many finish between them.")
        case "shortgame": plan = ("Chipping and pitching.", "Up-and-down game: 9 balls from different lies. Chip, then putt out. Aim for 5 of 9.")
        default: plan = ("Keep doing what you did today.", nil)
        }
        return RoundReport(good: good.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0 },
                           costly: costly.sorted { $0.1 > $1.1 }.prefix(3).map { $0.0 },
                           focus: plan.focus, drill: plan.drill)
    }
}

extension String {
    /// "par, birdie" → "Par, birdie"
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
