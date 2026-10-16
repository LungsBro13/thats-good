import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Bring in old scores from a CSV file or pasted text, and see what's been imported.
struct ImportScoresView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ImportedScore.playedOn, order: .reverse) private var imported: [ImportedScore]

    @State private var text = ""
    @State private var result: ScoreImport.Result?
    @State private var choosingFile = false
    @State private var message: String?
    @State private var confirmDeleteAll = false
    @State private var showingCard: ImportedScore?

    private var newRounds: [ImportedRound] {
        ScoreImport.newOnly(result?.rounds ?? [], existing: imported.map(\.data))
    }

    var body: some View {
        List {
            Section {
                Button { choosingFile = true } label: { Label("Choose a file", systemImage: "doc") }
                TextEditor(text: $text)
                    .font(.caption.monospaced())
                    .frame(minHeight: 120)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("…or paste here")
                                .font(.caption)
                                .foregroundStyle(Color.tgMuted)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: text) { result = text.isEmpty ? nil : ScoreImport.parse(text) }
            } header: {
                Text("Add scores")
            } footer: {
                Text("A CSV file with a header row: date, course, tee, adj_gross, course_rating, slope, pcc. Optional: holes and pars, as 18 numbers with spaces between.")
            }

            if let result {
                Section("Check") {
                    Text("\(result.rounds.count) score\(result.rounds.count == 1 ? "" : "s") read · \(newRounds.count) new")
                        .font(.subheadline.weight(.semibold))
                    ForEach(result.problems, id: \.self) { problem in
                        Text(problem).font(.footnote).foregroundStyle(Color.tgLoss)
                    }
                    Button("Import \(newRounds.count) score\(newRounds.count == 1 ? "" : "s")") { importNew() }
                        .disabled(newRounds.isEmpty)
                }
            }
            if let message {
                Text(message).font(.footnote).foregroundStyle(Color.tgAccent)
            }

            if !imported.isEmpty {
                Section {
                    ForEach(imported) { score in
                        Button { if !score.holeStrokes.isEmpty { showingCard = score } } label: {
                            ImportedScoreRow(score: score)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(imported[i]) }
                    }
                    Button("Delete all imported scores", role: .destructive) { confirmDeleteAll = true }
                } header: {
                    Text("Imported · \(imported.count)")
                } footer: {
                    Text("These count towards your handicap estimate. They don't have putts or fairways, so they don't change your other stats.")
                }
            }
        }
        .navigationTitle("Import scores")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.commaSeparatedText, .tabSeparatedText, .plainText, .text]) { picked in
            readFile(picked)
        }
        .sheet(item: $showingCard) { score in
            NavigationStack { ImportedCardView(score: score) }
                .presentationDetents([.medium])
        }
        .confirmationDialog("Delete all imported scores?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                for score in imported { context.delete(score) }
            }
        }
        #if DEBUG
        .onAppear {
            // CI screenshot: a made-up sample, not anyone's real scores.
            if ProcessInfo.processInfo.arguments.contains("-importSample"), text.isEmpty {
                text = """
                date,course,tee,adj_gross,course_rating,slope,pcc
                05/10/2026,Demo Golf Club,Blue,79,71.8,128,0
                21/09/2026,Demo Golf Club,Blue,83,71.8,128,-1
                """
            }
        }
        #endif
    }

    private func readFile(_ picked: Result<URL, Error>) {
        switch picked {
        case .success(let url):
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let content = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) {
                text = content
            } else {
                message = "Couldn't read that file."
            }
        case .failure(let error):
            message = error.localizedDescription
        }
    }

    private func importNew() {
        let rounds = newRounds
        for r in rounds { context.insert(ImportedScore(r)) }
        message = "Imported \(rounds.count) score\(rounds.count == 1 ? "" : "s"). Your handicap on Home now includes them."
        text = ""
        result = nil
    }
}

struct ImportedScoreRow: View {
    let score: ImportedScore

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(score.courseName).font(.body.weight(.semibold)).lineLimit(1)
                Text("\(score.playedOn.formatted(date: .abbreviated, time: .omitted))" + (score.teeName.isEmpty ? "" : " · \(score.teeName)")
                     + (score.holeStrokes.isEmpty ? "" : " · card"))
                    .font(.caption)
                    .foregroundStyle(Color.tgMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(score.adjustedGross)").font(.title3.weight(.semibold)).monospacedDigit()
                Text("diff \(formatDecimal(score.data.differential))").font(.caption).foregroundStyle(Color.tgMuted)
            }
        }
        .contentShape(Rectangle())
    }
}

/// The hole-by-hole card of an imported score.
struct ImportedCardView: View {
    let score: ImportedScore

    var body: some View {
        let strokes = score.holeStrokes
        let pars = score.holePars
        let halves = strokes.count == 18 ? [0..<9, 9..<18] : [0..<strokes.count]

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("\(score.playedOn.formatted(date: .long, time: .omitted)) · adjusted \(score.adjustedGross)")
                    .font(.subheadline)
                    .foregroundStyle(Color.tgMuted)
                ForEach(halves, id: \.lowerBound) { range in
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Hole").foregroundStyle(Color.tgMuted)
                            if !pars.isEmpty { Text("Par").foregroundStyle(Color.tgMuted) }
                            Text("Score")
                        }
                        .font(.caption)
                        .frame(width: 44, alignment: .leading)
                        ForEach(Array(range), id: \.self) { i in
                            VStack(spacing: 6) {
                                Text("\(i + 1)").foregroundStyle(Color.tgMuted)
                                if !pars.isEmpty { Text("\(pars[i])").foregroundStyle(Color.tgMuted) }
                                Text("\(strokes[i])")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(pars.isEmpty ? Color.primary : scoreColor(strokes[i] - pars[i]))
                            }
                            .font(.caption)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                        }
                        VStack(spacing: 6) {
                            Text(range.lowerBound == 0 ? (strokes.count == 18 ? "Out" : "Tot") : "In").foregroundStyle(Color.tgMuted)
                            if !pars.isEmpty { Text("\(pars[range].reduce(0, +))").foregroundStyle(Color.tgMuted) }
                            Text("\(strokes[range].reduce(0, +))").fontWeight(.bold)
                        }
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 34)
                    }
                    Hairline()
                }
                Text("Total \(strokes.reduce(0, +))" + (pars.isEmpty ? "" : " · par \(pars.reduce(0, +))"))
                    .font(.headline)
            }
            .padding(20)
        }
        .navigationTitle(score.courseName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
