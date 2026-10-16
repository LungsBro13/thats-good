import Foundation

// MARK: - Settings

enum TourScoring: String, CaseIterable, Codable, Identifiable {
    case stroke, match
    var id: String { rawValue }
    var label: String { self == .stroke ? "Stroke play" : "Match play" }
}

enum TourMode: String, CaseIterable, Codable, Identifiable {
    case individual, pairs, teams
    var id: String { rawValue }
    var label: String {
        switch self {
        case .individual: return "Individual"
        case .pairs: return "Pairs"
        case .teams: return "Two teams"
        }
    }
}

enum PairFormat: String, CaseIterable, Codable, Identifiable {
    case fourball, foursomes, scramble
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    /// Foursomes and scramble: one ball per pair.
    var sharedBall: Bool { self != .fourball }
    var note: String {
        switch self {
        case .fourball: return "Both play their own ball, best score on each hole counts."
        case .foursomes: return "One ball per pair, taking turns."
        case .scramble: return "Both tee off, pick the best shot, both play from there."
        }
    }
}

enum TeamStroke: String, CaseIterable, Codable, Identifiable {
    case best2, all
    var id: String { rawValue }
    var label: String { self == .best2 ? "Best 2 per hole" : "All scores count" }
}

/// Ryder Cup style sessions.
enum CupSession: String, CaseIterable, Codable, Identifiable {
    case fourball, foursomes, singles
    var id: String { rawValue }
    var label: String {
        switch self {
        case .fourball: return "Fourballs"
        case .foursomes: return "Foursomes"
        case .singles: return "Singles"
        }
    }
    var prefix: String {
        switch self {
        case .fourball: return "fb"
        case .foursomes: return "fs"
        case .singles: return "s"
        }
    }
}

struct TourPlayer: Hashable {
    var key: String
    var name: String
    var handicapIndex: Double?
    var team: Int?  // 0 or 1 in a two-team event
}

struct TourSetup {
    var scoring: TourScoring
    var mode: TourMode
    var pairFormat: PairFormat = .fourball
    var teamStroke: TeamStroke = .best2
    var basis: HandicapBasis = .net
    var holes: [MatchHoleInfo]
    var courseRating: Double
    var slope: Int
    var rounds: Int = 1
    var sessions: [CupSession] = CupSession.allCases
    var players: [TourPlayer]  // in draw order
    var teamNames: [String] = ["Team Blue", "Team Orange"]

    var par: Int { holes.reduce(0) { $0 + $1.par } }
    func team(_ t: Int) -> [TourPlayer] { players.filter { $0.team == t } }
    var isKnockout: Bool { scoring == .match && mode != .teams }
}

/// Gross strokes: game key ("r1", "fb2", "k1-3") → unit key → hole number → strokes.
typealias TourScores = [String: ScoreTable]

// MARK: - Who plays together

/// One ball: a player, or a pair sharing a ball. `handicap` is the strokes it gets over the round.
struct TourUnit: Hashable, Identifiable {
    var key: String
    var name: String
    var playerKeys: [String]
    var handicap: Int
    var id: String { key }
}

/// One side: a player, a pair or a team, made of one or more balls.
struct TourSide: Hashable, Identifiable {
    var key: String
    var name: String
    var playerKeys: [String]
    var units: [TourUnit]
    var team: Int?
    var id: String { key }
}

/// A match between two sides. Either side can still be unknown in a knockout.
struct TourGame: Identifiable {
    var key: String
    var title: String
    var session: CupSession?
    var a: TourSide?
    var b: TourSide?
    var id: String { key }
    var isReady: Bool { a != nil && b != nil }
}

struct GameState: Equatable {
    var lead = 0          // positive: side a is up
    var played = 0
    var remaining = 0
    var closedOut = false
    var extraHoles = 0    // sudden death holes played after a halved knockout match
    var winner: Int?      // 0 = side a, 1 = side b
    var finished = false
    var status = "Not started"

    /// 0 or 1 for the side ahead now, nil when level.
    var leader: Int? { winner ?? (lead > 0 ? 0 : (lead < 0 ? 1 : nil)) }
}

// MARK: - Results

struct TourRow: Identifiable, Equatable {
    var key: String
    var name: String
    var position: Int
    var positionLabel: String
    var today: Int?        // to par in the current round
    var thru: Int          // holes counted in the current round
    var roundDone: Bool
    var total: Int?        // to par over every round so far
    var strokes: Int?      // gross strokes in the current round
    var movement: Int?     // places gained since the last round
    var handicapIndex: Double?
    var team: Int?
    var id: String { key }
}

struct TourBoard {
    var rows: [TourRow]
    var currentRound: Int
}

struct KnockoutGame: Identifiable {
    var game: TourGame
    var round: Int
    var slot: Int
    var isBye: Bool
    var state: GameState?
    var winner: TourSide?
    var id: String { game.key }
}

struct Bracket {
    var rounds: [[KnockoutGame]]
    var champion: TourSide?
    func title(_ round: Int) -> String { TournamentEngine.roundTitle(round, of: rounds.count) }
}

struct CupMatch: Identifiable {
    var game: TourGame
    var state: GameState
    var id: String { game.key }
}

struct CupResult {
    var matches: [CupMatch]
    var points: [Double]
    var projected: [Double]
    var total: Double
    var toWin: Double { total / 2 + 0.5 }
    var winner: Int? { points[0] > total / 2 ? 0 : (points[1] > total / 2 ? 1 : nil) }
    var onCourse: Int
    func sessionPoints(_ session: CupSession) -> [Double] {
        var p = [0.0, 0.0]
        for m in matches where m.game.session == session && m.state.finished {
            if let w = m.state.winner { p[w] += 1 } else { p[0] += 0.5; p[1] += 0.5 }
        }
        return p
    }
}

/// A set of balls the scorer enters together: a tee group or one match.
struct ScoringGroup: Identifiable {
    var id: String
    var game: String
    var title: String
    var units: [TourUnit]
    var holes: [MatchHoleInfo]
    var playerKeys: [String] { units.flatMap(\.playerKeys) }
}

struct TourScoreEvent {
    var game: String
    var unit: String
    var hole: Int
    var strokes: Int
    var time: Date
}

struct FeedItem: Identifiable, Equatable {
    var id: String
    var time: Date
    var name: String
    var text: String
}

// MARK: - Engine

enum TournamentEngine {
    // MARK: Handicaps (WHS recommended allowances)

    static func courseHandicap(_ s: TourSetup, _ p: TourPlayer) -> Int {
        Handicap.courseHandicap(index: p.handicapIndex ?? 0, slope: s.slope, rating: s.courseRating, par: s.par)
    }

    /// Own-ball allowance: individual stroke 95%, fourball stroke 85%, singles match 100%, fourball match 90%.
    static func ownBallAllowance(fourball: Bool, matchPlay: Bool) -> Double {
        switch (fourball, matchPlay) {
        case (false, false): return 0.95
        case (true, false): return 0.85
        case (false, true): return 1.0
        case (true, true): return 0.9
        }
    }

    static func playerUnit(_ s: TourSetup, _ p: TourPlayer, allowance: Double) -> TourUnit {
        let h = s.basis == .net ? Int((Double(courseHandicap(s, p)) * allowance).rounded()) : 0
        return TourUnit(key: p.key, name: p.name, playerKeys: [p.key], handicap: h)
    }

    /// Foursomes: 50% of the pair's combined handicap. Scramble: 35% of the lower plus 15% of the higher.
    static func sharedHandicap(_ s: TourSetup, _ players: [TourPlayer], format: PairFormat) -> Int {
        guard s.basis == .net else { return 0 }
        let ch = players.map { Double(courseHandicap(s, $0)) }.sorted()
        switch format {
        case .scramble where ch.count == 2: return Int((0.35 * ch[0] + 0.15 * ch[1]).rounded())
        default: return Int((0.5 * ch.reduce(0, +)).rounded())
        }
    }

    static func pairName(_ players: [TourPlayer]) -> String { players.map(\.name).joined(separator: " & ") }

    /// A pair as a side: two balls in fourball, one shared ball otherwise.
    static func pairSide(_ s: TourSetup, _ players: [TourPlayer], format: PairFormat, matchPlay: Bool) -> TourSide {
        let key = players.map(\.key).joined(separator: "+")
        let units: [TourUnit]
        if format.sharedBall {
            units = [TourUnit(key: key, name: pairName(players), playerKeys: players.map(\.key),
                              handicap: sharedHandicap(s, players, format: format))]
        } else {
            units = players.map { playerUnit(s, $0, allowance: ownBallAllowance(fourball: true, matchPlay: matchPlay)) }
        }
        return TourSide(key: key, name: pairName(players), playerKeys: players.map(\.key), units: units, team: players.first?.team)
    }

    static func singleSide(_ s: TourSetup, _ p: TourPlayer, matchPlay: Bool) -> TourSide {
        TourSide(key: p.key, name: p.name, playerKeys: [p.key],
                 units: [playerUnit(s, p, allowance: ownBallAllowance(fourball: false, matchPlay: matchPlay))], team: p.team)
    }

    /// Pairs in draw order: players 1 & 2, 3 & 4, …
    static func pairs(_ s: TourSetup, matchPlay: Bool) -> [TourSide] {
        stride(from: 0, to: s.players.count - 1, by: 2).map {
            pairSide(s, [s.players[$0], s.players[$0 + 1]], format: s.pairFormat, matchPlay: matchPlay)
        }
    }

    /// In match play the lowest ball in the match plays off zero and everyone else gets the difference.
    static func makeGame(_ key: String, title: String, session: CupSession? = nil, _ a: TourSide?, _ b: TourSide?) -> TourGame {
        guard var a, var b else { return TourGame(key: key, title: title, session: session, a: a, b: b) }
        let low = (a.units + b.units).map(\.handicap).min() ?? 0
        a.units = a.units.map { var u = $0; u.handicap -= low; return u }
        b.units = b.units.map { var u = $0; u.handicap -= low; return u }
        return TourGame(key: key, title: title, session: session, a: a, b: b)
    }

    // MARK: Hole scores

    static func net(_ scores: ScoreTable, _ unit: TourUnit, _ hole: MatchHoleInfo, holeCount: Int) -> Int? {
        guard let gross = scores[unit.key]?[hole.number] else { return nil }
        return gross - Handicap.strokesReceived(courseHandicap: unit.handicap, strokeIndex: hole.strokeIndex,
                                                holeCount: max(holeCount, 1))
    }

    /// A side's score on a hole: its best ball. Nil until every ball on the side has a score.
    static func sideNet(_ scores: ScoreTable, _ side: TourSide, _ hole: MatchHoleInfo, holeCount: Int) -> Int? {
        let nets = side.units.map { net(scores, $0, hole, holeCount: holeCount) }
        guard !nets.isEmpty, nets.allSatisfy({ $0 != nil }) else { return nil }
        return nets.compactMap { $0 }.min()
    }

    /// Hole 19 plays as hole 1, and so on.
    static func extraHole(_ s: TourSetup, _ k: Int) -> MatchHoleInfo {
        let source = s.holes[(k - 1) % s.holes.count]
        return MatchHoleInfo(number: s.holes.count + k, par: source.par, strokeIndex: source.strokeIndex)
    }

    // MARK: Match play

    static func gameState(_ s: TourSetup, _ scores: TourScores, _ game: TourGame, suddenDeath: Bool) -> GameState {
        guard let a = game.a, let b = game.b else { return GameState(status: "Waiting") }
        let table = scores[game.key] ?? [:]
        let n = s.holes.count
        var st = GameState()
        for hole in s.holes {
            guard let x = sideNet(table, a, hole, holeCount: n), let y = sideNet(table, b, hole, holeCount: n) else { break }
            st.played += 1
            if x < y { st.lead += 1 } else if y < x { st.lead -= 1 }
            if abs(st.lead) > n - st.played { break }
        }
        st.remaining = n - st.played
        st.closedOut = abs(st.lead) > st.remaining
        let margin = abs(st.lead)

        if st.closedOut {
            st.finished = true
            st.winner = st.lead > 0 ? 0 : 1
            st.status = st.remaining > 0 ? "\(margin)&\(st.remaining)" : "\(margin) UP"
        } else if st.remaining == 0 {
            // Level after the last hole.
            st.status = "AS"
            st.finished = !suddenDeath
            if suddenDeath {
                var k = 1
                while k <= n {
                    let hole = extraHole(s, k)
                    guard let x = sideNet(table, a, hole, holeCount: n), let y = sideNet(table, b, hole, holeCount: n) else { break }
                    st.extraHoles = k
                    if x != y {
                        st.winner = x < y ? 0 : 1
                        st.finished = true
                        st.status = "Won at the \(ordinal(n + k))"
                        break
                    }
                    k += 1
                }
                if !st.finished { st.status = st.extraHoles == 0 ? "AS · extra holes" : "AS after \(n + st.extraHoles)" }
            }
        } else if st.played == 0 {
            st.status = "Not started"
        } else {
            st.status = st.lead == 0 ? "AS" : "\(margin) UP"
        }
        return st
    }

    static func ordinal(_ n: Int) -> String {
        let suffix: String
        switch (n % 10, n % 100) {
        case (1, let t) where t != 11: suffix = "st"
        case (2, let t) where t != 12: suffix = "nd"
        case (3, let t) where t != 13: suffix = "rd"
        default: suffix = "th"
        }
        return "\(n)\(suffix)"
    }

    // MARK: Knockout

    /// Standard seeding: 1 plays the lowest seed, and the top two can only meet in the final.
    static func seedOrder(_ size: Int) -> [Int] {
        var order = [1]
        while order.count < size {
            let m = order.count * 2
            order = order.flatMap { [$0, m + 1 - $0] }
        }
        return order
    }

    static func knockoutEntries(_ s: TourSetup) -> [TourSide] {
        s.mode == .pairs ? pairs(s, matchPlay: true) : s.players.map { singleSide(s, $0, matchPlay: true) }
    }

    static func roundTitle(_ round: Int, of total: Int) -> String {
        switch total - round {
        case 0: return "Final"
        case 1: return "Semi-finals"
        case 2: return "Quarter-finals"
        default: return "Round \(round)"
        }
    }

    static func bracket(_ s: TourSetup, _ scores: TourScores) -> Bracket {
        let entries = knockoutEntries(s)
        guard entries.count >= 2 else { return Bracket(rounds: [], champion: entries.first) }
        var size = 1
        while size < entries.count { size *= 2 }
        let roundCount = Int(log2(Double(size)))
        let order = seedOrder(size)
        var rounds: [[KnockoutGame]] = []

        for round in 1...roundCount {
            let slots = size >> round
            var games: [KnockoutGame] = []
            for slot in 0..<slots {
                let a: TourSide?, b: TourSide?
                var bye = false
                if round == 1 {
                    let x = order[2 * slot], y = order[2 * slot + 1]
                    a = x <= entries.count ? entries[x - 1] : nil
                    b = y <= entries.count ? entries[y - 1] : nil
                    bye = a == nil || b == nil
                } else {
                    a = rounds[round - 2][2 * slot].winner
                    b = rounds[round - 2][2 * slot + 1].winner
                }
                let game = makeGame("k\(round)-\(slot + 1)", title: roundTitle(round, of: roundCount), a, b)
                var item = KnockoutGame(game: game, round: round, slot: slot, isBye: bye)
                if bye {
                    item.winner = a ?? b
                } else if game.isReady {
                    let st = gameState(s, scores, game, suddenDeath: true)
                    item.state = st
                    if let w = st.winner, st.finished { item.winner = w == 0 ? game.a : game.b }
                }
                games.append(item)
            }
            rounds.append(games)
        }
        return Bracket(rounds: rounds, champion: rounds.last?.first?.winner)
    }

    // MARK: Two teams, match play

    static func cupGames(_ s: TourSetup) -> [TourGame] {
        let a = s.team(0), b = s.team(1)
        let n = min(a.count, b.count)
        let m = n / 2
        var games: [TourGame] = []
        for session in CupSession.allCases where s.sessions.contains(session) {
            switch session {
            case .fourball, .foursomes:
                guard m > 0 else { continue }
                let format: PairFormat = session == .fourball ? .fourball : .foursomes
                // Fourballs pair 1 & 2, 3 & 4; foursomes mix it up (1 & 3, 2 & 4) against different opponents.
                func pair(_ team: [TourPlayer], _ i: Int) -> [TourPlayer] {
                    session == .fourball ? [team[2 * i], team[2 * i + 1]] : [team[i], team[i + m]]
                }
                for i in 0..<m {
                    let j = session == .fourball ? i : (i + 1) % m
                    games.append(makeGame("\(session.prefix)\(i + 1)", title: "\(session.label) · match \(i + 1)", session: session,
                                          pairSide(s, pair(a, i), format: format, matchPlay: true),
                                          pairSide(s, pair(b, j), format: format, matchPlay: true)))
                }
            case .singles:
                for i in 0..<n {
                    games.append(makeGame("s\(i + 1)", title: "Singles · match \(i + 1)", session: .singles,
                                          singleSide(s, a[i], matchPlay: true), singleSide(s, b[i], matchPlay: true)))
                }
            }
        }
        return games
    }

    static func cup(_ s: TourSetup, _ scores: TourScores) -> CupResult {
        let matches = cupGames(s).map { CupMatch(game: $0, state: gameState(s, scores, $0, suddenDeath: false)) }
        var points = [0.0, 0.0], projected = [0.0, 0.0]
        var onCourse = 0
        for m in matches {
            let st = m.state
            if st.finished {
                if let w = st.winner { points[w] += 1; projected[w] += 1 } else {
                    points[0] += 0.5; points[1] += 0.5; projected[0] += 0.5; projected[1] += 0.5
                }
            } else {
                if st.played > 0 { onCourse += 1 }
                if let w = st.leader { projected[w] += 1 } else { projected[0] += 0.5; projected[1] += 0.5 }
            }
        }
        return CupResult(matches: matches, points: points, projected: projected, total: Double(matches.count), onCourse: onCourse)
    }

    // MARK: Stroke play

    struct Entry {
        var key: String
        var name: String
        var units: [TourUnit]
        var counting: Int?  // best N balls per hole; nil means every ball counts
        var team: Int?
        var handicapIndex: Double?
    }

    static func strokeEntries(_ s: TourSetup) -> [Entry] {
        switch s.mode {
        case .individual:
            return s.players.map { p in
                Entry(key: p.key, name: p.name, units: [playerUnit(s, p, allowance: 0.95)], counting: 1, handicapIndex: p.handicapIndex)
            }
        case .pairs:
            return pairs(s, matchPlay: false).map { Entry(key: $0.key, name: $0.name, units: $0.units, counting: 1) }
        case .teams:
            return [0, 1].map { t in
                Entry(key: "team\(t)", name: s.teamNames[t], units: s.team(t).map { playerUnit(s, $0, allowance: 0.95) },
                      counting: s.teamStroke == .best2 ? 2 : nil, team: t)
            }
        }
    }

    /// One entry's round: to par, holes counted, gross strokes counted.
    static func entryRound(_ s: TourSetup, _ table: ScoreTable, _ e: Entry) -> (toPar: Int, thru: Int, strokes: Int) {
        let n = s.holes.count
        var toPar = 0, thru = 0, strokes = 0
        for hole in s.holes {
            let scored = e.units.compactMap { u -> (net: Int, gross: Int)? in
                guard let gross = table[u.key]?[hole.number], let x = net(table, u, hole, holeCount: n) else { return nil }
                return (x, gross)
            }.sorted { $0.net < $1.net }
            if let k = e.counting {
                guard scored.count >= min(k, e.units.count), !scored.isEmpty else { continue }
                let best = scored.prefix(k)
                toPar += best.reduce(0) { $0 + $1.net - hole.par }
                strokes += best.reduce(0) { $0 + $1.gross }
                thru += 1
            } else {
                toPar += scored.reduce(0) { $0 + $1.net - hole.par }
                strokes += scored.reduce(0) { $0 + $1.gross }
                if scored.count == e.units.count { thru += 1 }
            }
        }
        return (toPar, thru, strokes)
    }

    static func currentRound(_ s: TourSetup, _ scores: TourScores) -> Int {
        (1...max(1, s.rounds)).last { r in !(scores["r\(r)"] ?? [:]).values.allSatisfy(\.isEmpty) } ?? 1
    }

    /// Live stroke play board. `basis` lets the viewer flip between gross and net.
    static func leaderboard(_ setup: TourSetup, _ scores: TourScores, basis: HandicapBasis? = nil) -> TourBoard {
        var s = setup
        if let basis { s.basis = basis }
        let current = currentRound(s, scores)
        let entries = strokeEntries(s)

        var rows: [TourRow] = []
        var before: [String: Int?] = [:]
        for e in entries {
            var total: Int?
            var prior: Int?
            var row = TourRow(key: e.key, name: e.name, position: 0, positionLabel: "", today: nil, thru: 0,
                              roundDone: false, total: nil, strokes: nil, movement: nil,
                              handicapIndex: e.handicapIndex, team: e.team)
            for r in 1...current {
                let res = entryRound(s, scores["r\(r)"] ?? [:], e)
                guard res.thru > 0 || (e.counting == nil && res.strokes > 0) else { continue }
                total = (total ?? 0) + res.toPar
                if r < current { prior = (prior ?? 0) + res.toPar }
                if r == current {
                    row.today = res.toPar
                    row.thru = res.thru
                    row.strokes = res.strokes
                    row.roundDone = res.thru == s.holes.count
                }
            }
            row.total = total
            before[e.key] = prior
            rows.append(row)
        }

        let now = positions(rows.map { ($0.key, $0.total.map { Double($0) }) })
        rows = rows.map { row in
            var r = row
            r.position = now[r.key]?.0 ?? 0
            r.positionLabel = now[r.key]?.1 ?? "–"
            return r
        }
        if current > 1 {
            let then = positions(before.map { ($0.key, $0.value.map { Double($0) }) })
            rows = rows.map { row in
                var r = row
                if let a = then[r.key]?.0, r.total != nil, before[r.key] ?? nil != nil { r.movement = a - r.position }
                return r
            }
        }
        rows.sort { ($0.total ?? Int.max, $0.thru == 0 ? 1 : 0, $0.name) < ($1.total ?? Int.max, $1.thru == 0 ? 1 : 0, $1.name) }
        return TourBoard(rows: rows, currentRound: current)
    }

    /// Positions with ties (lowest first). Entries with no score yet have no position.
    static func positions(_ items: [(String, Double?)]) -> [String: (Int, String)] {
        let scored = items.compactMap { k, v in v.map { (k, $0) } }
        var out: [String: (Int, String)] = [:]
        for (k, v) in scored {
            let pos = 1 + scored.filter { $0.1 < v }.count
            let tied = scored.filter { $0.1 == v }.count > 1
            out[k] = (pos, (tied ? "T" : "") + "\(pos)")
        }
        return out
    }

    /// Players for team stroke play, alternating teams so groups are mixed.
    static func interleaved(_ s: TourSetup) -> [TourPlayer] {
        let a = s.team(0), b = s.team(1)
        var out: [TourPlayer] = []
        for i in 0..<max(a.count, b.count) {
            if i < a.count { out.append(a[i]) }
            if i < b.count { out.append(b[i]) }
        }
        return out
    }

    // MARK: Scoring

    static func scoringGroups(_ s: TourSetup, _ scores: TourScores) -> [ScoringGroup] {
        switch (s.scoring, s.mode) {
        case (.stroke, _):
            let units: [[TourUnit]]
            switch s.mode {
            case .individual:
                units = chunk(s.players.map { playerUnit(s, $0, allowance: 0.95) }, 4)
            case .pairs:
                units = chunk(pairs(s, matchPlay: false), 2).map { $0.flatMap(\.units) }
            case .teams:
                units = chunk(interleaved(s).map { playerUnit(s, $0, allowance: 0.95) }, 4)
            }
            return (1...max(1, s.rounds)).flatMap { r in
                units.enumerated().map { i, group in
                    ScoringGroup(id: "r\(r)-g\(i + 1)", game: "r\(r)",
                                 title: (s.rounds > 1 ? "Round \(r) · " : "") + "Group \(i + 1)", units: group, holes: s.holes)
                }
            }
        case (.match, .teams):
            return cupGames(s).map { group(s, scores, $0, suddenDeath: false) }
        case (.match, _):
            return bracket(s, scores).rounds.flatMap { $0 }
                .filter { !$0.isBye && $0.game.isReady }
                .map { group(s, scores, $0.game, suddenDeath: true) }
        }
    }

    static func group(_ s: TourSetup, _ scores: TourScores, _ game: TourGame, suddenDeath: Bool) -> ScoringGroup {
        let st = gameState(s, scores, game, suddenDeath: suddenDeath)
        var holes = s.holes
        if suddenDeath && st.remaining == 0 && st.lead == 0 {
            let extra = st.finished ? st.extraHoles : min(s.holes.count, st.extraHoles + 1)
            if extra > 0 { holes += (1...extra).map { extraHole(s, $0) } }
        }
        let names = [game.a?.name ?? "?", game.b?.name ?? "?"].joined(separator: " v ")
        return ScoringGroup(id: game.key, game: game.key, title: "\(game.title): \(names)",
                            units: (game.a?.units ?? []) + (game.b?.units ?? []), holes: holes)
    }

    static func chunk<T>(_ items: [T], _ size: Int) -> [[T]] {
        stride(from: 0, to: items.count, by: size).map { Array(items[$0..<min($0 + size, items.count)]) }
    }

    // MARK: Live feed

    /// Birdies, eagles and finished rounds, newest first.
    static func feed(_ s: TourSetup, _ scores: TourScores, events: [TourScoreEvent], limit: Int = 8) -> [FeedItem] {
        var names: [String: String] = [:]
        for g in scoringGroups(s, scores) { for u in g.units { names[u.key] = u.name } }
        let byNumber = Dictionary(uniqueKeysWithValues: s.holes.map { ($0.number, $0) })
        var items: [FeedItem] = []
        for e in events {
            guard let hole = byNumber[e.hole], let name = names[e.unit] else { continue }
            let diff = e.strokes - hole.par
            let id = "\(e.game)|\(e.unit)|\(e.hole)"
            if e.strokes == 1 {
                items.append(FeedItem(id: id, time: e.time, name: name, text: "hole in one on \(e.hole)!"))
            } else if diff <= -2 {
                items.append(FeedItem(id: id, time: e.time, name: name, text: "eagle on \(e.hole)"))
            } else if diff == -1 {
                items.append(FeedItem(id: id, time: e.time, name: name, text: "birdie on \(e.hole)"))
            }
            if s.scoring == .stroke, e.hole == s.holes.last?.number,
               let card = scores[e.game]?[e.unit], s.holes.allSatisfy({ card[$0.number] != nil }) {
                let gross = s.holes.reduce(0) { $0 + (card[$1.number] ?? 0) }
                let round = s.rounds > 1 ? ", round \(e.game.dropFirst())" : ""
                items.append(FeedItem(id: id + "|F", time: e.time, name: name,
                                      text: "finished with \(gross) (\(MatchEngine.toParText(gross - s.par)))\(round)"))
            }
        }
        return Array(items.sorted { $0.time > $1.time }.prefix(limit))
    }

    // MARK: Setup checks and wording

    static func problem(_ s: TourSetup) -> String? {
        let n = s.players.count
        if n < 2 { return "Add at least 2 players." }
        if n > 64 { return "Up to 64 players." }
        switch s.mode {
        case .individual:
            return nil
        case .pairs:
            if n % 2 != 0 { return "Pairs need an even number of players." }
            if n < 4 { return "Pairs need at least 4 players." }
            return nil
        case .teams:
            let a = s.team(0).count, b = s.team(1).count
            if a + b != n { return "Put every player in a team." }
            if a == 0 || b == 0 { return "Both teams need players." }
            if s.scoring == .match {
                if a != b { return "Teams need the same number of players (\(a) v \(b))." }
                if s.sessions.isEmpty { return "Pick at least one session." }
                if s.sessions.allSatisfy({ $0 != .singles }) && a < 2 { return "Pairs sessions need 2 players a team." }
            } else if s.teamStroke == .best2 && min(a, b) < 2 {
                return "Best 2 per hole needs at least 2 players a team."
            }
            return nil
        }
    }

    static func summary(_ s: TourSetup) -> String {
        let n = s.players.count
        let rounds = "\(s.rounds) round\(s.rounds == 1 ? "" : "s")"
        switch (s.mode, s.scoring) {
        case (.individual, .stroke):
            return "\(n) players · \(rounds) · live \(s.basis.rawValue) leaderboard"
        case (.individual, .match), (.pairs, .match):
            let entries = s.mode == .pairs ? n / 2 : n
            var size = 1
            while size < entries { size *= 2 }
            let byes = size - entries
            let what = s.mode == .pairs ? "\(entries) pairs · \(s.pairFormat.rawValue)" : "\(entries) players"
            return "\(what) · knockout · \(Int(log2(Double(max(size, 2))))) rounds" + (byes > 0 ? " · \(byes) bye\(byes == 1 ? "" : "s")" : "")
        case (.pairs, .stroke):
            return "\(n / 2) pairs · \(s.pairFormat.rawValue) stroke play · \(rounds)"
        case (.teams, .match):
            let total = Double(cupGames(s).count)
            return "\(s.team(0).count) v \(s.team(1).count) · \(s.sessions.map { $0.label.lowercased() }.joined(separator: ", ")) · "
                + "\(formatPoints(total)) points, \(formatPoints(total / 2 + 0.5)) to win"
        case (.teams, .stroke):
            return "\(s.team(0).count) v \(s.team(1).count) · \(s.teamStroke == .best2 ? "best 2 scores per hole" : "every score counts") · \(rounds)"
        }
    }

    static func allowanceText(_ s: TourSetup) -> String {
        guard s.basis == .net else { return "Gross: off scratch, no strokes" }
        switch (s.mode, s.scoring) {
        case (.individual, .stroke), (.teams, .stroke): return "95% of course handicap"
        case (.individual, .match): return "100% of the difference"
        case (.pairs, _):
            switch s.pairFormat {
            case .fourball: return s.scoring == .stroke ? "85% each player" : "90% each player, off the lowest"
            case .foursomes: return "50% of the pair's combined handicap"
            case .scramble: return "35% of the lower, 15% of the higher"
            }
        case (.teams, .match): return "Fourballs 90%, foursomes 50% combined, singles 100% of the difference"
        }
    }

    /// 7.5 → "7½"
    static func formatPoints(_ x: Double) -> String {
        let whole = Int(x.rounded(.down))
        let half = x - Double(whole) >= 0.5
        if whole == 0 && half { return "½" }
        return "\(whole)" + (half ? "½" : "")
    }
}
