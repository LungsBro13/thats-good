import Foundation
import Supabase
import SwiftData

// MARK: - What's stored on the server

struct ProfileDTO: Codable, Identifiable, Hashable, Sendable {
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

struct FriendshipDTO: Codable, Hashable, Sendable {
    let requester: UUID
    let addressee: UUID
    var status: String
}

struct SharedHole: Codable, Sendable {
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

struct SharedRoundDTO: Codable, Identifiable, Sendable {
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

// MARK: - Server calls

/// Plain network calls. They run off the main thread and only hand back simple values.
struct SupabaseAPI: Sendable {
    let client: SupabaseClient

    func currentUserID() async -> UUID? {
        (try? await client.auth.session)?.user.id
    }

    func signUp(email: String, password: String) async throws -> UUID? {
        try await client.auth.signUp(email: email, password: password).session?.user.id
    }

    func signIn(email: String, password: String) async throws -> UUID {
        try await client.auth.signIn(email: email, password: password).user.id
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func profile(id: UUID) async throws -> ProfileDTO? {
        let rows: [ProfileDTO] = try await client.from("profiles").select()
            .eq("id", value: id.uuidString).execute().value
        return rows.first
    }

    func profile(username: String) async throws -> ProfileDTO? {
        let rows: [ProfileDTO] = try await client.from("profiles").select()
            .eq("username", value: username).execute().value
        return rows.first
    }

    func profiles(ids: [UUID]) async throws -> [ProfileDTO] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("profiles").select()
            .in("id", values: ids.map(\.uuidString)).execute().value
    }

    func insertProfile(_ profile: ProfileDTO) async throws {
        try await client.from("profiles").insert(profile).execute()
    }

    func setVisibility(_ visibility: String, for id: UUID) async throws {
        try await client.from("profiles").update(["stats_visibility": visibility])
            .eq("id", value: id.uuidString).execute()
    }

    func friendships() async throws -> [FriendshipDTO] {
        try await client.from("friendships").select().execute().value
    }

    func requestFriend(from me: UUID, to other: UUID) async throws {
        try await client.from("friendships")
            .insert(FriendshipDTO(requester: me, addressee: other, status: "pending")).execute()
    }

    func acceptFriend(requester: UUID, addressee: UUID) async throws {
        try await client.from("friendships").update(["status": "accepted"])
            .eq("requester", value: requester.uuidString)
            .eq("addressee", value: addressee.uuidString)
            .execute()
    }

    func removeFriendship(_ a: UUID, _ b: UUID) async throws {
        let x = a.uuidString, y = b.uuidString
        try await client.from("friendships").delete()
            .or("and(requester.eq.\(x),addressee.eq.\(y)),and(requester.eq.\(y),addressee.eq.\(x))")
            .execute()
    }

    func rounds(for userIDs: [UUID]) async throws -> [SharedRoundDTO] {
        try await client.from("shared_rounds").select()
            .in("user_id", values: userIDs.map(\.uuidString))
            .order("played_on", ascending: false)
            .limit(2000)
            .execute().value
    }

    func upsertRounds(_ rounds: [SharedRoundDTO]) async throws {
        try await client.from("shared_rounds").upsert(rounds).execute()
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
    @Published var matches: [LiveMatch] = []
    @Published var tournaments: [LiveTournament] = []
    @Published private(set) var isBusy = false
    @Published var message: String?

    var api: SupabaseAPI?
    var userID: UUID?

    private static let urlKey = "supabaseURL"
    private static let keyKey = "supabaseKey"

    init() {
        connectFromSavedSettings()
    }

    var myID: UUID? { userID }

    // MARK: Setup

    /// Saves the project URL and publishable key the player pasted in. Returns false if they don't look right.
    func connect(url: String, key: String) -> Bool {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = ServerURL.normalize(url), cleanKey.count > 20, !cleanKey.hasPrefix("sb_secret_") else {
            return false
        }
        let cleanURL = parsed.absoluteString
        UserDefaults.standard.set(cleanURL, forKey: Self.urlKey)
        UserDefaults.standard.set(cleanKey, forKey: Self.keyKey)
        connectFromSavedSettings()
        return true
    }

    func disconnect() {
        UserDefaults.standard.removeObject(forKey: Self.urlKey)
        UserDefaults.standard.removeObject(forKey: Self.keyKey)
        api = nil
        clearAccount()
        status = .notConfigured
    }

    private func connectFromSavedSettings() {
        guard let saved = UserDefaults.standard.string(forKey: Self.urlKey), let url = URL(string: saved),
              let key = UserDefaults.standard.string(forKey: Self.keyKey) else {
            status = .notConfigured
            return
        }
        // Opt in to the library's newer session behaviour (silences its warning). `currentUserID` reads
        // `auth.session`, which refreshes an expired session, so nothing else changes.
        let options = SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        api = SupabaseAPI(client: SupabaseClient(supabaseURL: url, supabaseKey: key, options: options))
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
        matches = []
        tournaments = []
    }

    // MARK: Account

    func restoreSession() async {
        guard let api else { return }
        guard let id = await api.currentUserID() else {
            status = .signedOut
            return
        }
        userID = id
        await loadProfile()
    }

    func signUp(email: String, password: String) async {
        await run { api in
            if let id = try await api.signUp(email: email, password: password) {
                self.userID = id
                await self.loadProfile()
            } else {
                self.message = "Check your email and tap the confirm link, then sign in."
            }
        }
    }

    func signIn(email: String, password: String) async {
        await run { api in
            self.userID = try await api.signIn(email: email, password: password)
            await self.loadProfile()
        }
    }

    func signOut() async {
        await api?.signOut()
        clearAccount()
        status = api == nil ? .notConfigured : .signedOut
    }

    private func loadProfile() async {
        guard let api, let userID else { return }
        do {
            if let mine = try await api.profile(id: userID) {
                profile = mine
                status = .signedIn
                await refresh()
            } else {
                status = .needsProfile
            }
        } catch {
            message = Backend.isCancel(error) ? nil : friendly(error)
        }
    }

    func createProfile(username: String, displayName: String) async {
        await run { api in
            guard let userID = self.userID else { return }
            let mine = ProfileDTO(id: userID, username: username.lowercased(),
                                  displayName: displayName, statsVisibility: "friends")
            try await api.insertProfile(mine)
            self.profile = mine
            self.status = .signedIn
            await self.refresh()
        }
    }

    func setVisibility(_ visibility: String) async {
        await run { api in
            guard let userID = self.userID else { return }
            try await api.setVisibility(visibility, for: userID)
            self.profile?.statsVisibility = visibility
        }
    }

    // MARK: Friends

    func refresh() async {
        guard status == .signedIn, let api, let me = userID else { return }
        do {
            let links = try await api.friendships()
            let accepted = links.filter { $0.status == "accepted" }.map { $0.requester == me ? $0.addressee : $0.requester }
            let incomingIDs = links.filter { $0.status == "pending" && $0.addressee == me }.map(\.requester)
            let outgoingIDs = links.filter { $0.status == "pending" && $0.requester == me }.map(\.addressee)

            let found = try await api.profiles(ids: Array(Set(accepted + incomingIDs + outgoingIDs)))
            let people = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
            friends = accepted.compactMap { people[$0] }.sorted { $0.displayName < $1.displayName }
            incoming = incomingIDs.compactMap { people[$0] }
            outgoing = outgoingIDs.compactMap { people[$0] }

            let shared = try await api.rounds(for: accepted + [me])
            rounds = Dictionary(grouping: shared, by: \.userID)
            await refreshMatches()
            await refreshTournaments()
        } catch {
            message = Backend.isCancel(error) ? nil : friendly(error)
        }
    }

    /// Sends a request, or accepts theirs if they already asked you.
    func addFriend(username: String) async -> Bool {
        var ok = false
        await run { api in
            guard let me = self.userID else { return }
            let name = username.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: "@", with: "")
            guard let other = try await api.profile(username: name), other.id != me else {
                self.message = "No player called @\(name)."
                return
            }
            if self.incoming.contains(where: { $0.id == other.id }) {
                try await api.acceptFriend(requester: other.id, addressee: me)
            } else {
                try await api.requestFriend(from: me, to: other.id)
                self.message = "Request sent to @\(other.username)."
            }
            ok = true
            await self.refresh()
        }
        return ok
    }

    func accept(_ other: ProfileDTO) async {
        await run { api in
            guard let me = self.userID else { return }
            try await api.acceptFriend(requester: other.id, addressee: me)
            await self.refresh()
        }
    }

    /// Declines a request, cancels one you sent, or removes a friend.
    func remove(_ other: ProfileDTO) async {
        await run { api in
            guard let me = self.userID else { return }
            try await api.removeFriendship(me, other.id)
            await self.refresh()
        }
    }

    // MARK: Rounds

    /// Shares finished rounds that haven't been shared yet. Demo rounds are never shared.
    func sync(context: ModelContext) async {
        guard status == .signedIn, let api, let me = userID else { return }
        let descriptor = FetchDescriptor<Round>(predicate: #Predicate { $0.isComplete && $0.uploadedAt == nil })
        let pending = ((try? context.fetch(descriptor)) ?? []).filter { $0.courseName != SampleData.courseName }
        guard !pending.isEmpty else { return }
        let payload: [SharedRoundDTO] = pending.map { round in
            let id = round.remoteID ?? UUID()
            round.remoteID = id
            return SharedRoundDTO(round: round, id: id, userID: me)
        }
        do {
            try await api.upsertRounds(payload)
            for round in pending { round.uploadedAt = .now }
            await refresh()
        } catch {
            message = Backend.isCancel(error) ? nil : friendly(error)
        }
    }

    // MARK: Helpers

    func run(_ work: @escaping @MainActor (SupabaseAPI) async throws -> Void) async {
        guard let api else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await work(api)
        } catch {
            message = Backend.isCancel(error) ? nil : friendly(error)
        }
    }

    /// A cancelled load (the screen closed or refreshed again) isn't a real problem, so it shows no message.
    static func isCancel(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let e = error as? URLError, e.code == .cancelled { return true }
        return (error as NSError).code == NSURLErrorCancelled && (error as NSError).domain == NSURLErrorDomain
    }

    func friendly(_ error: Error) -> String {
        if error is DecodingError {
            return "The server sent back something unexpected. Check the Project URL looks like https://xxxx.supabase.co (Supabase → Project Settings → Data API), and that the SQL setup ran. Then tap Disconnect and connect again."
        }
        let text = error.localizedDescription
        if text.contains("relation") && text.contains("does not exist") {
            return "The server tables are missing. Run the SQL setup file in Supabase's SQL Editor."
        }
        if text.lowercased().contains("invalid api key") || text.contains("No API key") {
            return "The key isn't right. Copy the publishable key again (Project Settings → API Keys)."
        }
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
        func makeRounds(for person: ProfileDTO, start: Double, end: Double) -> [SharedRoundDTO] {
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
            me.id: makeRounds(for: me, start: 0.55, end: 0.4),
            people[0].id: makeRounds(for: people[0], start: 0.3, end: 0.32),
            people[1].id: makeRounds(for: people[1], start: 0.6, end: 0.52),
            people[2].id: makeRounds(for: people[2], start: 0.85, end: 0.6),
        ]
        status = .signedIn
        loadDemoMatches()
        loadDemoTournaments()
    }
    #endif
}
