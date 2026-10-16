import Foundation
import Supabase

// MARK: - What's stored on the server

struct MatchDTO: Codable, Identifiable, Sendable {
    let id: UUID
    var createdBy: UUID
    var format: String
    var basis: String
    var allowance: String
    var courseName: String
    var courseRating: Double
    var slope: Int
    var holes: [MatchHoleInfo]
    var status: String
    var playedOn: String

    enum CodingKeys: String, CodingKey {
        case id, format, basis, allowance, slope, holes, status
        case createdBy = "created_by"
        case courseName = "course_name"
        case courseRating = "course_rating"
        case playedOn = "played_on"
    }
}

struct MatchPlayerDTO: Codable, Hashable, Sendable {
    var matchID: UUID
    var playerKey: String
    var userID: UUID?
    var name: String
    var handicapIndex: Double?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name
        case matchID = "match_id"
        case playerKey = "player_key"
        case userID = "user_id"
        case handicapIndex = "handicap_index"
        case sortOrder = "sort_order"
    }
}

struct MatchScoreDTO: Codable, Sendable {
    var matchID: UUID
    var playerKey: String
    var hole: Int
    var strokes: Int

    enum CodingKeys: String, CodingKey {
        case hole, strokes
        case matchID = "match_id"
        case playerKey = "player_key"
    }
}

/// A match with its players and every score entered so far.
struct LiveMatch: Identifiable {
    var match: MatchDTO
    var players: [MatchPlayerDTO]
    var scores: ScoreTable

    var id: UUID { match.id }
    var format: MatchFormat { MatchFormat(rawValue: match.format) ?? .stroke }
    var isLive: Bool { match.status == "live" }
    var date: Date { SharedRoundDTO.dayFormatter.date(from: match.playedOn) ?? .distantPast }

    var setup: MatchSetup {
        MatchSetup(format: format,
                   basis: HandicapBasis(rawValue: match.basis) ?? .net,
                   allowance: AllowanceRule(rawValue: match.allowance) ?? .full,
                   holes: match.holes,
                   courseRating: match.courseRating,
                   slope: match.slope,
                   players: players.sorted { $0.sortOrder < $1.sortOrder }
                       .map { MatchPlayerInfo(key: $0.playerKey, name: $0.name, handicapIndex: $0.handicapIndex) })
    }

    var outcome: MatchOutcome { MatchEngine.outcome(setup, scores) }

    func key(for user: UUID) -> String? {
        players.first { $0.userID == user }?.playerKey
    }

    /// How `me` did against `other` in this match.
    func result(_ me: UUID, against other: UUID) -> PairResult? {
        guard let a = key(for: me), let b = key(for: other) else { return nil }
        return MatchEngine.pairResult(setup, scores, a, b)
    }

    var playerNames: String {
        players.sorted { $0.sortOrder < $1.sortOrder }.map(\.name).joined(separator: ", ")
    }
}

// MARK: - Server calls

extension SupabaseAPI {
    func createMatch(_ match: MatchDTO, players: [MatchPlayerDTO]) async throws {
        try await client.from("matches").insert(match).execute()
        try await client.from("match_players").insert(players).execute()
    }

    func matches() async throws -> [MatchDTO] {
        try await client.from("matches").select()
            .order("played_on", ascending: false)
            .order("created_at", ascending: false)
            .limit(100)
            .execute().value
    }

    func matchPlayers(_ ids: [UUID]) async throws -> [MatchPlayerDTO] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("match_players").select()
            .in("match_id", values: ids.map(\.uuidString)).execute().value
    }

    /// Reads every score, 1,000 rows at a time (the server's page size).
    func matchScores(_ ids: [UUID]) async throws -> [MatchScoreDTO] {
        guard !ids.isEmpty else { return [] }
        var all: [MatchScoreDTO] = []
        var from = 0
        let page = 1000
        while true {
            let chunk: [MatchScoreDTO] = try await client.from("match_scores").select()
                .in("match_id", values: ids.map(\.uuidString))
                .order("match_id").order("player_key").order("hole")
                .range(from: from, to: from + page - 1)
                .execute().value
            all += chunk
            if chunk.count < page { return all }
            from += page
        }
    }

    func saveScores(_ scores: [MatchScoreDTO]) async throws {
        try await client.from("match_scores").upsert(scores).execute()
    }

    func setMatchStatus(_ id: UUID, _ status: String) async throws {
        try await client.from("matches").update(["status": status]).eq("id", value: id.uuidString).execute()
    }

    func deleteMatch(_ id: UUID) async throws {
        try await client.from("matches").delete().eq("id", value: id.uuidString).execute()
    }
}

// MARK: - App side

extension Backend {
    static func table(_ scores: [MatchScoreDTO]) -> ScoreTable {
        var table: ScoreTable = [:]
        for s in scores { table[s.playerKey, default: [:]][s.hole] = s.strokes }
        return table
    }

    func refreshMatches() async {
        guard status == .signedIn, let api else { return }
        do {
            let list = try await api.matches()
            let ids = list.map(\.id)
            let players = Dictionary(grouping: try await api.matchPlayers(ids), by: \.matchID)
            let scores = Dictionary(grouping: try await api.matchScores(ids), by: \.matchID)
            matches = list.map { LiveMatch(match: $0, players: players[$0.id] ?? [], scores: Backend.table(scores[$0.id] ?? [])) }
        } catch {
            message = friendly(error)
        }
    }

    /// Reloads one match's scores and status (used every few seconds while a match is open).
    func refreshMatch(_ id: UUID) async {
        guard status == .signedIn, let api, let i = matches.firstIndex(where: { $0.id == id }) else { return }
        do {
            let scores = try await api.matchScores([id])
            let latest = try await api.matches().first { $0.id == id }
            guard let j = matches.firstIndex(where: { $0.id == id }), j == i else { return }
            matches[j].scores = Backend.table(scores)
            if let latest { matches[j].match = latest }
        } catch {
            message = friendly(error)
        }
    }

    struct NewPlayer: Identifiable, Hashable {
        var id = UUID()
        var userID: UUID?
        var name: String
        var handicapIndex: Double?
    }

    /// Sets up a match on the server. Returns its id.
    func createMatch(format: MatchFormat, basis: HandicapBasis, allowance: AllowanceRule,
                     course: Course, players: [NewPlayer]) async -> UUID? {
        var created: UUID?
        await run { api in
            guard let me = self.userID else { return }
            let id = UUID()
            let holes = course.holes.sorted { $0.number < $1.number }
                .map { MatchHoleInfo(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex) }
            let match = MatchDTO(id: id, createdBy: me, format: format.rawValue, basis: basis.rawValue,
                                 allowance: allowance.rawValue, courseName: course.name,
                                 courseRating: course.courseRating, slope: course.slope, holes: holes,
                                 status: "live", playedOn: SharedRoundDTO.dayFormatter.string(from: .now))
            let rows = players.enumerated().map { i, p in
                MatchPlayerDTO(matchID: id, playerKey: p.userID?.uuidString ?? "guest-\(p.id.uuidString)",
                               userID: p.userID, name: p.name,
                               handicapIndex: p.handicapIndex.map { ($0 * 10).rounded() / 10 }, sortOrder: i)
            }
            try await api.createMatch(match, players: rows)
            created = id
            await self.refreshMatches()
        }
        return created
    }

    func saveHole(_ matchID: UUID, hole: Int, strokes: [String: Int]) async {
        await run { api in
            let rows = strokes.map { MatchScoreDTO(matchID: matchID, playerKey: $0.key, hole: hole, strokes: $0.value) }
            try await api.saveScores(rows)
            if let i = self.matches.firstIndex(where: { $0.id == matchID }) {
                for (key, value) in strokes { self.matches[i].scores[key, default: [:]][hole] = value }
            }
        }
    }

    func finishMatch(_ matchID: UUID) async {
        await run { api in
            try await api.setMatchStatus(matchID, "finished")
            if let i = self.matches.firstIndex(where: { $0.id == matchID }) { self.matches[i].match.status = "finished" }
        }
    }

    func deleteMatch(_ matchID: UUID) async {
        await run { api in
            try await api.deleteMatch(matchID)
            self.matches.removeAll { $0.id == matchID }
        }
    }

    /// Your all-time record against one friend, from every finished match you both played.
    func rivalry(with friend: UUID) -> (record: RivalryRecord, matches: [LiveMatch]) {
        guard let me = userID else { return (RivalryRecord(), []) }
        let shared = matches.filter { !$0.isLive && $0.key(for: me) != nil && $0.key(for: friend) != nil }
            .sorted { $0.date > $1.date }
        let results = shared.compactMap { m in m.result(me, against: friend).map { (m.format, $0) } }
        return (RivalryRecord.build(results), shared)
    }

    #if DEBUG
    /// Demo matches for the CI screenshot, using the demo friends.
    func loadDemoMatches() {
        guard let me = profile, friends.count >= 2 else { return }
        let dave = friends[1], tom = friends[0]
        let pars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
        let sis = [7, 3, 15, 11, 1, 9, 17, 5, 13, 8, 16, 2, 12, 6, 10, 18, 4, 14]
        let holes = (0..<18).map { MatchHoleInfo(number: $0 + 1, par: pars[$0], strokeIndex: sis[$0]) }
        var rng = SeededGenerator(seed: 21)

        func make(_ format: MatchFormat, _ opponents: [ProfileDTO], daysAgo: Double, holesPlayed: Int, live: Bool) -> LiveMatch {
            let id = UUID()
            let everyone = [me] + opponents
            let players = everyone.enumerated().map { i, p in
                MatchPlayerDTO(matchID: id, playerKey: p.id.uuidString, userID: p.id, name: p.id == me.id ? "You" : p.displayName,
                               handicapIndex: [5.3, 4.8, 9.0][min(i, 2)], sortOrder: i)
            }
            var scores: ScoreTable = [:]
            for p in players {
                for h in holes.prefix(holesPlayed) {
                    let r = Double.random(in: 0..<1, using: &rng)
                    scores[p.playerKey, default: [:]][h.number] = h.par + (r < 0.15 ? -1 : (r < 0.6 ? 0 : (r < 0.92 ? 1 : 2)))
                }
            }
            let match = MatchDTO(id: id, createdBy: me.id, format: format.rawValue, basis: "net", allowance: "full",
                                 courseName: "Demo Golf Club", courseRating: 71.8, slope: 128, holes: holes,
                                 status: live ? "live" : "finished",
                                 playedOn: SharedRoundDTO.dayFormatter.string(from: Date.now.addingTimeInterval(-daysAgo * 86_400)))
            return LiveMatch(match: match, players: players, scores: scores)
        }

        var list = [make(.nassau, [dave], daysAgo: 0, holesPlayed: 11, live: true)]
        let formats: [MatchFormat] = [.matchplay, .nassau, .stroke, .matchplay, .stableford, .nassau, .matchplay, .skins]
        for (i, f) in formats.enumerated() {
            list.append(make(f, [dave], daysAgo: Double(7 + i * 9), holesPlayed: 18, live: false))
        }
        list.append(make(.skins, [tom, dave], daysAgo: 3, holesPlayed: 18, live: false))
        matches = list
    }
    #endif
}
