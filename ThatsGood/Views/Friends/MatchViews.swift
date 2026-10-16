import SwiftUI
import SwiftData

/// Live and recent matches, shown at the top of the Friends hub.
struct MatchesSection: View {
    @ObservedObject private var backend = Backend.shared
    @Binding var openMatch: UUID?
    @State private var creating = false

    var body: some View {
        let live = backend.matches.filter(\.isLive)
        let recent = Array(backend.matches.filter { !$0.isLive }.prefix(4))

        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Matches")
                Spacer()
                Button("New match") { creating = true }
                    .font(.subheadline.weight(.semibold))
            }
            .padding(.bottom, 6)

            if live.isEmpty && recent.isEmpty {
                Text("Set up a Nassau, skins, match play, Stableford or stroke play match with your mates.")
                    .font(.footnote)
                    .foregroundStyle(Color.tgMuted)
                    .padding(.vertical, 8)
            }
            ForEach(live) { match in
                matchRow(match, live: true)
                Hairline()
            }
            ForEach(recent) { match in
                matchRow(match, live: false)
                Hairline()
            }
        }
        .sheet(isPresented: $creating) {
            NewMatchView { id in openMatch = id }
        }
    }

    private func matchRow(_ match: LiveMatch, live: Bool) -> some View {
        Button { openMatch = match.id } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(match.format.label).font(.body.weight(.semibold))
                        if live {
                            Text("LIVE")
                                .font(.caption2.weight(.bold))
                                .tracking(0.8)
                                .foregroundStyle(Color.tgBackground)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.tgAccent, in: RoundedRectangle(cornerRadius: 3))
                        }
                    }
                    Text(match.playerNames).font(.caption).foregroundStyle(Color.tgMuted).lineLimit(1)
                    Text(match.outcome.status).font(.caption.weight(.semibold)).lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.tgMuted)
            }
            .frame(minHeight: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct NewMatchView: View {
    let onCreated: (UUID) -> Void

    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(filter: #Predicate<Round> { $0.isComplete }) private var myRounds: [Round]

    @State private var format: MatchFormat = .nassau
    @State private var basis: HandicapBasis = .net
    @State private var allowance: AllowanceRule = .full
    @State private var courseName: String = ""
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

    private var problem: String? {
        if courses.isEmpty { return "Add your course first (Play → Add a course)." }
        if format.isHeadToHead && players.count != 2 { return "\(format.label) is one against one: pick exactly one other player." }
        if players.count < 2 { return "Pick at least one other player." }
        if players.count > 8 { return "Up to 8 players." }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Format") {
                    Picker("Format", selection: $format) {
                        ForEach(MatchFormat.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Scoring", selection: $basis) {
                        Text("Net (with handicaps)").tag(HandicapBasis.net)
                        Text("Gross").tag(HandicapBasis.gross)
                    }
                    if basis == .net {
                        Picker("Handicaps", selection: $allowance) {
                            Text("Full").tag(AllowanceRule.full)
                            Text("Official allowance").tag(AllowanceRule.whs)
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
                } header: {
                    Text("Players")
                } footer: {
                    Text("Handicaps come from each player's shared rounds. Guests don't need the app.")
                }

                Section("Add a guest") {
                    TextField("Name", text: $guestName)
                    TextField("Handicap index, e.g. 12.4", text: $guestHandicap)
                        .keyboardType(.decimalPad)
                    Button("Add guest") {
                        let name = guestName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        let index = Double(guestHandicap.replacingOccurrences(of: ",", with: "."))
                        guests.append(Backend.NewPlayer(name: name, handicapIndex: index))
                        guestName = ""
                        guestHandicap = ""
                    }
                    .disabled(guestName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(Color.tgLoss)
                }
                if let message = backend.message {
                    Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
                }
            }
            .navigationTitle("New match")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { start() }.disabled(problem != nil || backend.isBusy)
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

    private func start() {
        guard let course = courses.first(where: { $0.name == courseName }) ?? courses.first else { return }
        let list = players
        Task {
            if let id = await backend.createMatch(format: format, basis: basis, allowance: allowance, course: course, players: list) {
                dismiss()
                onCreated(id)
            }
        }
    }
}

/// One match: live standings, and hole-by-hole score entry for the group's scorer.
struct MatchView: View {
    let matchID: UUID

    @ObservedObject private var backend = Backend.shared
    @Environment(\.dismiss) private var dismiss
    @State private var hole = 1
    @State private var draft: [String: Int] = [:]
    @State private var confirmFinish = false
    @State private var confirmDelete = false

    private var match: LiveMatch? { backend.matches.first { $0.id == matchID } }

    var body: some View {
        Group {
            if let match {
                content(match)
            } else {
                ProgressView()
            }
        }
        .background(Color.tgBackground)
        .navigationTitle(match?.format.label ?? "Match")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Keep the scores fresh while the match is open, so everyone sees the same thing.
            while !Task.isCancelled {
                if match?.isLive ?? false { await backend.refreshMatch(matchID) }
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }

    private func content(_ match: LiveMatch) -> some View {
        let outcome = match.outcome
        let setup = match.setup
        let handicaps = MatchEngine.playingHandicaps(setup)

        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if match.isLive {
                            Circle().fill(Color.tgAccent).frame(width: 7, height: 7)
                            Text("LIVE").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Color.tgAccent)
                        } else {
                            Text("FINAL").font(.caption.weight(.bold)).tracking(1).foregroundStyle(Color.tgMuted)
                        }
                        Text("· \(match.match.courseName) · \(setup.basis == .net ? "Net" : "Gross")")
                            .font(.caption)
                            .foregroundStyle(Color.tgMuted)
                    }
                    Text(outcome.status)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(outcome.holesComplete) of \(setup.holes.count) holes scored")
                        .font(.footnote)
                        .foregroundStyle(Color.tgMuted)
                }

                VStack(alignment: .leading, spacing: 0) {
                    SectionLabel("Standings").padding(.bottom, 6)
                    ForEach(outcome.standings) { row in
                        HStack(spacing: 12) {
                            Text(row.positionLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(row.position == 1 ? Color.tgAccent : Color.tgMuted)
                                .frame(width: 28, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.name).font(.body.weight(.semibold))
                                Text("Gets \(handicaps[row.key] ?? 0)" + (row.detail.isEmpty ? "" : " · \(row.detail)"))
                                    .font(.caption)
                                    .foregroundStyle(Color.tgMuted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text(row.value).font(.title3.weight(.semibold)).monospacedDigit()
                        }
                        .frame(minHeight: 54)
                        Hairline()
                    }
                }

                if match.isLive {
                    scoringCard(match, setup: setup, handicaps: handicaps)

                    Button("Finish match") { confirmFinish = true }
                        .buttonStyle(SecondaryButtonStyle())
                }

                if match.match.createdBy == backend.myID {
                    Button("Delete match", role: .destructive) { confirmDelete = true }
                        .font(.footnote)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .onAppear {
            hole = setup.holes.first { h in setup.players.contains { match.scores[$0.key]?[h.number] == nil } }?.number
                ?? setup.holes.last?.number ?? 1
            loadDraft(match)
        }
        .onChange(of: hole) { loadDraft(match) }
        .confirmationDialog("Finish this match?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish match") { Task { await backend.finishMatch(matchID) } }
        } message: {
            Text(outcome.isFinished ? "The result goes into everyone's rivalry records." : "Not every hole has a score yet. The result will be based on the holes played.")
        }
        .confirmationDialog("Delete this match for everyone?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete match", role: .destructive) {
                Task {
                    await backend.deleteMatch(matchID)
                    dismiss()
                }
            }
        }
    }

    private func scoringCard(_ match: LiveMatch, setup: MatchSetup, handicaps: [String: Int]) -> some View {
        let info = setup.holes.first { $0.number == hole }
        let numbers = setup.holes.map(\.number)
        let index = numbers.firstIndex(of: hole) ?? 0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button { hole = numbers[max(0, index - 1)] } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }
                .disabled(index == 0)
                .accessibilityLabel("Previous hole")
                Spacer()
                VStack(spacing: 2) {
                    Text("Hole \(hole)").font(.title3.weight(.semibold))
                    if let info {
                        Text("PAR \(info.par) · SI \(info.strokeIndex)").font(.caption).foregroundStyle(Color.tgMuted)
                    }
                }
                Spacer()
                Button { hole = numbers[min(numbers.count - 1, index + 1)] } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }
                .disabled(index == numbers.count - 1)
                .accessibilityLabel("Next hole")
            }
            .buttonStyle(.plain)

            ForEach(setup.players, id: \.key) { player in
                let strokes = info.map { MatchEngine.strokesReceived(setup, playingHandicap: handicaps[player.key] ?? 0, hole: $0) } ?? 0
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(player.name).font(.body.weight(.semibold))
                        Text(strokes > 0 ? String(repeating: "•", count: strokes) + " gets \(strokes)" : (strokes < 0 ? "gives \(-strokes)" : " "))
                            .font(.caption)
                            .foregroundStyle(Color.tgAccent)
                    }
                    Spacer()
                    Button { change(player.key, -1, par: info?.par ?? 4) } label: {
                        Image(systemName: "minus").frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
                    }
                    .accessibilityLabel("Fewer strokes for \(player.name)")
                    Text("\(draft[player.key] ?? info?.par ?? 4)")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .frame(width: 44)
                    Button { change(player.key, 1, par: info?.par ?? 4) } label: {
                        Image(systemName: "plus").frame(width: 44, height: 44)
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
                    }
                    .accessibilityLabel("More strokes for \(player.name)")
                }
                .buttonStyle(.plain)
                .frame(minHeight: 56)
                Hairline()
            }

            Button(index == numbers.count - 1 ? "Save last hole" : "Save hole \(hole) and next") {
                save(setup: setup, numbers: numbers, index: index, par: info?.par ?? 4)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(backend.isBusy)

            if let message = backend.message {
                Text(message).font(.footnote).foregroundStyle(Color.tgLoss)
            }
        }
        .padding(.top, 4)
    }

    private func loadDraft(_ match: LiveMatch) {
        var values: [String: Int] = [:]
        for p in match.players { if let s = match.scores[p.playerKey]?[hole] { values[p.playerKey] = s } }
        draft = values
    }

    private func change(_ key: String, _ delta: Int, par: Int) {
        draft[key] = min(15, max(1, (draft[key] ?? par) + delta))
    }

    private func save(setup: MatchSetup, numbers: [Int], index: Int, par: Int) {
        var strokes: [String: Int] = [:]
        for p in setup.players { strokes[p.key] = draft[p.key] ?? par }
        let current = hole
        Task {
            await backend.saveHole(matchID, hole: current, strokes: strokes)
            if backend.message == nil && index < numbers.count - 1 { hole = numbers[index + 1] }
        }
    }
}

/// All-time record against one friend, for the friend's page.
struct RivalrySection: View {
    let friend: ProfileDTO
    @ObservedObject private var backend = Backend.shared

    var body: some View {
        let rivalry = backend.rivalry(with: friend.id)
        let r = rivalry.record

        VStack(alignment: .leading, spacing: 14) {
            SectionLabel("Head to head · all time")
            if r.played == 0 {
                Text("No finished matches against \(friend.displayName) yet. Start one from the Friends tab.")
                    .font(.footnote)
                    .foregroundStyle(Color.tgMuted)
            } else {
                HStack(spacing: 28) {
                    big("\(r.wins)", "WON", Color.tgAccent)
                    big("\(r.halves)", "HALVED", Color.primary)
                    big("\(r.losses)", "LOST", Color.tgLoss)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Form · last \(min(10, r.form.count))").font(.caption).foregroundStyle(Color.tgMuted)
                    let form = Array(r.form.prefix(10))
                    HStack(spacing: 4) {
                        ForEach(form.indices, id: \.self) { i in
                            let result = form[i]
                            Text(result == .win ? "W" : (result == .loss ? "L" : "H"))
                                .font(.caption.weight(.bold))
                                .frame(width: 26, height: 26)
                                .foregroundStyle(result == .halve ? Color.primary : Color.tgBackground)
                                .background(result == .win ? Color.tgAccent : (result == .loss ? Color.tgLoss : Color.tgLine),
                                            in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Recent results: " + r.form.prefix(10).map { $0 == .win ? "won" : ($0 == .loss ? "lost" : "halved") }.joined(separator: ", "))
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(MatchFormat.allCases) { format in
                        if let f = r.byFormat[format] {
                            HStack {
                                Text(format.label)
                                Spacer()
                                Text("\(f.wins)–\(f.halves)–\(f.losses)").fontWeight(.semibold).monospacedDigit()
                            }
                            .frame(minHeight: 40)
                            Hairline()
                        }
                    }
                    Text("Won–halved–lost").font(.caption2).foregroundStyle(Color.tgMuted).padding(.top, 4)
                }
            }
        }
    }

    private func big(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 44, weight: .semibold)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(Color.tgMuted)
        }
    }
}
