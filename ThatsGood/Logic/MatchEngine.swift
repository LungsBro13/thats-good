import Foundation

enum MatchFormat: String, CaseIterable, Codable, Identifiable {
    case stroke, stableford, skins, matchplay, nassau

    var id: String { rawValue }

    var label: String {
        switch self {
        case .stroke: return "Stroke play"
        case .stableford: return "Stableford"
        case .skins: return "Skins"
        case .matchplay: return "Match play"
        case .nassau: return "Nassau"
        }
    }

    /// Match play and Nassau are one against one.
    var isHeadToHead: Bool { self == .matchplay || self == .nassau }
}

enum HandicapBasis: String, CaseIterable, Codable { case net, gross }
enum AllowanceRule: String, CaseIterable, Codable { case full, whs }

struct MatchHoleInfo: Codable, Hashable {
    var number: Int
    var par: Int
    var strokeIndex: Int
}

struct MatchPlayerInfo: Hashable {
    var key: String
    var name: String
    var handicapIndex: Double?
}

struct MatchSetup {
    var format: MatchFormat
    var basis: HandicapBasis
    var allowance: AllowanceRule
    var holes: [MatchHoleInfo]  // in play order
    var courseRating: Double
    var slope: Int
    var players: [MatchPlayerInfo]

    var par: Int { holes.reduce(0) { $0 + $1.par } }
}

/// Gross strokes: player key → hole number → strokes.
typealias ScoreTable = [String: [Int: Int]]

struct Standing: Identifiable, Equatable {
    let key: String
    let name: String
    let position: Int
    let positionLabel: String  // "1", "T2"
    let value: String          // "−2", "38 pts", "3 skins", "2 UP"
    let detail: String         // "Thru 9"
    var id: String { key }
}

struct MatchOutcome {
    var standings: [Standing]
    var status: String
    var holesComplete: Int  // holes everyone has a score for
    var isFinished: Bool    // every hole scored, or the match is closed out
}

/// Result for the first player against the second.
enum PairResult: Equatable { case win, loss, halve }

enum MatchEngine {
    // MARK: Handicaps

    static func allowance(_ s: MatchSetup) -> Double {
        guard s.allowance == .whs else { return 1 }
        return s.format.isHeadToHead ? 1.0 : 0.95
    }

    /// Strokes each player gets over the round. Match play, Nassau and skins play off the lowest handicap.
    static func playingHandicaps(_ s: MatchSetup) -> [String: Int] {
        guard s.basis == .net else {
            return Dictionary(uniqueKeysWithValues: s.players.map { ($0.key, 0) })
        }
        var result: [String: Int] = [:]
        for p in s.players {
            let course = Handicap.courseHandicap(index: p.handicapIndex ?? 0, slope: s.slope, rating: s.courseRating, par: s.par)
            result[p.key] = Int((Double(course) * allowance(s)).rounded())
        }
        if s.format.isHeadToHead || s.format == .skins {
            let low = result.values.min() ?? 0
            result = result.mapValues { $0 - low }
        }
        return result
    }

    static func strokesReceived(_ s: MatchSetup, playingHandicap: Int, hole: MatchHoleInfo) -> Int {
        Handicap.strokesReceived(courseHandicap: playingHandicap, strokeIndex: hole.strokeIndex)
    }

    static func net(_ s: MatchSetup, _ scores: ScoreTable, _ handicaps: [String: Int], key: String, hole: MatchHoleInfo) -> Int? {
        guard let gross = scores[key]?[hole.number] else { return nil }
        return gross - strokesReceived(s, playingHandicap: handicaps[key] ?? 0, hole: hole)
    }

    static func completeHoles(_ s: MatchSetup, _ scores: ScoreTable, players: [String]? = nil) -> [MatchHoleInfo] {
        let keys = players ?? s.players.map(\.key)
        return s.holes.filter { hole in keys.allSatisfy { scores[$0]?[hole.number] != nil } }
    }

    // MARK: Outcome

    static func outcome(_ s: MatchSetup, _ scores: ScoreTable) -> MatchOutcome {
        switch s.format {
        case .stroke: return strokeOutcome(s, scores)
        case .stableford: return stablefordOutcome(s, scores)
        case .skins: return skinsOutcome(s, scores)
        case .matchplay, .nassau: return headToHeadOutcome(s, scores)
        }
    }

    static func toParText(_ v: Int) -> String {
        v == 0 ? "E" : (v > 0 ? "+\(v)" : "−\(-v)")
    }

    /// Positions with ties: the best value is 1, equal values share a "T" position.
    private static func ranked(_ items: [(key: String, name: String, score: Double, value: String, detail: String)],
                               higherIsBetter: Bool) -> [Standing] {
        let sorted = items.sorted { higherIsBetter ? $0.score > $1.score : $0.score < $1.score }
        return sorted.map { item in
            let position = 1 + sorted.filter { higherIsBetter ? $0.score > item.score : $0.score < item.score }.count
            let tied = sorted.filter { $0.score == item.score }.count > 1
            return Standing(key: item.key, name: item.name, position: position,
                            positionLabel: (tied ? "T" : "") + "\(position)", value: item.value, detail: item.detail)
        }
    }

    private static func strokeOutcome(_ s: MatchSetup, _ scores: ScoreTable) -> MatchOutcome {
        let hcp = playingHandicaps(s)
        let items = s.players.map { p -> (key: String, name: String, score: Double, value: String, detail: String) in
            let played = s.holes.filter { scores[p.key]?[$0.number] != nil }
            let toPar = played.reduce(0) { $0 + (net(s, scores, hcp, key: p.key, hole: $1) ?? 0) - $1.par }
            let gross = played.reduce(0) { $0 + (scores[p.key]?[$1.number] ?? 0) }
            let score = played.isEmpty ? Double.infinity : Double(toPar)
            let detail = played.isEmpty ? "Not started" : (played.count == s.holes.count ? "F" : "Thru \(played.count)") + " · \(gross)"
            return (p.key, p.name, score, played.isEmpty ? "–" : toParText(toPar), detail)
        }
        let standings = ranked(items, higherIsBetter: false)
        let complete = completeHoles(s, scores).count
        let finished = complete == s.holes.count
        let status = standings.first.map { "\(finished ? "Winner" : "Leader"): \($0.name) \($0.value)" } ?? ""
        return MatchOutcome(standings: standings, status: status, holesComplete: complete, isFinished: finished)
    }

    static func stablefordPoints(par: Int, net: Int) -> Int { max(0, 2 + par - net) }

    private static func stablefordOutcome(_ s: MatchSetup, _ scores: ScoreTable) -> MatchOutcome {
        let hcp = playingHandicaps(s)
        let items = s.players.map { p -> (key: String, name: String, score: Double, value: String, detail: String) in
            let played = s.holes.filter { scores[p.key]?[$0.number] != nil }
            let points = played.reduce(0) { total, hole in
                total + stablefordPoints(par: hole.par, net: net(s, scores, hcp, key: p.key, hole: hole) ?? 0)
            }
            return (p.key, p.name, Double(points), "\(points) pts",
                    played.isEmpty ? "Not started" : (played.count == s.holes.count ? "F" : "Thru \(played.count)"))
        }
        let standings = ranked(items, higherIsBetter: true)
        let complete = completeHoles(s, scores).count
        let finished = complete == s.holes.count
        let status = standings.first.map { "\(finished ? "Winner" : "Leader"): \($0.name), \($0.value)" } ?? ""
        return MatchOutcome(standings: standings, status: status, holesComplete: complete, isFinished: finished)
    }

    /// Skins won by each player, and how many are carrying over.
    static func skins(_ s: MatchSetup, _ scores: ScoreTable) -> (won: [String: Int], carrying: Int) {
        let hcp = playingHandicaps(s)
        var won = Dictionary(uniqueKeysWithValues: s.players.map { ($0.key, 0) })
        var pot = 1
        for hole in completeHoles(s, scores) {
            let nets = s.players.compactMap { p in net(s, scores, hcp, key: p.key, hole: hole).map { (p.key, $0) } }
            guard let best = nets.map(\.1).min() else { continue }
            let leaders = nets.filter { $0.1 == best }
            if leaders.count == 1 {
                won[leaders[0].0, default: 0] += pot
                pot = 1
            } else {
                pot += 1
            }
        }
        return (won, pot - 1)
    }

    private static func skinsOutcome(_ s: MatchSetup, _ scores: ScoreTable) -> MatchOutcome {
        let result = skins(s, scores)
        let complete = completeHoles(s, scores).count
        let items = s.players.map { p -> (key: String, name: String, score: Double, value: String, detail: String) in
            let n = result.won[p.key] ?? 0
            return (p.key, p.name, Double(n), "\(n) skin\(n == 1 ? "" : "s")", "Thru \(complete)")
        }
        let finished = complete == s.holes.count
        var status = finished ? "Final" : "Thru \(complete)"
        if result.carrying > 0 { status += " · \(result.carrying) skin\(result.carrying == 1 ? "" : "s") carrying" }
        return MatchOutcome(standings: ranked(items, higherIsBetter: true), status: status,
                            holesComplete: complete, isFinished: finished)
    }

    struct Segment {
        var lead: Int       // positive: first player is up
        var played: Int
        var remaining: Int
        var closedOut: Bool
        var finished: Bool { closedOut || remaining == 0 }
    }

    /// Match play over a set of holes between two players. Stops counting once the match is closed out.
    static func segment(_ s: MatchSetup, _ scores: ScoreTable, holes: [MatchHoleInfo], _ a: String, _ b: String) -> Segment {
        let hcp = playingHandicaps(s)
        var lead = 0, played = 0
        for hole in holes {
            guard let x = net(s, scores, hcp, key: a, hole: hole), let y = net(s, scores, hcp, key: b, hole: hole) else { break }
            played += 1
            if x < y { lead += 1 } else if y < x { lead -= 1 }
            if abs(lead) > holes.count - played { break }
        }
        let remaining = holes.count - played
        return Segment(lead: lead, played: played, remaining: remaining, closedOut: abs(lead) > remaining)
    }

    /// "Dave 2 UP thru 11", "Dave 3&2", "Halved", "All square thru 4".
    static func describe(_ seg: Segment, aName: String, bName: String) -> String {
        if seg.played == 0 { return "Not started" }
        let leader = seg.lead > 0 ? aName : bName
        let margin = abs(seg.lead)
        if seg.closedOut && seg.remaining > 0 { return "\(leader) \(margin)&\(seg.remaining)" }
        if seg.remaining == 0 { return seg.lead == 0 ? "Halved" : "\(leader) \(margin) UP" }
        return seg.lead == 0 ? "All square thru \(seg.played)" : "\(leader) \(margin) UP thru \(seg.played)"
    }

    private static func headToHeadOutcome(_ s: MatchSetup, _ scores: ScoreTable) -> MatchOutcome {
        guard s.players.count == 2 else {
            return MatchOutcome(standings: [], status: "Needs exactly 2 players", holesComplete: 0, isFinished: false)
        }
        let a = s.players[0], b = s.players[1]
        let overall = segment(s, scores, holes: s.holes, a.key, b.key)
        var status = describe(overall, aName: a.name, bName: b.name)
        var finished = overall.finished
        var detail = status

        if s.format == .nassau && s.holes.count > 9 {
            let front = segment(s, scores, holes: Array(s.holes.prefix(9)), a.key, b.key)
            let back = segment(s, scores, holes: Array(s.holes.dropFirst(9)), a.key, b.key)
            let total = segment(s, scores, holes: s.holes, a.key, b.key)
            // In a Nassau every bet is played out, so the overall match runs all 18.
            finished = front.finished && back.finished && (total.remaining == 0)
            status = "Front: \(describe(front, aName: a.name, bName: b.name)) · Back: \(describe(back, aName: a.name, bName: b.name)) · Overall: \(describe(total, aName: a.name, bName: b.name))"
            detail = describe(total, aName: a.name, bName: b.name)
        }

        func value(for first: Bool) -> String {
            let lead = first ? overall.lead : -overall.lead
            if overall.played == 0 { return "–" }
            if lead == 0 { return "AS" }
            if lead < 0 { return "" }
            if overall.closedOut && overall.remaining > 0 { return "\(lead)&\(overall.remaining)" }
            return "\(lead) UP"
        }
        let aFirst = overall.lead >= 0
        let ordered = aFirst ? [a, b] : [b, a]
        let standings = ordered.enumerated().map { i, p in
            Standing(key: p.key, name: p.name, position: overall.lead == 0 ? 1 : i + 1,
                     positionLabel: overall.lead == 0 ? "T1" : "\(i + 1)",
                     value: value(for: p.key == a.key), detail: i == 0 ? detail : "")
        }
        return MatchOutcome(standings: standings, status: status,
                            holesComplete: completeHoles(s, scores).count, isFinished: finished)
    }

    // MARK: Rivalries

    /// How player a did against player b in this match, or nil if it can't be compared yet.
    static func pairResult(_ s: MatchSetup, _ scores: ScoreTable, _ a: String, _ b: String) -> PairResult? {
        let hcp = playingHandicaps(s)
        func compare(_ x: Double, _ y: Double, higherIsBetter: Bool) -> PairResult {
            if x == y { return .halve }
            return (x > y) == higherIsBetter ? .win : .loss
        }
        switch s.format {
        case .matchplay, .nassau:
            let seg = segment(s, scores, holes: s.holes, a, b)
            guard seg.played > 0 else { return nil }
            return seg.lead > 0 ? .win : (seg.lead < 0 ? .loss : .halve)
        case .stroke:
            let both = completeHoles(s, scores, players: [a, b])
            guard both.count == s.holes.count else { return nil }
            let x = both.reduce(0) { $0 + (net(s, scores, hcp, key: a, hole: $1) ?? 0) }
            let y = both.reduce(0) { $0 + (net(s, scores, hcp, key: b, hole: $1) ?? 0) }
            return compare(Double(x), Double(y), higherIsBetter: false)
        case .stableford:
            let both = completeHoles(s, scores, players: [a, b])
            guard !both.isEmpty else { return nil }
            func points(_ k: String) -> Int {
                both.reduce(0) { $0 + stablefordPoints(par: $1.par, net: net(s, scores, hcp, key: k, hole: $1) ?? 0) }
            }
            return compare(Double(points(a)), Double(points(b)), higherIsBetter: true)
        case .skins:
            let won = skins(s, scores).won
            guard completeHoles(s, scores).count > 0 else { return nil }
            return compare(Double(won[a] ?? 0), Double(won[b] ?? 0), higherIsBetter: true)
        }
    }
}

/// All-time record of one player against another.
struct RivalryRecord {
    var wins = 0
    var losses = 0
    var halves = 0
    var form: [PairResult] = []  // most recent first
    var byFormat: [MatchFormat: (wins: Int, losses: Int, halves: Int)] = [:]

    var played: Int { wins + losses + halves }

    /// Results must be passed most recent first.
    static func build(_ results: [(format: MatchFormat, result: PairResult)]) -> RivalryRecord {
        var r = RivalryRecord()
        for item in results {
            var f = r.byFormat[item.format] ?? (0, 0, 0)
            switch item.result {
            case .win: r.wins += 1; f.wins += 1
            case .loss: r.losses += 1; f.losses += 1
            case .halve: r.halves += 1; f.halves += 1
            }
            r.byFormat[item.format] = f
            r.form.append(item.result)
        }
        return r
    }
}
