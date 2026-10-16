import Foundation
import Supabase

// MARK: - What's stored on the server

struct TournamentDTO: Codable, Identifiable, Sendable {
    let id: UUID
    var createdBy: UUID
    var name: String
    var scoring: String
    var mode: String
    var pairFormat: String
    var teamStroke: String
    var sessions: [String]
    var teamNames: [String]
    var basis: String
    var rounds: Int
    var courseName: String
    var courseRating: Double
    var slope: Int
    var holes: [MatchHoleInfo]
    var status: String
    var joinCode: String
    var playedOn: String

    enum CodingKeys: String, CodingKey {
        case id, name, scoring, mode, sessions, basis, rounds, slope, holes, status
        case createdBy = "created_by"
        case pairFormat = "pair_format"
        case teamStroke = "team_stroke"
        case teamNames = "team_names"
        case courseName = "course_name"
        case courseRating = "course_rating"
        case joinCode = "join_code"
        case playedOn = "played_on"
    }

    /// Six letters and numbers that are easy to read out (no 0/O or 1/I).
    static func makeCode() -> String {
        let letters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        return String((0..<6).map { _ in letters.randomElement()! })
    }
}

struct TournamentPlayerDTO: Codable, Hashable, Sendable {
    var tournamentID: UUID
    var playerKey: String
    var userID: UUID?
    var name: String
    var handicapIndex: Double?
    var team: Int?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case name, team
        case tournamentID = "tournament_id"
        case playerKey = "player_key"
        case userID = "user_id"
        case handicapIndex = "handicap_index"
        case sortOrder = "sort_order"
    }
}

struct TournamentScoreDTO: Codable, Sendable {
    var tournamentID: UUID
    var game: String
    var unit: String
    var hole: Int
    var strokes: Int
    var updatedAt: String?  // read only; the server sets it

    enum CodingKeys: String, CodingKey {
        case game, unit, hole, strokes
        case tournamentID = "tournament_id"
        case updatedAt = "updated_at"
    }

    private static let withFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    var time: Date {
        guard let updatedAt else { return .distantPast }
        return Self.withFraction.date(from: updatedAt) ?? ISO8601DateFormatter().date(from: updatedAt) ?? .distantPast
    }
}

/// Only the fields the organiser changes while setting the draw. A nil team is sent as null.
private struct PlacementDTO: Encodable, Sendable {
    var team: Int?
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case team
        case sortOrder = "sort_order"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(team, forKey: .team)
        try c.encode(sortOrder, forKey: .sortOrder)
    }
}

private struct JoinParams: Encodable, Sendable {
    var code: String
    var player_name: String
    var player_index: Double?

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(player_name, forKey: .player_name)
        try c.encode(player_index, forKey: .player_index)
    }

    enum CodingKeys: String, CodingKey { case code, player_name, player_index }
}

/// A tournament with its players and every score entered so far.
struct LiveTournament: Identifiable {
    var tournament: TournamentDTO
    var players: [TournamentPlayerDTO]
    var scores: [TournamentScoreDTO]

    var id: UUID { tournament.id }
    var status: String { tournament.status }
    var isLive: Bool { status == "live" }
    var isSetup: Bool { status == "setup" }
    var date: Date { SharedRoundDTO.dayFormatter.date(from: tournament.playedOn) ?? .distantPast }
    var sortedPlayers: [TournamentPlayerDTO] { players.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }

    var setup: TourSetup {
        let t = tournament
        return TourSetup(scoring: TourScoring(rawValue: t.scoring) ?? .stroke,
                         mode: TourMode(rawValue: t.mode) ?? .individual,
                         pairFormat: PairFormat(rawValue: t.pairFormat) ?? .fourball,
                         teamStroke: TeamStroke(rawValue: t.teamStroke) ?? .best2,
                         basis: HandicapBasis(rawValue: t.basis) ?? .net,
                         holes: t.holes, courseRating: t.courseRating, slope: t.slope, rounds: t.rounds,
                         sessions: t.sessions.compactMap(CupSession.init(rawValue:)),
                         players: sortedPlayers.map { TourPlayer(key: $0.playerKey, name: $0.name, handicapIndex: $0.handicapIndex, team: $0.team) },
                         teamNames: t.teamNames.count == 2 ? t.teamNames : ["Team Blue", "Team Orange"])
    }

    var table: TourScores {
        var out: TourScores = [:]
        for s in scores { out[s.game, default: [:]][s.unit, default: [:]][s.hole] = s.strokes }
        return out
    }

    var events: [TourScoreEvent] {
        scores.map { TourScoreEvent(game: $0.game, unit: $0.unit, hole: $0.hole, strokes: $0.strokes, time: $0.time) }
    }

    func key(for user: UUID) -> String? { players.first { $0.userID == user }?.playerKey }

    /// One line for lists: the leader, the cup score or how far the knockout has got.
    var headline: String {
        let s = setup
        if isSetup { return "\(players.count) players · code \(tournament.joinCode)" }
        switch (s.scoring, s.mode) {
        case (.stroke, _):
            guard let top = TournamentEngine.leaderboard(s, table).rows.first, let total = top.total else { return "No scores yet" }
            return "\(status == "finished" ? "Winner" : "Leader"): \(top.name) \(MatchEngine.toParText(total))"
        case (.match, .teams):
            let cup = TournamentEngine.cup(s, table)
            return "\(s.teamNames[0]) \(TournamentEngine.formatPoints(cup.points[0])) – \(TournamentEngine.formatPoints(cup.points[1])) \(s.teamNames[1])"
        case (.match, _):
            let b = TournamentEngine.bracket(s, table)
            if let champ = b.champion { return "Winner: \(champ.name)" }
            let round = b.rounds.firstIndex { $0.contains { !$0.isBye && $0.winner == nil } }.map { b.title($0 + 1) } ?? ""
            return round.isEmpty ? "Knockout" : "Knockout · \(round)"
        }
    }

    var formatLine: String {
        let s = setup
        var parts = [s.scoring.label]
        switch s.mode {
        case .individual: parts.append("individual")
        case .pairs: parts.append("pairs \(s.pairFormat.rawValue)")
        case .teams: parts.append("two teams")
        }
        parts.append(s.basis == .net ? "net" : "gross")
        return parts.joined(separator: " · ")
    }
}

// MARK: - Server calls

extension SupabaseAPI {
    func createTournament(_ t: TournamentDTO, players: [TournamentPlayerDTO]) async throws {
        try await client.from("tournaments").insert(t).execute()
        if !players.isEmpty { try await client.from("tournament_players").insert(players).execute() }
    }

    func tournaments() async throws -> [TournamentDTO] {
        try await client.from("tournaments").select()
            .order("played_on", ascending: false)
            .order("created_at", ascending: false)
            .limit(50)
            .execute().value
    }

    func tournamentPlayers(_ ids: [UUID]) async throws -> [TournamentPlayerDTO] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("tournament_players").select()
            .in("tournament_id", values: ids.map(\.uuidString)).execute().value
    }

    /// Reads every score, 1,000 rows at a time (the server's page size).
    func tournamentScores(_ ids: [UUID]) async throws -> [TournamentScoreDTO] {
        guard !ids.isEmpty else { return [] }
        var all: [TournamentScoreDTO] = []
        var from = 0
        let page = 1000
        while true {
            let chunk: [TournamentScoreDTO] = try await client.from("tournament_scores").select()
                .in("tournament_id", values: ids.map(\.uuidString))
                .order("tournament_id").order("game").order("unit").order("hole")
                .range(from: from, to: from + page - 1)
                .execute().value
            all += chunk
            if chunk.count < page { return all }
            from += page
        }
    }

    func saveTournamentScores(_ scores: [TournamentScoreDTO]) async throws {
        try await client.from("tournament_scores").upsert(scores).execute()
    }

    func addTournamentPlayers(_ players: [TournamentPlayerDTO]) async throws {
        try await client.from("tournament_players").insert(players).execute()
    }

    func placePlayer(_ id: UUID, key: String, team: Int?, sortOrder: Int) async throws {
        try await client.from("tournament_players").update(PlacementDTO(team: team, sortOrder: sortOrder))
            .eq("tournament_id", value: id.uuidString).eq("player_key", value: key).execute()
    }

    func removeTournamentPlayer(_ id: UUID, key: String) async throws {
        try await client.from("tournament_players").delete()
            .eq("tournament_id", value: id.uuidString).eq("player_key", value: key).execute()
    }

    func setTournamentStatus(_ id: UUID, _ status: String) async throws {
        try await client.from("tournaments").update(["status": status]).eq("id", value: id.uuidString).execute()
    }

    func deleteTournament(_ id: UUID) async throws {
        try await client.from("tournaments").delete().eq("id", value: id.uuidString).execute()
    }

    func joinTournament(code: String, name: String, index: Double?) async throws -> UUID? {
        let value: String = try await client.rpc("join_tournament", params: JoinParams(code: code, player_name: name, player_index: index))
            .execute().value
        return UUID(uuidString: value)
    }
}

// MARK: - App side

extension Backend {
    func refreshTournaments() async {
        guard status == .signedIn, let api else { return }
        do {
            let list = try await api.tournaments()
            let ids = list.map(\.id)
            let players = Dictionary(grouping: try await api.tournamentPlayers(ids), by: \.tournamentID)
            let scores = Dictionary(grouping: try await api.tournamentScores(ids), by: \.tournamentID)
            tournaments = list.map { LiveTournament(tournament: $0, players: players[$0.id] ?? [], scores: scores[$0.id] ?? []) }
        } catch {
            message = friendly(error)
        }
    }

    /// Reloads one tournament (used every few seconds while it's open).
    func refreshTournament(_ id: UUID) async {
        guard status == .signedIn, let api, tournaments.contains(where: { $0.id == id }) else { return }
        do {
            let latest = try await api.tournaments().first { $0.id == id }
            let players = try await api.tournamentPlayers([id])
            let scores = try await api.tournamentScores([id])
            guard let i = tournaments.firstIndex(where: { $0.id == id }) else { return }
            if let latest {
                tournaments[i] = LiveTournament(tournament: latest, players: players, scores: scores)
            } else {
                tournaments.remove(at: i)  // deleted by the organiser
            }
        } catch {
            message = friendly(error)
        }
    }

    struct TournamentOptions {
        var name: String
        var scoring: TourScoring
        var mode: TourMode
        var pairFormat: PairFormat
        var teamStroke: TeamStroke
        var sessions: [CupSession]
        var teamNames: [String]
        var basis: HandicapBasis
        var rounds: Int
    }

    func createTournament(_ o: TournamentOptions, course: Course, players: [NewPlayer]) async -> UUID? {
        var created: UUID?
        await run { api in
            guard let me = self.userID else { return }
            let id = UUID()
            let holes = course.holes.sorted { $0.number < $1.number }
                .map { MatchHoleInfo(number: $0.number, par: $0.par, strokeIndex: $0.strokeIndex) }
            let t = TournamentDTO(id: id, createdBy: me, name: o.name, scoring: o.scoring.rawValue, mode: o.mode.rawValue,
                                  pairFormat: o.pairFormat.rawValue, teamStroke: o.teamStroke.rawValue,
                                  sessions: o.sessions.map(\.rawValue), teamNames: o.teamNames, basis: o.basis.rawValue,
                                  rounds: o.scoring == .stroke ? o.rounds : 1, courseName: course.name,
                                  courseRating: course.courseRating, slope: course.slope, holes: holes, status: "setup",
                                  joinCode: TournamentDTO.makeCode(),
                                  playedOn: SharedRoundDTO.dayFormatter.string(from: .now))
            let rows = players.enumerated().map { i, p in
                TournamentPlayerDTO(tournamentID: id, playerKey: p.userID?.uuidString ?? "guest-\(p.id.uuidString)",
                                    userID: p.userID, name: p.name,
                                    handicapIndex: p.handicapIndex.map { ($0 * 10).rounded() / 10 },
                                    team: o.mode == .teams ? i % 2 : nil, sortOrder: i)
            }
            try await api.createTournament(t, players: rows)
            created = id
            await self.refreshTournaments()
        }
        return created
    }

    func addGuest(to id: UUID, name: String, index: Double?) async {
        await run { api in
            guard let t = self.tournaments.first(where: { $0.id == id }) else { return }
            let order = (t.players.map(\.sortOrder).max() ?? -1) + 1
            let row = TournamentPlayerDTO(tournamentID: id, playerKey: "guest-\(UUID().uuidString)", userID: nil, name: name,
                                          handicapIndex: index.map { ($0 * 10).rounded() / 10 },
                                          team: t.setup.mode == .teams ? order % 2 : nil, sortOrder: order)
            try await api.addTournamentPlayers([row])
            await self.refreshTournament(id)
        }
    }

    /// Saves a new draw: the order of players and, for team events, who is on which team.
    func saveDraw(_ id: UUID, _ players: [TournamentPlayerDTO]) async {
        await run { api in
            guard let i = self.tournaments.firstIndex(where: { $0.id == id }) else { return }
            let old = Dictionary(uniqueKeysWithValues: self.tournaments[i].players.map { ($0.playerKey, $0) })
            var updated = players
            for n in updated.indices { updated[n].sortOrder = n }
            self.tournaments[i].players = updated
            for p in updated where old[p.playerKey]?.sortOrder != p.sortOrder || old[p.playerKey]?.team != p.team {
                try await api.placePlayer(id, key: p.playerKey, team: p.team, sortOrder: p.sortOrder)
            }
        }
    }

    func removePlayer(_ id: UUID, key: String) async {
        await run { api in
            try await api.removeTournamentPlayer(id, key: key)
            if let i = self.tournaments.firstIndex(where: { $0.id == id }) {
                self.tournaments[i].players.removeAll { $0.playerKey == key }
            }
        }
    }

    func setTournamentStatus(_ id: UUID, _ status: String) async {
        await run { api in
            try await api.setTournamentStatus(id, status)
            if let i = self.tournaments.firstIndex(where: { $0.id == id }) { self.tournaments[i].tournament.status = status }
        }
    }

    func saveTournamentHole(_ id: UUID, game: String, hole: Int, strokes: [String: Int]) async {
        await run { api in
            let rows = strokes.map { TournamentScoreDTO(tournamentID: id, game: game, unit: $0.key, hole: hole, strokes: $0.value) }
            try await api.saveTournamentScores(rows)
            guard let i = self.tournaments.firstIndex(where: { $0.id == id }) else { return }
            let now = ISO8601DateFormatter().string(from: .now)
            for row in rows {
                self.tournaments[i].scores.removeAll { $0.game == row.game && $0.unit == row.unit && $0.hole == row.hole }
                var stamped = row
                stamped.updatedAt = now
                self.tournaments[i].scores.append(stamped)
            }
        }
    }

    func deleteTournament(_ id: UUID) async {
        await run { api in
            try await api.deleteTournament(id)
            self.tournaments.removeAll { $0.id == id }
        }
    }

    /// Joins with a code from the organiser. Returns the tournament id.
    func joinTournament(code: String, index: Double?) async -> UUID? {
        var joined: UUID?
        await run { api in
            guard let me = self.profile else { return }
            let clean = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            joined = try await api.joinTournament(code: clean, name: me.displayName, index: index.map { ($0 * 10).rounded() / 10 })
            await self.refreshTournaments()
        }
        return joined
    }

    #if DEBUG
    /// Demo tournaments for the CI screenshots: a stroke play event, a team cup and a knockout.
    func loadDemoTournaments() {
        guard let me = profile else { return }
        let pars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
        let sis = [7, 3, 15, 11, 1, 9, 17, 5, 13, 8, 16, 2, 12, 6, 10, 18, 4, 14]
        let holes = (0..<18).map { MatchHoleInfo(number: $0 + 1, par: pars[$0], strokeIndex: sis[$0]) }
        var rng = SeededGenerator(seed: 33)
        let names = ["You", "Tom", "Dave", "Jack", "Sam", "Ollie", "Ben", "Chris", "Luke", "Harry",
                     "Rob", "Alex", "Matt", "James", "Will", "Dan"]
        let indexes = [7.2, 4.8, 9.0, 11.4, 14.7, 20.1, 3.1, 6.0, 12.8, 16.5, 8.3, 10.2, 5.5, 13.0, 18.4, 2.4]

        /// Random scores for every ready group that has none yet. A halved knockout match is settled on the 19th.
        func fill(_ live: inout LiveTournament, progress: [String: Int]) {
            let start = Date.now.addingTimeInterval(-3 * 3600)
            let stamp = ISO8601DateFormatter()
            for (g, group) in TournamentEngine.scoringGroups(live.setup, live.table).enumerated() {
                let unitKeys = Set(group.units.map(\.key))
                let existing = live.scores.filter { $0.game == group.game && unitKeys.contains($0.unit) }
                if !existing.isEmpty {
                    if group.holes.count > live.setup.holes.count, let extra = group.holes.last,
                       !existing.contains(where: { $0.hole == extra.number }) {
                        for (u, unit) in group.units.enumerated() {
                            live.scores.append(TournamentScoreDTO(tournamentID: live.id, game: group.game, unit: unit.key,
                                                                  hole: extra.number, strokes: extra.par - (u == 0 ? 1 : 0),
                                                                  updatedAt: stamp.string(from: .now)))
                        }
                    }
                    continue
                }
                var played = progress[group.game] ?? 0
                if live.setup.scoring == .stroke && group.game != "r1" { played = max(0, played - (g % 3) * 2) }
                for (u, unit) in group.units.enumerated() {
                    let skill = 0.25 + Double(max(0, unit.handicap)) / 30
                    for (h, hole) in group.holes.prefix(played).enumerated() {
                        let r = Double.random(in: 0..<1, using: &rng)
                        let over = r < 0.12 ? -1 : (r < 0.12 + max(0, 0.75 - skill) ? 0 : (r < 0.9 ? 1 : 2))
                        let time = start.addingTimeInterval(Double(h * 600 + u * 30 + g * 7))
                        live.scores.append(TournamentScoreDTO(tournamentID: live.id, game: group.game, unit: unit.key,
                                                              hole: hole.number, strokes: hole.par + over,
                                                              updatedAt: stamp.string(from: time)))
                    }
                }
            }
        }

        func make(_ name: String, scoring: TourScoring, mode: TourMode, count: Int, rounds: Int = 1,
                  pairFormat: PairFormat = .fourball, status: String = "live", progress: [String: Int]) -> LiveTournament {
            let id = UUID()
            let players = (0..<count).map { i in
                TournamentPlayerDTO(tournamentID: id, playerKey: i == 0 ? me.id.uuidString : "guest-\(i)",
                                    userID: i == 0 ? me.id : nil, name: names[i], handicapIndex: indexes[i],
                                    team: mode == .teams ? i % 2 : nil, sortOrder: mode == .teams ? i / 2 : i)
            }
            let t = TournamentDTO(id: id, createdBy: me.id, name: name, scoring: scoring.rawValue, mode: mode.rawValue,
                                  pairFormat: pairFormat.rawValue, teamStroke: "best2", sessions: CupSession.allCases.map(\.rawValue),
                                  teamNames: ["Team Blue", "Team Orange"], basis: "net", rounds: rounds,
                                  courseName: "Demo Golf Club", courseRating: 71.8, slope: 128, holes: holes,
                                  status: status, joinCode: "DEMO42", playedOn: SharedRoundDTO.dayFormatter.string(from: .now))
            var live = LiveTournament(tournament: t, players: players, scores: [])
            fill(&live, progress: progress)
            return live
        }


        let championship = make("Club Championship", scoring: .stroke, mode: .individual, count: 10, rounds: 2,
                                progress: ["r1": 18, "r2": 15])
        let cup = make("Autumn Cup", scoring: .match, mode: .teams, count: 16,
                       progress: ["fb1": 18, "fb2": 18, "fb3": 18, "fb4": 18, "fs1": 18, "fs2": 18, "fs3": 18, "fs4": 18,
                                  "s1": 14, "s2": 18, "s3": 18, "s4": 15, "s5": 13, "s6": 18, "s7": 18])
        // Later knockout rounds only exist once earlier ones finish, so fill a few passes.
        var knockout = make("Matchplay Knockout", scoring: .match, mode: .individual, count: 6,
                            progress: ["k1-2": 18, "k1-4": 18])
        for _ in 0..<4 { fill(&knockout, progress: ["k2-1": 18, "k2-2": 10]) }
        let lobby = make("Saturday Fourball", scoring: .stroke, mode: .pairs, count: 8, status: "setup", progress: [:])
        tournaments = [cup, championship, knockout, lobby]
    }
    #endif
}
