import Foundation
import Supabase
import SwiftData

// MARK: - What's stored on the server

struct ProfileDTO: Codable, Identifiable, Hashable {
    let id: UUID
    var username: String
    var displayName: String
    var statsVisibility: String

    enum CodingKeys: String, CodingKey {
        case id, username
        case displayName = "display_name"
        case statsVisibility = "stats_visibility"
    }

    var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap(\.first)
        return letters.isEmpty ? String(username.prefix(2)).uppercased() : String(letters).uppercased()
    }
}

struct FriendshipDTO: Codable, Hashable {
    let requester: UUID
    let addressee: UUID
    var status: String
}

struct SharedHole: Codable {
    var number: Int
    var par: Int
    var strokeIndex: Int
    var strokes: Int
    var putts: Int
    var firstPuttFeet: Int?
    var fairway: String?
    var green: String?
    var upAndDown: Bool?
    var penalties: Int
}

struct SharedRoundDTO: Codable, Identifiable {
    let id: UUID
    var userID: UUID
    var playedOn: String  // yyyy-MM-dd
    var courseName: String
    var teeName: String
    var courseRating: Double
    var slope: Int
    var handicapIndexAtStart: Double?
    var mode: String
    var holes: [SharedHole]

    enum CodingKeys: String, CodingKey {
        case id, slope, mode, holes
        case userID = "user_id"
        case playedOn = "played_on"
        case courseName = "course_name"
        case teeName = "tee_name"
        case courseRating = "course_rating"
        case handicapIndexAtStart = "handicap_index_at_start"
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    var date: Date { Self.dayFormatter.date(from: playedOn) ?? .distantPast }
    var strokes: Int { holes.reduce(0) { $0 + $1.strokes } }
    var toPar: Int { holes.reduce(0) { $0 + $1.strokes - $1.par } }

    var data: RoundData {
        RoundData(
            date: date, courseRating: courseRating, slope: slope, handicapIndex: handicapIndexAtStart,
            holes: holes.map { h in
                HoleData(par: h.par, strokeIndex: h.strokeIndex, strokes: h.strokes, putts: h.putts,
                         firstPuttFeet: h.firstPuttFeet, fairway: h.fairway.flatMap(FairwayResult.init(rawValue:)),
                         green: h.green.flatMap(GreenResult.init(rawValue:)), upAndDown: h.upAndDown,
                         penalties: h.penalties)
            }
        )
    }

    init(id: UUID, userID: UUID, playedOn: Date, courseName: String, teeName: String, courseRating: Double,
         slope: Int, handicapIndexAtStart: Double?, mode: String, holes: [SharedHole]) {
        self.id = id
        self.userID = userID
        self.playedOn = Self.dayFormatter.string(from: playedOn)
        self.courseName = courseName
        self.teeName = teeName
        self.courseRating = courseRating
        self.slope = slope
        self.handicapIndexAtStart = handicapIndexAtStart
        self.mode = mode
        self.holes = holes
    }

    init(round: Round, id: UUID, userID: UUID) {
        let holes: [SharedHole] = round.enteredScores.compactMap { score in
            guard let hole = round.hole(score.number) else { return nil }
            return SharedHole(number: score.number, par: hole.par, strokeIndex: hole.strokeIndex,
                              strokes: score.strokes, putts: score.putts,
                              firstPuttFeet: score.firstPuttFeet > 0 ? score.firstPuttFeet : nil,
                              fairway: hole.par >= 4 ? score.fairway : nil, green: score.green,
                              upAndDown: score.greenResult == .hit ? nil : score.upAndDown,
                              penalties: score.penalties)
        }
        self.init(id: id, userID: userID, playedOn: round.playedOn, courseName: round.courseName,
                  teeName: round.teeName, courseRating: round.courseRating, slope: round.slope,
                  handicapIndexAtStart: round.handicapIndexAtStart, mode: round.mode, holes: holes)
    }
}

// MARK: - Connection to Supabase

/// Accounts, friends and shared rounds. Everything else in the app works without it.
@MainActor
final class Backend: ObservableObject {
    static let shared = Backend()

    enum Status: Equatable {
        case notConfigured, signedOut, needsProfile, signedIn
    }

    @Published private(set) var status: Status = .notConfigured
    @Published private(set) var profile: ProfileDTO?
    @Published private(set) var friends: [ProfileDTO] = []
    @Published private(set) var incoming: [ProfileDTO] = []
    @Published private(set) var outgoing: [ProfileDTO] = []
    @Published private(set) var rounds: [UUID: [SharedRoundDTO]] = [:]
    @Published private(set) var isBusy = false
    @Published var message: String?

    private var client: SupabaseClient?
    private var userID: UUID?

    private static let urlKey = "supabaseURL"
    private static let keyKey = "supabaseKey"

    init() {
        connectFromSavedSettings()
    }

    // MARK: Setup

    /// Saves the project URL and publishable key the player pasted in. Returns false if they don't look right.
    func connect(url: String, key: String) -> Bool {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = URL(string: cleanURL), parsed.scheme == "https", parsed.host != nil, cleanKey.count > 20 else {
            return false
        }
        UserDefaults.standard.set(cleanURL, forKey: Self.urlKey)
        UserDefaults.standard.set(cleanKey, forKey: Self.keyKey)
        connectFromSavedSettings()
        return true
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.urlKey)
        UserDefaults.standard.removeObject(forKey: Self.keyKey)
        client = nil
        clearAccount()
        status = .notConfigured
    }

    private func connectFromSavedSettings() {
        guard let saved = UserDefaults.standard.string(forKey: Self.urlKey), let url = URL(string: saved),
              let key = UserDefaults.standard.string(forKey: Self.keyKey) else {
            status = .notConfigured
            return
        }
        client = SupabaseClient(supabaseURL: url, supabaseKey: key)
        status = .signedOut
        Task { await restoreSession() }
    }

    private func clearAccount() {
        userID = nil
        profile = nil
        friends = []
        incoming = []
        outgoing = []
        rounds = [:]
    }

    // MARK: Account

    func restoreSession() async {
        guard let client else { return }
        guard let session = try? await client.auth.session else {
            status = .signedOut
            return
        }
        userID = session.user.id
        await loadProfile()
    }

    func signUp(email: String, password: String) async {
        await run {
            guard let client = self.client else { return }
            let response = try await client.auth.signUp(email: email, password: password)
            if let session = response.session {
                self.userID = session.user.id
                await self.loadProfile()
            } else {
                self.message = "Check your email and tap the confirm link, then sign in."
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run {
            guard let client = self.client else { return }
            let session = try await client.auth.signIn(email: email, password: password)
            self.userID = session.user.id
            await self.loadProfile()
        }
    }

    func signOut() async {
        try? await client?.auth.signOut()
        clearAccount()
        status = client == nil ? .notConfigured : .signedOut
    }

    private func loadProfile() async {
        guard let client, let userID else { return }
        do {
            let rows: [ProfileDTO] = try await client.from("profiles").select()
                .eq("id", value: userID.uuidString).execute().value
            if let mine = rows.first {
                profile = mine
                status = .signedIn
                await refresh()
            } else {
                status = .needsProfile
            }
        } catch {
            message = friendly(error)
        }
    }

    func createProfile(username: String, displayName: String) async {
        await run {
            guard let client = self.client, let userID = self.userID else { return }
            let mine = ProfileDTO(id: userID, username: username.lowercased(),
                                  displayName: displayName, statsVisibility: "friends")
            try await client.from("profiles").insert(mine).execute()
            self.profile = mine
            self.status = .signedIn
            await self.refresh()
        }
    }

    func setVisibility(_ visibility: String) async {
        await run {
            guard let client = self.client, let userID = self.userID else { return }
            try await client.from("profiles").update(["stats_visibility": visibility])
                .eq("id", value: userID.uuidString).execute()
            self.profile?.statsVisibility = visibility
        }
    }

    // MARK: Friends

    var myID: UUID? { userID }

    func refresh() async {
        guard status == .signedIn, let client, let me = userID else { return }
        do {
            let links: [FriendshipDTO] = try await client.from("friendships").select().execute().value
            let accepted = links.filter { $0.status == "accepted" }.map { $0.requester == me ? $0.addressee : $0.requester }
            let incomingIDs = links.filter { $0.status == "pending" && $0.addressee == me }.map(\.requester)
            let outgoingIDs = links.filter { $0.status == "pending" && $0.requester == me }.map(\.addressee)

            let everyone = Set(accepted + incomingIDs + outgoingIDs)
            var people: [UUID: ProfileDTO] = [:]
            if !everyone.isEmpty {
                let found: [ProfileDTO] = try await client.from("profiles").select()
                    .in("id", values: everyone.map(\.uuidString)).execute().value
                people = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
            }
            friends = accepted.compactMap { people[$0] }.sorted { $0.displayName < $1.displayName }
            incoming = incomingIDs.compactMap { people[$0] }
            outgoing = outgoingIDs.compactMap { people[$0] }

            let shared: [SharedRoundDTO] = try await client.from("shared_rounds").select()
                .in("user_id", values: (accepted + [me]).map(\.uuidString))
                .order("played_on", ascending: false)
                .limit(2000)
                .execute().value
            rounds = Dictionary(grouping: shared, by: \.userID)
        } catch {
            message = friendly(error)
        }
    }

    /// Sends a request, or accepts theirs if they already asked you.
    func addFriend(username: String) async -> Bool {
        var ok = false
        await run {
            guard let client = self.client, let me = self.userID else { return }
            let name = username.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
            let found: [ProfileDTO] = try await client.from("profiles").select().eq("username", value: name).execute().value
            guard let other = found.first, other.id != me else {
                self.message = "No player called @\(name)."
                return
            }
            if self.incoming.contains(where: { $0.id == other.id }) {
                try await self.acceptRequest(from: other, client: client, me: me)
            } else {
                try await client.from("friendships")
                    .insert(FriendshipDTO(requester: me, addressee: other.id, status: "pending")).execute()
                self.message = "Request sent to @\(other.username)."
            }
            ok = true
            await self.refresh()
        }
        return ok
    }

    func accept(_ other: ProfileDTO) async {
        await run {
            guard let client = self.client, let me = self.userID else { return }
            try await self.acceptRequest(from: other, client: client, me: me)
            await self.refresh()
        }
    }

    private func acceptRequest(from other: ProfileDTO, client: SupabaseClient, me: UUID) async throws {
        try await client.from("friendships").update(["status": "accepted"])
            .eq("requester", value: other.id.uuidString)
            .eq("addressee", value: me.uuidString)
            .execute()
    }

    /// Declines a request, cancels one you sent, or removes a friend.
    func remove(_ other: ProfileDTO) async {
        await run {
            guard let client = self.client, let me = self.userID else { return }
            let a = me.uuidString, b = other.id.uuidString
            try await client.from("friendships").delete()
                .or("and(requester.eq.\(a),addressee.eq.\(b)),and(requester.eq.\(b),addressee.eq.\(a))")
                .execute()
            await self.refresh()
        }
    }

    // MARK: Rounds

    /// Shares finished rounds that haven't been shared yet. Demo rounds are never shared.
    func sync(context: ModelContext) async {
        guard status == .signedIn, let client, let me = userID else { return }
        let descriptor = FetchDescriptor<Round>(predicate: #Predicate { $0.isComplete && $0.uploadedAt == nil })
        let pending = ((try? context.fetch(descriptor)) ?? []).filter { $0.courseName != SampleData.courseName }
        guard !pending.isEmpty else { return }
        let payload: [SharedRoundDTO] = pending.map { round in
            let id = round.remoteID ?? UUID()
            round.remoteID = id
            return SharedRoundDTO(round: round, id: id, userID: me)
        }
        do {
            try await client.from("shared_rounds").upsert(payload).execute()
            for round in pending { round.uploadedAt = .now }
            await refresh()
        } catch {
            message = friendly(error)
        }
    }

    // MARK: Helpers

    private func run(_ work: @escaping @MainActor () async throws -> Void) async {
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            message = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        let text = error.localizedDescription
        if text.contains("duplicate key") && text.contains("username") { return "That username is taken." }
        if text.contains("duplicate key") { return "Already done." }
        if text.contains("Invalid login credentials") { return "Wrong email or password." }
        return text
    }

    #if DEBUG
    /// Fake friends and rounds for the CI screenshot. Never talks to the server.
    func loadDemo() {
        let me = ProfileDTO(id: UUID(), username: "sammy", displayName: "Sammy", statsVisibility: "friends")
        let people = [
            ProfileDTO(id: UUID(), username: "tom", displayName: "Tom", statsVisibility: "friends"),
            ProfileDTO(id: UUID(), username: "dave", displayName: "Dave", statsVisibility: "friends"),
            ProfileDTO(id: UUID(), username: "jack", displayName: "Jack", statsVisibility: "friends"),
        ]
        var rng = SeededGenerator(seed: 11)
        func rounds(for person: ProfileDTO, start: Double, end: Double) -> [SharedRoundDTO] {
            let pars = [4, 4, 3, 5, 4, 4, 3, 4, 5, 4, 3, 4, 5, 4, 4, 3, 4, 5]
            return (0..<14).map { i in
                let skill = start + (end - start) * Double(i) / 13  // average strokes over par per hole
                let holes = pars.enumerated().map { n, par in
                    let r = Double.random(in: 0..<1, using: &rng)
                    let over = r < 0.1 ? -1 : (r < 0.1 + max(0, 0.9 - skill) ? 0 : (r < 0.93 ? 1 : 2))
                    return SharedHole(number: n + 1, par: par, strokeIndex: n + 1, strokes: par + over, putts: 2,
                                      firstPuttFeet: Int.random(in: 4...35, using: &rng), fairway: nil, green: nil,
                                      upAndDown: nil, penalties: 0)
                }
                return SharedRoundDTO(id: UUID(), userID: person.id,
                                      playedOn: Date.now.addingTimeInterval(-Double(13 - i) * 10 * 86_400),
                                      courseName: "Demo Golf Club", teeName: "White", courseRating: 71.8, slope: 128,
                                      handicapIndexAtStart: nil, mode: "quick", holes: holes)
            }
        }
        profile = me
        userID = me.id
        friends = people
        incoming = [ProfileDTO(id: UUID(), username: "ollie", displayName: "Ollie", statsVisibility: "friends")]
        rounds = [
            me.id: rounds(for: me, start: 0.55, end: 0.4),
            people[0].id: rounds(for: people[0], start: 0.3, end: 0.32),
            people[1].id: rounds(for: people[1], start: 0.6, end: 0.52),
            people[2].id: rounds(for: people[2], start: 0.85, end: 0.6),
        ]
        status = .signedIn
    }
    #endif
}
