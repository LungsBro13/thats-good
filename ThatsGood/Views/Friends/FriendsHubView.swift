import SwiftUI
import SwiftData
import Charts

/// Everyone the player can see: themselves plus accepted friends.
struct PlayerSnapshot: Identifiable {
    let profile: ProfileDTO
    let rounds: [SharedRoundDTO]
    let progress: PlayerProgress
    let isMe: Bool

    var id: UUID { profile.id }
}

struct FriendsHubView: View {
    @ObservedObject private var backend = Backend.shared
    @Environment(\.modelContext) private var context

    @State private var addingFriend = false
    @State private var measure: ProgressMeasure = .handicap
    @State private var board: LeaderboardKind = .handicap

    enum ProgressMeasure: String, CaseIterable {
        case handicap, score
        var label: String { self == .handicap ? "Handicap" : "Avg score" }
    }

    private var players: [PlayerSnapshot] {
        var list: [PlayerSnapshot] = []
        if let me = backend.profile {
            let mine = backend.rounds[me.id] ?? []
            list.append(PlayerSnapshot(profile: me, rounds: mine, progress: PlayerProgress.compute(mine.map(\.data)), isMe: true))
        }
        for friend in backend.friends {
            let theirs = backend.rounds[friend.id] ?? []
            list.append(PlayerSnapshot(profile: friend, rounds: theirs, progress: PlayerProgress.compute(theirs.map(\.data)), isMe: false))
        }
        return list
    }

    var body: some View {
        let everyone = players
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !backend.incoming.isEmpty { requests }
                summary(everyone)
                if backend.friends.isEmpty {
                    emptyState
                } else {
                    progressSection(everyone)
                    leaderboardSection(everyone)
                    activitySection(everyone)
                }
                if !backend.outgoing.isEmpty {
                    Text("Waiting for " + backend.outgoing.map { "@\($0.username)" }.joined(separator: ", "))
                        .font(.footnote)
                        .foregroundStyle(Color.tgMuted)
                }
                if let message = backend.message {
                    Text(message).font(.footnote).foregroundStyle(Color.tgMuted)
                }
            }
            .padding(20)
        }
        .background(Color.tgBackground)
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { addingFriend = true } label: { Image(systemName: "person.badge.plus") }
                    .accessibilityLabel("Add a friend")
            }
            ToolbarItem(placement: .topBarLeading) { accountMenu }
        }
        .sheet(isPresented: $addingFriend) { AddFriendView() }
        .refreshable {
            await backend.sync(context: context)
            await backend.refresh()
        }
        .task {
            await backend.sync(context: context)
            await backend.refresh()
        }
    }

    // MARK: Sections

    private var accountMenu: some View {
        Menu {
            if let me = backend.profile {
                Text("@\(me.username)")
                Picker("Who sees my rounds", selection: Binding(
                    get: { me.statsVisibility },
                    set: { value in Task { await backend.setVisibility(value) } })) {
                    Text("Friends").tag("friends")
                    Text("Everyone").tag("public")
                    Text("Only me").tag("private")
                }
            }
            Button("Sign out", role: .destructive) { Task { await backend.signOut() } }
        } label: {
            Image(systemName: "person.crop.circle")
        }
        .accessibilityLabel("Account")
    }

    private var requests: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Friend requests").padding(.bottom, 6)
            ForEach(backend.incoming) { person in
                HStack(spacing: 12) {
                    Avatar(initials: person.initials)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(person.displayName).font(.body.weight(.semibold))
                        Text("@\(person.username)").font(.caption).foregroundStyle(Color.tgMuted)
                    }
                    Spacer()
                    Button("Accept") { Task { await backend.accept(person) } }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.borderedProminent)
                    Button { Task { await backend.remove(person) } } label: { Image(systemName: "xmark") }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Decline")
                }
                .frame(minHeight: 56)
                Hairline()
            }
        }
    }

    private func summary(_ everyone: [PlayerSnapshot]) -> some View {
        let me = everyone.first { $0.isMe }
        return HStack(spacing: 0) {
            StatTile(title: "Friends", value: "\(backend.friends.count)")
            StatTile(title: "Rounds shared", value: "\(me?.rounds.count ?? 0)")
            StatTile(title: "Your handicap", value: formatDecimal(me?.progress.handicap))
        }
        .overlay(alignment: .top) { Hairline() }
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add your mates").font(.headline)
            Text("Tap the person icon at the top and enter their username. Yours is @\(backend.profile?.username ?? "").")
                .font(.subheadline)
                .foregroundStyle(Color.tgMuted)
            Button("Add a friend") { addingFriend = true }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private func progressSection(_ everyone: [PlayerSnapshot]) -> some View {
        let rows = everyone.sorted { a, b in
            let x = change(a.progress) ?? .infinity, y = change(b.progress) ?? .infinity
            return x < y
        }
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                SectionLabel("Progress · last 90 days")
                Spacer()
                SegmentedPicker(options: ProgressMeasure.allCases, selection: $measure) { $0.label }
                    .frame(width: 190)
                    .scaleEffect(0.9, anchor: .trailing)
            }
            .padding(.bottom, 6)
            ForEach(rows) { player in
                NavigationLink {
                    FriendDetailView(player: player, me: everyone.first { $0.isMe })
                } label: {
                    ProgressRow(player: player, value: current(player.progress), change: change(player.progress),
                                trend: measure == .handicap ? player.progress.trend : [])
                }
                .buttonStyle(.plain)
                Hairline()
            }
        }
    }

    private func current(_ p: PlayerProgress) -> Double? {
        measure == .handicap ? p.handicap : p.averageScore
    }

    private func change(_ p: PlayerProgress) -> Double? {
        measure == .handicap ? p.handicapChange : p.averageScoreChange
    }

    private func leaderboardSection(_ everyone: [PlayerSnapshot]) -> some View {
        let byID = Dictionary(uniqueKeysWithValues: everyone.map { ($0.id, $0) })
        let ranked = Leaderboard.rank(byID.mapValues(\.progress), by: board)
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Leaderboard · all time").padding(.bottom, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 18) {
                    ForEach(LeaderboardKind.allCases) { kind in
                        Button { board = kind } label: {
                            Text(kind.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(board == kind ? Color.primary : Color.tgMuted)
                                .padding(.vertical, 10)
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(board == kind ? Color.tgAccent : Color.clear).frame(height: 2)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(board == kind ? .isSelected : [])
                    }
                }
            }
            Hairline()
            if ranked.isEmpty {
                Text("Not enough rounds yet.").font(.footnote).foregroundStyle(Color.tgMuted).padding(.vertical, 12)
            }
            ForEach(ranked.indices, id: \.self) { position in
                let entry = ranked[position]
                if let player = byID[entry.id] {
                    HStack(spacing: 12) {
                        Text("\(position + 1)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(position == 0 ? Color.tgAccent : Color.tgMuted)
                            .frame(width: 20, alignment: .leading)
                        Avatar(initials: player.profile.initials)
                        Text(player.isMe ? "You" : player.profile.displayName).font(.body.weight(.semibold))
                        Spacer()
                        Text(boardValue(entry.value)).font(.body.weight(.semibold)).monospacedDigit()
                    }
                    .frame(minHeight: 52)
                    .foregroundStyle(player.isMe ? Color.tgAccent : Color.primary)
                    Hairline()
                }
            }
        }
    }

    private func boardValue(_ value: Double) -> String {
        switch board {
        case .handicap: return formatDecimal(value)
        case .improved: return (value > 0 ? "+" : value < 0 ? "−" : "") + formatDecimal(abs(value))
        case .bestRound, .rounds: return "\(Int(value))"
        }
    }

    private func activitySection(_ everyone: [PlayerSnapshot]) -> some View {
        let recent = Array(everyone.flatMap { player in player.rounds.map { ActivityItem(player: player, round: $0) } }
            .sorted { $0.round.date > $1.round.date }
            .prefix(12))
        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel("Activity").padding(.bottom, 6)
            ForEach(recent) { item in
                let player = item.player, round = item.round
                HStack(spacing: 12) {
                    Avatar(initials: player.profile.initials)
                    VStack(alignment: .leading, spacing: 2) {
                        (Text(player.isMe ? "You" : player.profile.displayName).fontWeight(.semibold)
                         + Text(" shot \(round.strokes) (\(formatToPar(round.toPar)))").foregroundColor(Color.tgMuted))
                            .font(.subheadline)
                        Text("\(round.courseName) · \(round.date.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(Color.tgMuted)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .frame(minHeight: 52)
                Hairline()
            }
        }
    }
}

private struct ActivityItem: Identifiable {
    let player: PlayerSnapshot
    let round: SharedRoundDTO
    var id: UUID { round.id }
}

private struct TrendPoint: Identifiable {
    let id: Int
    let value: Double
}

struct Avatar: View {
    let initials: String

    var body: some View {
        Text(initials)
            .font(.caption.weight(.bold))
            .frame(width: 34, height: 34)
            .background(Color.tgSurface, in: Circle())
            .overlay(Circle().stroke(Color.tgLine))
            .accessibilityHidden(true)
    }
}

struct ProgressRow: View {
    let player: PlayerSnapshot
    let value: Double?
    let change: Double?
    let trend: [Double]

    var body: some View {
        HStack(spacing: 12) {
            Avatar(initials: player.profile.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(player.isMe ? "You" : player.profile.displayName).font(.body.weight(.semibold))
                Text(value.map { formatDecimal($0) } ?? "Needs 3 rounds")
                    .font(.caption)
                    .foregroundStyle(Color.tgMuted)
            }
            Spacer()
            if trend.count >= 2 {
                Chart(trend.indices.map { TrendPoint(id: $0, value: trend[$0]) }) { item in
                    LineMark(x: .value("Round", item.id), y: .value("Handicap", item.value))
                        .foregroundStyle((change ?? 0) <= 0 ? Color.tgAccent : Color.tgLoss)
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(width: 64, height: 26)
                .accessibilityHidden(true)
            }
            Text(change.map { ($0 > 0 ? "+" : $0 < 0 ? "−" : "") + formatDecimal(abs($0)) } ?? "–")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(change.map { $0 <= 0 ? Color.tgAccent : Color.tgLoss } ?? Color.tgMuted)
                .frame(width: 48, alignment: .trailing)
        }
        .frame(minHeight: 56)
        .contentShape(Rectangle())
    }
}
