import SwiftUI
import SwiftData

extension Color {
    static let tgBlue = Color.tgData
    static let tgOrange = Color.tgLoss
    static func team(_ t: Int?) -> Color { t == 0 ? .tgBlue : (t == 1 ? .tgOrange : .tgMuted) }
}

/// Small coloured label: LIVE, SETUP, FINAL.
struct StatusBadge: View {
    let status: String

    var body: some View {
        let text = status == "live" ? "LIVE" : (status == "setup" ? "SETUP" : "FINAL")
        Text(text)
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(status == "live" ? Color.tgBackground : Color.tgMuted)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(status == "live" ? Color.tgAccent : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(status == "live" ? Color.clear : Color.tgLine))
    }
}

// MARK: - Friends hub section

struct TournamentsSection: View {
    @ObservedObject private var backend = Backend.shared
    @Binding var open: UUID?
    @State private var creating = false
    @State private var joining = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 18) {
                SectionLabel("Tournaments")
                Spacer()
                Button("Join") { joining = true }.font(.subheadline.weight(.semibold))
                Button("New") { creating = true }.font(.subheadline.weight(.semibold))
            }
            .padding(.bottom, 6)

            if backend.tournaments.isEmpty {
                Text("Run a club championship, a pairs event or a Ryder Cup style match, with a live leaderboard for everyone.")
                    .font(.footnote)
                    .foregroundStyle(Color.tgMuted)
                    .padding(.vertical, 8)
            }
            ForEach(Array(backend.tournaments.prefix(6))) { t in
                Button { open = t.id } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(t.tournament.name).font(.body.weight(.semibold)).lineLimit(1)
                                StatusBadge(status: t.status)
                            }
                            Text(t.formatLine).font(.caption).foregroundStyle(Color.tgMuted).lineLimit(1)
                            Text(t.headline).font(.caption.weight(.semibold)).lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.tgMuted)
                    }
                    .frame(minHeight: 64)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Hairline()
            }
        }
        .sheet(isPresented: $creating) { NewTournamentView { open = $0 } }
        .sheet(isPresented: $joining) { JoinTournamentView { open = $0 } }
    }
}

// MARK: - Create

struct NewTournamentView: View {
    let onCreated: (UUID) -> Void

    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(filter: #Predicate<Round> { $0.isComplete }) private var myRounds: [Round]

    @State private var name = ""
    @State private var scoring: TourScoring = .stroke
    @State private var mode: TourMode = .individual
    @State private var pairFormat: PairFormat = .fourball
    @State private var teamStroke: TeamStroke = .best2
    @State private var sessions: Set<CupSession> = Set(CupSession.allCases)
    @State private var blueName = "Team Blue"
    @State private var orangeName = "Team Orange"
    @State private var basis: HandicapBasis = .net
    @State private var rounds = 1
    @State private var courseName = ""
    @State private var chosenFriends: Set<UUID> = []
    @State private var guests: [Backend.NewPlayer] = []
    @State private var guestName = ""
    @State private var guestHandicap = ""

    private var myIndex: Double? {
        Handicap.currentIndex(myRounds.map(\.data))
            ?? PlayerProgress.compute((backend.rounds[backend.myID ?? UUID()] ?? []).map(\.data)).handicap
    }

    private func friendIndex(_ id: UUID) -> Double? {
        PlayerProgress.compute((backend.rounds[id] ?? []).map(\.data)).handicap
    }

    private var players: [Backend.NewPlayer] {
        var list: [Backend.NewPlayer] = []
        if let me = backend.profile {
            list.append(Backend.NewPlayer(userID: me.id, name: me.displayName, handicapIndex: myIndex))
        }
        for friend in backend.friends where chosenFriends.contains(friend.id) {
            list.append(Backend.NewPlayer(userID: friend.id, name: friend.displayName, handicapIndex: friendIndex(friend.id)))
        }
        return list + guests
    }

    /// A preview of the event as set up so far, for the summary line.
    private var preview: TourSetup {
        let list = players
        return TourSetup(scoring: scoring, mode: mode, pairFormat: pairFormat, teamStroke: teamStroke, basis: basis,
                         holes: (1...18).map { MatchHoleInfo(number: $0, par: 4, strokeIndex: $0) },
                         courseRating: 72, slope: 113, rounds: scoring == .stroke ? rounds : 1,
                         sessions: CupSession.allCases.filter { sessions.contains($0) },
                         players: list.enumerated().map { i, p in
                             TourPlayer(key: "\(i)", name: p.name, handicapIndex: p.handicapIndex, team: mode == .teams ? i % 2 : nil)
                         },
                         teamNames: [blueName, orangeName])
    }

    private var problem: String? {
        if courses.isEmpty { return "Add your course first (Play → Add a course)." }
        if name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give it a name." }
        if mode == .teams && scoring == .match && sessions.isEmpty { return "Pick at least one session." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Club Championship", text: $name)
                }

                Section {
                    Picker("Scoring", selection: $scoring) {
                        ForEach(TourScoring.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Who plays", selection: $mode) {
                        ForEach(TourMode.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if mode == .pairs {
                        Picker("Pairs format", selection: $pairFormat) {
                            ForEach(PairFormat.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        Text(pairFormat.note).font(.footnote).foregroundStyle(Color.tgMuted)
                    }
                    if mode == .teams && scoring == .stroke {
                        Picker("Team score", selection: $teamStroke) {
                            ForEach(TeamStroke.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("Handicaps", selection: $basis) {
                        Text("Net").tag(HandicapBasis.net)
                        Text("Gross").tag(HandicapBasis.gross)
                    }
                    .pickerStyle(.segmented)
                    if scoring == .stroke {
                        Stepper("Rounds: \(rounds)", value: $rounds, in: 1...4)
                    }
                } header: {
                    Text("Format")
                }

                if mode == .teams {
                    Section("Teams") {
                        TextField("Team 1", text: $blueName).foregroundStyle(Color.tgBlue)
                        TextField("Team 2", text: $orangeName).foregroundStyle(Color.tgOrange)
                        if scoring == .match {
                            ForEach(CupSession.allCases) { session in
                                Toggle(session.label, isOn: Binding(
                                    get: { sessions.contains(session) },
                                    set: { on in if on { sessions.insert(session) } else { sessions.remove(session) } }))
                            }
                        }
                    }
                }

                Section("Course") {
                    Picker("Course", selection: $courseName) {
                        ForEach(courses) { Text($0.name).tag($0.name) }
                    }
                }

                Section {
                    if let me = backend.profile {
                        playerRow(name: "\(me.displayName) (you)", index: myIndex)
                    }
                    ForEach(backend.friends) { friend in
                        Toggle(isOn: Binding(
                            get: { chosenFriends.contains(friend.id) },
                            set: { on in if on { chosenFriends.insert(friend.id) } else { chosenFriends.remove(friend.id) } })) {
                            playerRow(name: friend.displayName, index: friendIndex(friend.id))
                        }
                    }
                    ForEach(guests) { guest in
                        playerRow(name: "\(guest.name) (guest)", index: guest.handicapIndex)
                    }
                    .onDelete { guests.remove(atOffsets: $0) }
                    TextField("Guest name", text: $guestName)
                    TextField("Guest handicap index, e.g. 12.4", text: $guestHandicap).keyboardType(.decimalPad)
                    Button("Add guest") { addGuest() }
                        .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Players")
                } footer: {
                    Text("Anyone else can join with the code you'll get next. You set the draw and teams before it starts.")
                }

                Section {
                    Text(TournamentEngine.summary(preview)).font(.subheadline.weight(.semibold))
                    Text("Handicaps: " + TournamentEngine.allowanceText(preview)).font(.footnote).foregroundStyle(Color.tgMuted)
                    Text("Live scoring: one person per group enters scores and everyone sees the leaderboard update.")
                        .font(.footnote)
                        .foregroundStyle(Color.tgMuted)
                } header: {
                    Text("Summary")
                }

                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Color.tgLoss)
                }
                if let message = backend.message {
                    Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
                }
            }
            .navigationTitle("New tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }.disabled(problem != nil || backend.isBusy)
                }
            }
            .onAppear {
                if courseName.isEmpty { courseName = courses.first?.name ?? "" }
            }
        }
    }

    private func playerRow(name: String, index: Double?) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(index.map { formatDecimal($0) } ?? "No handicap").foregroundStyle(Color.tgMuted).monospacedDigit()
        }
    }

    private func addGuest() {
        let clean = guestName.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { return }
        guests.append(Backend.NewPlayer(name: clean, handicapIndex: Double(guestHandicap.replacingOccurrences(of: ",", with: "."))))
        guestName = ""
        guestHandicap = ""
    }

    private func create() {
        guard let course = courses.first(where: { $0.name == courseName }) ?? courses.first else { return }
        let options = Backend.TournamentOptions(
            name: name.trimmingCharacters(in: .whitespaces), scoring: scoring, mode: mode, pairFormat: pairFormat,
            teamStroke: teamStroke, sessions: CupSession.allCases.filter { sessions.contains($0) },
            teamNames: [blueName.isEmpty ? "Team Blue" : blueName, orangeName.isEmpty ? "Team Orange" : orangeName],
            basis: basis, rounds: rounds)
        let list = players
        Task {
            if let id = await backend.createTournament(options, course: course, players: list) {
                dismiss()
                onCreated(id)
            }
        }
    }
}

// MARK: - Join

struct JoinTournamentView: View {
    let onJoined: (UUID) -> Void

    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Round> { $0.isComplete }) private var myRounds: [Round]
    @State private var code = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Code, e.g. K7PX2M", text: $code)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.title3.weight(.semibold).monospaced())
                } footer: {
                    Text("Ask the organiser for the 6 character code. You can join until the tournament starts.")
                }
                if let message = backend.message {
                    Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
                }
            }
            .navigationTitle("Join a tournament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join") {
                        let index = Handicap.currentIndex(myRounds.map(\.data))
                            ?? PlayerProgress.compute((backend.rounds[backend.myID ?? UUID()] ?? []).map(\.data)).handicap
                        Task {
                            if let id = await backend.joinTournament(code: code, index: index) {
                                dismiss()
                                onJoined(id)
                            }
                        }
                    }
                    .disabled(code.trimmingCharacters(in: .whitespaces).count < 6 || backend.isBusy)
                }
            }
        }
    }
}

// MARK: - One tournament

struct TournamentView: View {
    let tournamentID: UUID

    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @State private var scoring = false
    @State private var confirmFinish = false
    @State private var confirmDelete = false

    private var live: LiveTournament? { backend.tournaments.first { $0.id == tournamentID } }

    var body: some View {
        Group {
            if let live {
                content(live)
            } else {
                ProgressView()
            }
        }
        .background(Color.tgBackground)
        .navigationTitle(live?.tournament.name ?? "Tournament")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $scoring) {
            NavigationStack { TourScoringView(tournamentID: tournamentID) }
        }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-tourScoring") { scoring = true }
            #endif
            // Keep everyone's board fresh while it's open.
            while !Task.isCancelled {
                if let live, live.status != "finished" { await backend.refreshTournament(tournamentID) }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    private func content(_ live: LiveTournament) -> some View {
        let setup = live.setup
        let isOrganiser = live.tournament.createdBy == backend.myID
        let isPlayer = live.players.contains { $0.userID == backend.myID }

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header(live, setup: setup)

                if live.isSetup {
                    TournamentLobby(live: live, isOrganiser: isOrganiser)
                } else {
                    switch (setup.scoring, setup.mode) {
                    case (.stroke, _): StrokeBoard(live: live)
                    case (.match, .teams): CupBoard(live: live)
                    case (.match, _): BracketBoard(live: live)
                    }

                    if live.isLive && (isPlayer || isOrganiser) {
                        Button("Enter scores") { scoring = true }
                            .buttonStyle(PrimaryButtonStyle())
                    }

                    FeedSection(live: live)

                    if live.isLive && isOrganiser {
                        Button("Finish tournament") { confirmFinish = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                }

                if let message = backend.message {
                    Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
                }

                if isOrganiser {
                    Button("Delete tournament", role: .destructive) { confirmDelete = true }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .refreshable { await backend.refreshTournament(tournamentID) }
        .confirmationDialog("Finish the tournament?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish tournament") { Task { await backend.setTournamentStatus(tournamentID, "finished") } }
        } message: {
            Text("Scores can't be changed after this.")
        }
        .confirmationDialog("Delete this tournament for everyone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete tournament", role: .destructive) {
                Task {
                    await backend.deleteTournament(tournamentID)
                    dismiss()
                }
            }
        }
    }

    private func header(_ live: LiveTournament, setup: TourSetup) -> some View {
        let round = TournamentEngine.currentRound(setup, live.table)
        var top = "SETTING UP"
        if live.isLive {
            top = "LIVE" + (setup.scoring == .stroke && setup.rounds > 1 ? " · ROUND \(round) OF \(setup.rounds)" : "")
        } else if live.status == "finished" {
            top = "FINAL"
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if live.isLive { Circle().fill(Color.tgAccent).frame(width: 7, height: 7) }
                Text(top).font(.caption.weight(.bold)).tracking(1)
                    .foregroundStyle(live.isLive ? Color.tgAccent : Color.tgMuted)
            }
            Text(live.tournament.name).font(.title.weight(.semibold))
            Text("\(live.formatLine) · \(live.players.count) players · \(live.tournament.courseName)")
                .font(.footnote)
                .foregroundStyle(Color.tgMuted)
            Text("Handicaps: " + TournamentEngine.allowanceText(setup))
                .font(.footnote)
                .foregroundStyle(Color.tgMuted)
        }
    }
}

// MARK: - Lobby (before it starts)

struct TournamentLobby: View {
    let live: LiveTournament
    let isOrganiser: Bool

    @ObservedObject private var backend = Backend.shared
    @State private var guestName = ""
    @State private var guestHandicap = ""
    @State private var confirmLeave = false

    var body: some View {
        let setup = live.setup
        let players = live.sortedPlayers

        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel("Join code")
                HStack {
                    Text(live.tournament.joinCode)
                        .font(.system(size: 40, weight: .semibold, design: .monospaced))
                        .tracking(4)
                        .textSelection(.enabled)
                    Spacer()
                    ShareLink(item: "Join \"\(live.tournament.name)\" on That's Good: Friends → Tournaments → Join, code \(live.tournament.joinCode)") {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                Text("Players with the app join with this code. Guests don't need it.")
                    .font(.footnote)
                    .foregroundStyle(Color.tgMuted)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    SectionLabel(setup.mode == .teams ? "Teams" : (setup.mode == .pairs ? "Pairs" : "Players"))
                    Spacer()
                    if isOrganiser && players.count > 1 {
                        Menu("Draw") {
                            Button("Balance by handicap") { save(balanced(players, setup: setup)) }
                            Button("Shuffle") { save(shuffled(players, setup: setup)) }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.bottom, 6)
                if setup.mode == .teams {
                    ForEach([0, 1], id: \.self) { team in
                        let members = players.filter { $0.team == team }
                        Text("\(setup.teamNames[team]) · \(members.count)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.team(team))
                            .padding(.top, 10)
                            .padding(.bottom, 4)
                        ForEach(members, id: \.playerKey) { p in row(p, all: players, setup: setup) }
                    }
                    let unplaced = players.filter { $0.team == nil }
                    if !unplaced.isEmpty {
                        Text("No team yet").font(.subheadline.weight(.semibold)).foregroundStyle(Color.tgMuted).padding(.top, 10)
                        ForEach(unplaced, id: \.playerKey) { p in row(p, all: players, setup: setup) }
                    }
                } else {
                    ForEach(players, id: \.playerKey) { p in
                        let i = players.firstIndex(of: p) ?? 0
                        if setup.mode == .pairs && i % 2 == 0 {
                            Text("Pair \(i / 2 + 1)").font(.caption.weight(.semibold)).foregroundStyle(Color.tgMuted).padding(.top, 10)
                        }
                        row(p, all: players, setup: setup)
                    }
                }
                Text(isOrganiser ? "Use the arrows to set the order. " + orderHint(setup) : orderHint(setup))
                    .font(.caption)
                    .foregroundStyle(Color.tgMuted)
                    .padding(.top, 8)
            }

            if isOrganiser {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Add a guest")
                    TextField("Name", text: $guestName).textFieldStyle(.roundedBorder)
                    TextField("Handicap index, e.g. 12.4", text: $guestHandicap)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Button("Add guest") {
                        let name = guestName.trimmingCharacters(in: .whitespaces)
                        let index = Double(guestHandicap.replacingOccurrences(of: ",", with: "."))
                        guestName = ""
                        guestHandicap = ""
                        Task { await backend.addGuest(to: live.id, name: name, index: index) }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(TournamentEngine.summary(setup)).font(.subheadline.weight(.semibold))
                    if let problem = TournamentEngine.problem(setup) {
                        Text(problem).font(.footnote).foregroundStyle(Color.tgLoss)
                    }
                    Button("Start tournament") { Task { await backend.setTournamentStatus(live.id, "live") } }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(TournamentEngine.problem(setup) != nil || backend.isBusy)
                    Text("The draw is locked once it starts.").font(.caption).foregroundStyle(Color.tgMuted)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Waiting for the organiser to start.").font(.subheadline).foregroundStyle(Color.tgMuted)
                    Button("Leave tournament", role: .destructive) { confirmLeave = true }
                        .font(.footnote)
                }
                .confirmationDialog("Leave this tournament?", isPresented: $confirmLeave, titleVisibility: .visible) {
                    Button("Leave", role: .destructive) {
                        if let key = live.key(for: backend.myID ?? UUID()) {
                            Task {
                                await backend.removePlayer(live.id, key: key)
                                await backend.refreshTournaments()
                            }
                        }
                    }
                }
            }
        }
    }

    private func orderHint(_ s: TourSetup) -> String {
        switch (s.scoring, s.mode) {
        case (.match, .teams): return "Players at the top of each team play together and against each other first."
        case (.match, _): return "Order is the seeding: number 1 plays the lowest seed."
        case (.stroke, .pairs): return "Players 1 & 2 are a pair, 3 & 4 the next, and so on."
        case (.stroke, _): return "Groups of four, in this order."
        }
    }

    private func row(_ p: TournamentPlayerDTO, all: [TournamentPlayerDTO], setup: TourSetup) -> some View {
        let i = all.firstIndex(of: p) ?? 0
        return HStack(spacing: 10) {
            Text(p.userID == backend.myID && p.name != "You" ? "\(p.name) (you)" : p.name).font(.body.weight(.semibold)).lineLimit(1)
            if p.userID == nil { Text("guest").font(.caption).foregroundStyle(Color.tgMuted) }
            Spacer()
            Text(p.handicapIndex.map { formatDecimal($0) } ?? "–").foregroundStyle(Color.tgMuted).monospacedDigit()
            if isOrganiser {
                if setup.mode == .teams {
                    Button { save(switchTeam(all, p)) } label: { Image(systemName: "arrow.left.arrow.right").frame(width: 34, height: 40) }
                        .accessibilityLabel("Move \(p.name) to the other team")
                }
                Button { save(move(all, from: i, by: -1)) } label: { Image(systemName: "chevron.up").frame(width: 30, height: 40) }
                    .disabled(i == 0)
                    .accessibilityLabel("Move \(p.name) up")
                Button { save(move(all, from: i, by: 1)) } label: { Image(systemName: "chevron.down").frame(width: 30, height: 40) }
                    .disabled(i == all.count - 1)
                    .accessibilityLabel("Move \(p.name) down")
                Menu {
                    Button("Remove \(p.name)", role: .destructive) { Task { await backend.removePlayer(live.id, key: p.playerKey) } }
                } label: { Image(systemName: "ellipsis").frame(width: 30, height: 40) }
                .accessibilityLabel("More for \(p.name)")
            }
        }
        .buttonStyle(.plain)
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func save(_ players: [TournamentPlayerDTO]) {
        Task { await backend.saveDraw(live.id, players) }
    }

    private func move(_ all: [TournamentPlayerDTO], from i: Int, by delta: Int) -> [TournamentPlayerDTO] {
        var list = all
        let j = i + delta
        guard list.indices.contains(j) else { return list }
        list.swapAt(i, j)
        return list
    }

    private func switchTeam(_ all: [TournamentPlayerDTO], _ p: TournamentPlayerDTO) -> [TournamentPlayerDTO] {
        all.map { q in
            var q = q
            if q.playerKey == p.playerKey { q.team = p.team == 0 ? 1 : 0 }
            return q
        }
    }

    private func shuffled(_ all: [TournamentPlayerDTO], setup: TourSetup) -> [TournamentPlayerDTO] {
        var list = all.shuffled()
        if setup.mode == .teams { for i in list.indices { list[i].team = i % 2 } }
        return list
    }

    /// Teams: snake draft by handicap. Pairs: best with worst. Otherwise: lowest handicap first.
    private func balanced(_ all: [TournamentPlayerDTO], setup: TourSetup) -> [TournamentPlayerDTO] {
        var list = all.sorted { ($0.handicapIndex ?? 54) < ($1.handicapIndex ?? 54) }
        switch setup.mode {
        case .teams:
            for i in list.indices { list[i].team = [0, 1, 1, 0][i % 4] }
        case .pairs:
            var paired: [TournamentPlayerDTO] = []
            var low = 0, high = list.count - 1
            while low <= high {
                paired.append(list[low])
                if low != high { paired.append(list[high]) }
                low += 1
                high -= 1
            }
            list = paired
        case .individual:
            break
        }
        return list
    }
}

// MARK: - Stroke play board

struct StrokeBoard: View {
    let live: LiveTournament
    @ObservedObject private var backend = Backend.shared
    @State private var basis: HandicapBasis?

    var body: some View {
        let setup = live.setup
        let shown = basis ?? setup.basis
        let board = TournamentEngine.leaderboard(setup, live.table, basis: shown)
        let myKey = live.key(for: backend.myID ?? UUID())

        VStack(alignment: .leading, spacing: 18) {
            SegmentedPicker(options: [HandicapBasis.gross, .net], selection: Binding(get: { shown }, set: { basis = $0 })) {
                $0 == .net ? "Net" : "Gross"
            }

            BoardTable(rows: board.rows, myKey: myKey, showHandicap: setup.mode == .individual,
                       isMine: { row in setup.mode == .teams ? false : row.key.contains(myKey ?? "-") })

            if setup.mode == .teams {
                let individual = Self.individual(setup)
                VStack(alignment: .leading, spacing: 6) {
                    SectionLabel("Players")
                    BoardTable(rows: TournamentEngine.leaderboard(individual, live.table, basis: shown).rows, myKey: myKey,
                               showHandicap: true, isMine: { $0.key == myKey }, teams: setup)
                }
            }
        }
    }
}

extension StrokeBoard {
    /// The same event scored player by player.
    static func individual(_ setup: TourSetup) -> TourSetup {
        var s = setup
        s.mode = .individual
        return s
    }
}

struct BoardTable: View {
    let rows: [TourRow]
    let myKey: String?
    let showHandicap: Bool
    let isMine: (TourRow) -> Bool
    var teams: TourSetup?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("POS").frame(width: 34, alignment: .leading)
                Text("PLAYER").frame(maxWidth: .infinity, alignment: .leading)
                Text("TODAY").frame(width: 50, alignment: .trailing)
                Text("THRU").frame(width: 38, alignment: .trailing)
                Text("TOTAL").frame(width: 50, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(Color.tgMuted)
            .padding(.bottom, 6)
            Hairline()
            ForEach(rows) { row in
                let mine = isMine(row)
                HStack(spacing: 6) {
                    Text(row.positionLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(row.position == 1 ? Color.tgAccent : Color.tgMuted)
                        .frame(width: 34, alignment: .leading)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 5) {
                            if let team = row.team ?? teamOf(row) {
                                Circle().fill(Color.team(team)).frame(width: 7, height: 7)
                            }
                            Text(row.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            if let m = row.movement, m != 0 {
                                Text(m > 0 ? "↑\(m)" : "↓\(-m)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(m > 0 ? Color.tgAccent : Color.tgLoss)
                            }
                        }
                        if showHandicap, let h = row.handicapIndex {
                            Text("HCP \(formatDecimal(h))").font(.caption2).foregroundStyle(Color.tgMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text(row.today.map(formatToPar) ?? "–").frame(width: 50, alignment: .trailing)
                    Text(row.roundDone ? "F" : (row.thru > 0 ? "\(row.thru)" : "–"))
                        .foregroundStyle(Color.tgMuted)
                        .frame(width: 38, alignment: .trailing)
                    Text(row.total.map(formatToPar) ?? "–")
                        .font(.body.weight(.bold))
                        .foregroundStyle((row.total ?? 0) < 0 ? Color.tgAccent : Color.primary)
                        .frame(width: 50, alignment: .trailing)
                }
                .font(.subheadline)
                .monospacedDigit()
                .frame(minHeight: 50)
                .padding(.horizontal, mine ? 20 : 0)
                .background(mine ? Color.tgSurface : Color.clear)
                .padding(.horizontal, mine ? -20 : 0)
                .accessibilityElement(children: .combine)
                Hairline()
            }
        }
    }

    private func teamOf(_ row: TourRow) -> Int? {
        teams?.players.first { $0.key == row.key }?.team
    }
}

// MARK: - Two-team match play board

struct CupBoard: View {
    let live: LiveTournament
    @State private var session: CupSession?

    var body: some View {
        let setup = live.setup
        let cup = TournamentEngine.cup(setup, live.table)
        let available = CupSession.allCases.filter { s in cup.matches.contains { $0.game.session == s } }
        let started = available.last(where: { s in cup.matches.contains { $0.game.session == s && $0.state.played > 0 } })
        let current = session ?? started ?? available.first ?? .singles

        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                teamScore(setup.teamNames[0], cup.points[0], team: 0, alignment: .leading)
                Spacer()
                VStack(spacing: 4) {
                    Text("\(TournamentEngine.formatPoints(cup.toWin)) to win").font(.caption.weight(.semibold))
                    Text("of \(TournamentEngine.formatPoints(cup.total))").font(.caption).foregroundStyle(Color.tgMuted)
                    if let w = cup.winner {
                        Text("\(setup.teamNames[w]) win").font(.caption.weight(.bold)).foregroundStyle(Color.team(w))
                    } else if cup.onCourse > 0 {
                        Text("\(cup.onCourse) on the course").font(.caption).foregroundStyle(Color.tgMuted)
                    }
                }
                .padding(.top, 22)
                Spacer()
                teamScore(setup.teamNames[1], cup.points[1], team: 1, alignment: .trailing)
            }

            HStack {
                Text("Projected").font(.caption).foregroundStyle(Color.tgMuted)
                Spacer()
                Text(TournamentEngine.formatPoints(cup.projected[0])).foregroundStyle(Color.tgBlue)
                Text("–").foregroundStyle(Color.tgMuted)
                Text(TournamentEngine.formatPoints(cup.projected[1])).foregroundStyle(Color.tgOrange)
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .padding(.vertical, 10)
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }

            VStack(spacing: 0) {
                HStack(spacing: 22) {
                    ForEach(available) { s in
                        let p = cup.sessionPoints(s)
                        Button { session = s } label: {
                            VStack(spacing: 2) {
                                Text(s.label).font(.subheadline.weight(.semibold))
                                Text("\(TournamentEngine.formatPoints(p[0]))–\(TournamentEngine.formatPoints(p[1]))")
                                    .font(.caption).monospacedDigit()
                            }
                            .foregroundStyle(s == current ? Color.primary : Color.tgMuted)
                            .padding(.vertical, 8)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(s == current ? Color.tgAccent : Color.clear).frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(s == current ? .isSelected : [])
                    }
                    Spacer()
                }
                Hairline()
                ForEach(cup.matches.filter { $0.game.session == current }) { m in
                    CupMatchRow(match: m)
                    Hairline()
                }
            }
        }
    }

    private func teamScore(_ name: String, _ points: Double, team: Int, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(name.uppercased()).font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Color.team(team))
            Text(TournamentEngine.formatPoints(points))
                .font(.system(size: 52, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Color.team(team))
        }
    }
}

struct CupMatchRow: View {
    let match: CupMatch

    var body: some View {
        let st = match.state
        let leader = st.leader
        let color = Color.team(leader)
        let sub: String = st.finished ? (st.winner == nil ? "HALVED" : "FINAL")
            : (st.played > 0 ? "LIVE · THRU \(st.played)" : "NOT STARTED")

        HStack(spacing: 8) {
            Text(match.game.a?.name ?? "")
                .font(.subheadline.weight(st.winner == 0 ? .bold : .medium))
                .foregroundStyle(st.winner == 1 ? Color.tgMuted : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 3) {
                Text(st.played == 0 ? "–" : st.status)
                    .font(.footnote.weight(.bold))
                    .monospacedDigit()
                    .frame(minWidth: 64)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 6)
                    .foregroundStyle(st.finished && leader != nil ? Color.tgBackground : (leader == nil ? Color.primary : color))
                    .background(st.finished && leader != nil ? color : Color.clear, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(leader == nil ? Color.tgLine : color, lineWidth: 1.5))
                Text(sub).font(.caption2.weight(.semibold)).tracking(0.5).foregroundStyle(Color.tgMuted)
            }
            Text(match.game.b?.name ?? "")
                .font(.subheadline.weight(st.winner == 1 ? .bold : .medium))
                .foregroundStyle(st.winner == 0 ? Color.tgMuted : Color.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(minHeight: 60)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(match.game.a?.name ?? "") against \(match.game.b?.name ?? ""): \(st.status), \(sub.lowercased())")
    }
}

// MARK: - Knockout board

struct BracketBoard: View {
    let live: LiveTournament

    var body: some View {
        let bracket = TournamentEngine.bracket(live.setup, live.table)

        VStack(alignment: .leading, spacing: 22) {
            if let champ = bracket.champion {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel("Winner")
                    Text(champ.name).font(.title2.weight(.semibold)).foregroundStyle(Color.tgAccent)
                }
            }
            ForEach(Array(bracket.rounds.indices.reversed()), id: \.self) { i in
                let games = bracket.rounds[i]
                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel(bracket.title(i + 1)).padding(.bottom, 6)
                    ForEach(games) { g in
                        KnockoutRow(game: g)
                        Hairline()
                    }
                }
            }
        }
    }
}

struct KnockoutRow: View {
    let game: KnockoutGame

    var body: some View {
        let st = game.state
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                side(game.game.a, won: game.winner?.key == game.game.a?.key && game.winner != nil)
                side(game.game.b, won: game.winner?.key == game.game.b?.key && game.winner != nil)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(game.isBye ? "Bye" : (game.game.isReady ? (st?.played == 0 ? "–" : st?.status ?? "–") : "Waiting"))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let st, !game.isBye, game.game.isReady {
                    Text(st.finished ? "FINAL" : (st.played > 0 ? "THRU \(st.played + st.extraHoles)" : "NOT STARTED"))
                        .font(.caption2.weight(.semibold))
                        .tracking(0.5)
                        .foregroundStyle(st.finished ? Color.tgMuted : Color.tgAccent)
                }
            }
        }
        .frame(minHeight: 60)
        .accessibilityElement(children: .combine)
    }

    private func side(_ s: TourSide?, won: Bool) -> some View {
        Text(s?.name ?? (game.isBye ? "Bye" : "To be decided"))
            .font(.subheadline.weight(won ? .bold : .regular))
            .foregroundStyle(s == nil ? Color.tgMuted : (won ? Color.tgAccent : Color.primary))
            .lineLimit(1)
    }
}

// MARK: - Live feed

struct FeedSection: View {
    let live: LiveTournament

    var body: some View {
        let items = TournamentEngine.feed(live.setup, live.table, events: live.events)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionLabel("Live feed").padding(.bottom, 6)
                ForEach(items) { item in
                    HStack(alignment: .firstTextBaseline) {
                        (Text(item.name).fontWeight(.semibold) + Text(" \(item.text)").foregroundColor(Color.tgMuted))
                            .font(.subheadline)
                        Spacer()
                        Text(item.time, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                            .font(.caption)
                            .foregroundStyle(Color.tgMuted)
                    }
                    .frame(minHeight: 44)
                    Hairline()
                }
            }
        }
    }
}

// MARK: - Score entry

/// The group's scorer enters every ball, hole by hole.
struct TourScoringView: View {
    let tournamentID: UUID

    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @State private var groupID = ""
    @State private var hole = 1
    @State private var draft: [String: Int] = [:]

    private var live: LiveTournament? { backend.tournaments.first { $0.id == tournamentID } }

    var body: some View {
        Group {
            if let live {
                let setup = live.setup
                let table = live.table
                let groups = TournamentEngine.scoringGroups(setup, table)
                if let group = groups.first(where: { $0.id == groupID }) ?? groups.first {
                    card(live, setup: setup, table: table, groups: groups, group: group)
                } else {
                    Text("Nothing to score yet.").foregroundStyle(Color.tgMuted)
                }
            } else {
                ProgressView()
            }
        }
        .background(Color.tgBackground)
        .navigationTitle("Enter scores")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .onAppear(perform: pickStartingGroup)
    }

    private func pickStartingGroup() {
        guard let live, groupID.isEmpty else { return }
        let setup = live.setup, table = live.table
        let groups = TournamentEngine.scoringGroups(setup, table)
        let myKey = live.key(for: backend.myID ?? UUID())
        func unfinished(_ g: ScoringGroup) -> Bool {
            g.holes.contains { h in g.units.contains { table[g.game]?[$0.key]?[h.number] == nil } }
        }
        let mine = groups.filter { g in myKey.map { g.playerKeys.contains($0) } ?? false }
        let pick = mine.first(where: unfinished) ?? groups.first(where: unfinished) ?? mine.first ?? groups.first
        guard let pick else { return }
        groupID = pick.id
        jumpToNextHole(pick, table: table)
    }

    private func jumpToNextHole(_ g: ScoringGroup, table: TourScores) {
        hole = g.holes.first { h in g.units.contains { table[g.game]?[$0.key]?[h.number] == nil } }?.number
            ?? g.holes.last?.number ?? 1
        loadDraft(g, table: table)
    }

    private func loadDraft(_ g: ScoringGroup, table: TourScores) {
        var values: [String: Int] = [:]
        for u in g.units { if let s = table[g.game]?[u.key]?[hole] { values[u.key] = s } }
        draft = values
    }

    private func card(_ live: LiveTournament, setup: TourSetup, table: TourScores,
                      groups: [ScoringGroup], group: ScoringGroup) -> some View {
        let info = group.holes.first { $0.number == hole } ?? group.holes[0]
        let numbers = group.holes.map(\.number)
        let index = numbers.firstIndex(of: hole) ?? 0
        let extra = hole > setup.holes.count

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Menu {
                    ForEach(groups) { g in
                        Button(g.title) {
                            groupID = g.id
                            jumpToNextHole(g, table: table)
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SCORING").font(.caption2.weight(.bold)).tracking(1).foregroundStyle(Color.tgMuted)
                            Text(group.title).font(.subheadline.weight(.semibold)).multilineTextAlignment(.leading)
                        }
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.footnote)
                    }
                    .padding(12)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
                }
                .buttonStyle(.plain)

                HStack {
                    Button { hole = numbers[max(0, index - 1)]; loadDraft(group, table: table) } label: {
                        Image(systemName: "chevron.left").frame(width: 44, height: 44)
                    }
                    .disabled(index == 0)
                    .accessibilityLabel("Previous hole")
                    Spacer()
                    VStack(spacing: 2) {
                        Text("Hole \(hole)").font(.title3.weight(.semibold))
                        Text(extra ? "Extra hole · plays as \(hole - setup.holes.count) · PAR \(info.par)" : "PAR \(info.par) · SI \(info.strokeIndex)")
                            .font(.caption)
                            .foregroundStyle(Color.tgMuted)
                    }
                    Spacer()
                    Button { hole = numbers[min(numbers.count - 1, index + 1)]; loadDraft(group, table: table) } label: {
                        Image(systemName: "chevron.right").frame(width: 44, height: 44)
                    }
                    .disabled(index == numbers.count - 1)
                    .accessibilityLabel("Next hole")
                }
                .buttonStyle(.plain)

                ForEach(group.units) { unit in
                    unitRow(unit, info: info, holeCount: setup.holes.count)
                    Hairline()
                }

                Button(index == numbers.count - 1 ? "Save hole \(hole)" : "Save hole \(hole) and next") {
                    save(group, info: info, numbers: numbers, index: index)
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(backend.isBusy)

                if let message = backend.message {
                    Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
                }
                Text("Pick-ups: enter the score that counts, e.g. net double bogey.")
                    .font(.caption)
                    .foregroundStyle(Color.tgMuted)
            }
            .padding(20)
        }
    }

    private func unitRow(_ unit: TourUnit, info: MatchHoleInfo, holeCount: Int) -> some View {
        let strokes = Handicap.strokesReceived(courseHandicap: unit.handicap, strokeIndex: info.strokeIndex, holeCount: max(holeCount, 1))
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(unit.name).font(.body.weight(.semibold)).lineLimit(1)
                Text(strokes > 0 ? String(repeating: "•", count: strokes) + " gets \(strokes)" : (strokes < 0 ? "gives \(-strokes)" : " "))
                    .font(.caption)
                    .foregroundStyle(Color.tgAccent)
            }
            Spacer()
            Button { change(unit.key, -1, par: info.par) } label: {
                Image(systemName: "minus").frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
            }
            .accessibilityLabel("Fewer strokes for \(unit.name)")
            Text("\(draft[unit.key] ?? info.par)")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .frame(width: 44)
            Button { change(unit.key, 1, par: info.par) } label: {
                Image(systemName: "plus").frame(width: 44, height: 44)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
            }
            .accessibilityLabel("More strokes for \(unit.name)")
        }
        .buttonStyle(.plain)
        .frame(minHeight: 56)
    }

    private func change(_ key: String, _ delta: Int, par: Int) {
        draft[key] = min(15, max(1, (draft[key] ?? par) + delta))
    }

    private func save(_ group: ScoringGroup, info: MatchHoleInfo, numbers: [Int], index: Int) {
        var strokes: [String: Int] = [:]
        for u in group.units { strokes[u.key] = draft[u.key] ?? info.par }
        let current = hole
        Task {
            await backend.saveTournamentHole(tournamentID, game: group.game, hole: current, strokes: strokes)
            guard backend.message == nil, let live else { return }
            // A halved knockout match grows an extra hole, so look the group up again.
            let table = live.table
            let fresh = TournamentEngine.scoringGroups(live.setup, table).first { $0.id == group.id } ?? group
            let next = fresh.holes.map(\.number).first { $0 > current }
            if let next {
                hole = next
                loadDraft(fresh, table: table)
            }
        }
    }
}
