import SwiftUI
import SwiftData

struct PlayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.name) private var courses: [Course]
    @Query(filter: #Predicate<Round> { !$0.isComplete }, sort: \Round.playedOn, order: .reverse)
    private var openRounds: [Round]
    @Query(filter: #Predicate<Round> { $0.isComplete }) private var completedRounds: [Round]

    @State private var activeRound: Round?
    @State private var chosenCourse: Course?
    @State private var addingCourse = false

    var body: some View {
        NavigationStack {
            List {
                if !openRounds.isEmpty {
                    Section("Round in progress") {
                        ForEach(openRounds) { round in
                            Button { activeRound = round } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(round.courseName).font(.body.weight(.semibold))
                                        Text("Thru \(round.enteredScores.count) · \(formatToPar(round.toPar))")
                                            .font(.caption)
                                            .foregroundStyle(Color.tgMuted)
                                    }
                                    Spacer()
                                    Text("Resume").font(.subheadline.weight(.semibold))
                                }
                            }
                            .foregroundStyle(Color.primary)
                        }
                        .onDelete { offsets in
                            for i in offsets { context.delete(openRounds[i]) }
                        }
                    }
                }

                Section {
                    if courses.isEmpty {
                        Text("No courses yet. Add your course from its scorecard, or load demo rounds in the Bag tab.")
                            .font(.subheadline)
                            .foregroundStyle(Color.tgMuted)
                    }
                    ForEach(courses) { course in
                        Button { chosenCourse = course } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(course.name).font(.body.weight(.semibold))
                                    Text("\(course.teeName) tees · par \(course.par) · \(formatDecimal(course.courseRating)) / \(course.slope)")
                                        .font(.caption)
                                        .foregroundStyle(Color.tgMuted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(Color.tgMuted)
                            }
                        }
                        .foregroundStyle(Color.primary)
                    }
                    Button { addingCourse = true } label: {
                        Label("Add a course", systemImage: "plus")
                    }
                } header: {
                    Text("Choose a course")
                }
            }
            .navigationTitle("Play")
            .navigationDestination(item: $activeRound) { round in
                ScoringView(round: round)
            }
            .sheet(item: $chosenCourse) { course in
                StartRoundSheet(course: course,
                                handicapIndex: Handicap.currentIndex(completedRounds.map(\.data))) { round in
                    activeRound = round
                }
            }
            .sheet(isPresented: $addingCourse) {
                CourseEditorView()
            }
            #if DEBUG
            .onAppear {
                // Used by the CI screenshot step to open the scoring screen.
                guard ProcessInfo.processInfo.arguments.contains("-openRound"), activeRound == nil,
                      let course = courses.first else { return }
                activeRound = openRounds.first
                    ?? Round.start(course: course, handicapIndex: Handicap.currentIndex(completedRounds.map(\.data)), in: context)
            }
            #endif
        }
    }
}

struct StartRoundSheet: View {
    let course: Course
    let handicapIndex: Double?
    let onStart: (Round) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(course.name).font(.title2.weight(.semibold))

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    row("Tees", course.teeName)
                    row("Par", "\(course.par)")
                    row("Course rating / slope", "\(formatDecimal(course.courseRating)) / \(course.slope)")
                    row("Your handicap index", handicapIndex.map { formatDecimal($0) } ?? "Not yet")
                    if let handicapIndex {
                        row("Course handicap", "\(Handicap.courseHandicap(index: handicapIndex, slope: course.slope, rating: course.courseRating, par: course.par))")
                    }
                }

                Text("Quick mode: enter score, putts, fairway, green and up and down for each hole. GPS and Detailed mode arrive in Phase 2.")
                    .font(.footnote)
                    .foregroundStyle(Color.tgMuted)

                Spacer()

                Button("Tee off") {
                    let round = Round.start(course: course, handicapIndex: handicapIndex, in: context)
                    dismiss()
                    onStart(round)
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(Color.tgMuted)
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}
