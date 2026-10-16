import SwiftUI
import SwiftData

struct ScoringView: View {
    @Bindable var round: Round
    @Environment(\.dismiss) private var dismiss

    @State private var holeNumber: Int
    @State private var showSummary = false
    @State private var confirmFinish = false

    init(round: Round) {
        self.round = round
        let firstOpen = round.sortedScores.first { !$0.isEntered }?.number
        _holeNumber = State(initialValue: firstOpen ?? round.lastHoleNumber)
    }

    private var isLastHole: Bool { holeNumber >= round.lastHoleNumber }
    private var missingHoles: Int { round.holes.count - round.enteredScores.count }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            ScrollView {
                if let hole = round.hole(holeNumber), let score = round.score(for: holeNumber) {
                    HoleEntryView(score: score, par: hole.par)
                        .id(holeNumber)
                        .padding(20)
                }
            }
            Hairline()
            Button(isLastHole ? "Finish round" : "Next hole") { next() }
                .buttonStyle(PrimaryButtonStyle())
                .padding(16)
        }
        .background(Color.tgBackground)
        .navigationTitle(round.courseName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Finish round?", isPresented: $confirmFinish, titleVisibility: .visible) {
            Button("Finish round") { finish() }
            Button("Keep scoring", role: .cancel) {}
        } message: {
            Text("\(missingHoles) hole\(missingHoles == 1 ? " has" : "s have") no score. Only 18-hole rounds count towards your handicap.")
        }
        .fullScreenCover(isPresented: $showSummary, onDismiss: { dismiss() }) {
            NavigationStack {
                RoundSummaryView(round: round, onDone: { showSummary = false })
            }
        }
    }

    private var header: some View {
        let hole = round.hole(holeNumber)
        return VStack(spacing: 10) {
            HStack {
                navButton("chevron.left", label: "Previous hole", disabled: holeNumber <= 1) { holeNumber -= 1 }
                Spacer()
                VStack(spacing: 2) {
                    Text("Hole \(holeNumber)").font(.title2.weight(.semibold))
                    if let hole {
                        Text("PAR \(hole.par)\(hole.yards > 0 ? " · \(hole.yards) YD" : "") · SI \(hole.strokeIndex)")
                            .font(.caption.weight(.medium))
                            .tracking(0.5)
                            .foregroundStyle(Color.tgMuted)
                    }
                }
                Spacer()
                navButton("chevron.right", label: "Next hole", disabled: isLastHole) { holeNumber += 1 }
            }
            HStack {
                Text("Thru \(round.enteredScores.count)")
                Spacer()
                Text("\(round.totalStrokes) ")
                    + Text(formatToPar(round.toPar)).foregroundColor(scoreColor(round.toPar))
            }
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
        }
        .padding(16)
    }

    private func navButton(_ icon: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.tgLine))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(label)
    }

    private func next() {
        round.score(for: holeNumber)?.isEntered = true
        if isLastHole {
            if missingHoles > 0 {
                confirmFinish = true
            } else {
                finish()
            }
        } else {
            holeNumber += 1
        }
    }

    private func finish() {
        round.isComplete = true
        showSummary = true
    }
}

struct HoleEntryView: View {
    @Bindable var score: HoleScore
    let par: Int

    private var fingerprint: String {
        "\(score.strokes)|\(score.putts)|\(score.firstPuttFeet)|\(score.penalties)|\(score.fairway ?? "")|\(score.green ?? "")|\(String(describing: score.upAndDown))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    StepperCell(title: "Score", value: $score.strokes, range: 1...15)
                    Rectangle().fill(Color.tgLine).frame(width: 1)
                    StepperCell(title: "Putts", value: $score.putts, range: 0...6)
                }
                Hairline()
                HStack(spacing: 0) {
                    StepperCell(title: "First putt ft", value: $score.firstPuttFeet, range: 0...99)
                    Rectangle().fill(Color.tgLine).frame(width: 1)
                    StepperCell(title: "Penalties", value: $score.penalties, range: 0...5)
                }
            }
            .overlay(alignment: .top) { Hairline() }
            .overlay(alignment: .bottom) { Hairline() }

            Text(scoreName)
                .font(.headline)
                .foregroundStyle(scoreColor(score.strokes - par))

            if par >= 4 {
                ChoiceRow(title: "Fairway", options: FairwayResult.allCases, selection: $score.fairwayResult) { $0.label }
            }
            ChoiceRow(title: "Green", options: GreenResult.allCases, selection: $score.greenResult) { $0.label }
            if score.greenResult != .hit {
                ChoiceRow(title: "Up and down", options: [true, false], selection: $score.upAndDown) { $0 ? "Yes" : "No" }
            }
        }
        .onChange(of: fingerprint) {
            score.isEntered = true
        }
        .onChange(of: score.green) {
            if score.greenResult == .hit { score.upAndDown = nil }
        }
    }

    private var scoreName: String {
        if score.strokes == 1 { return "Hole in one" }
        switch score.strokes - par {
        case ...(-3): return "Albatross"
        case -2: return "Eagle"
        case -1: return "Birdie"
        case 0: return "Par"
        case 1: return "Bogey"
        case 2: return "Double bogey"
        case 3: return "Triple bogey"
        default: return "+\(score.strokes - par)"
        }
    }
}
