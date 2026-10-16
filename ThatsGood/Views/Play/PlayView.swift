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
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-osmDemo") {
                    Task { await openOSMDemo() }
                    return
                }
                guard args.contains("-openRound"), activeRound == nil,
                      let course = courses.first else { return }
                activeRound = openRounds.first
                    ?? Round.start(course: course, handicapIndex: Handicap.currentIndex(completedRounds.map(\.data)), in: context)
            }
            #endif
        }
    }
}

#if DEBUG
extension PlayView {
    /// Downloads a real, well-mapped course from OpenStreetMap and opens hole 1 in Detailed mode.
    func openOSMDemo() async {
        guard activeRound == nil else { return }
        let pars = [4, 4, 4, 4, 5, 4, 4, 3, 4, 4, 3, 4, 4, 5, 4, 4, 4, 4]
        let holes = pars.enumerated().map { CourseHole(number: $0.offset + 1, par: $0.element, strokeIndex: $0.offset + 1, yards: 0) }
        let course = Course(name: "Old Course (map test)", teeName: "White", courseRating: 72.0, slope: 132, holes: holes)
        context.insert(course)
        activeRound = Round.start(course: course, handicapIndex: nil, in: context, mode: "detailed")
        if let geo = try? await CourseMapService.download(around: GeoPoint(lat: 56.3445, lon: -2.8090), radius: 1500) {
            course.geo = geo
        }
    }
}
#endif

struct StartRoundSheet: View {
    let course: Course
    let handicapIndex: Double?
    let onStart: (Round) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var mode = "quick"

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text(course.name).font(.title2.weight(.semibold))

                SegmentedPicker(options: ["quick", "detailed"], selection: $mode) { $0 == "quick" ? "Quick" : "Detailed" }

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    row("Tees", course.teeName)
                    row("Par", "\(course.par)")
                    row("Course rating / slope", "\(formatDecimal(course.courseRating)) / \(course.slope)")
                    row("Your handicap index", handicapIndex.map { formatDecimal($0) } ?? "Not yet")
                    if let handicapIndex {
                        row("Course handicap", "\(Handicap.courseHandicap(index: handicapIndex, slope: course.slope, rating: course.courseRating, par: course.par))")
                    }
                }

                Text(modeHelp)
                    .font(.footnote)
                    .foregroundStyle(Color.tgMuted)

                Spacer()

                Button("Tee off") {
                    let round = Round.start(course: course, handicapIndex: handicapIndex, in: context, mode: mode)
                    if mode == "detailed" { LocationManager.shared.start() }
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

    private var modeHelp: String {
        if mode == "quick" {
            return "Quick mode: enter score, putts, fairway, green and up and down for each hole."
        }
        let map = course.geo?.summary ?? "No map data"
        return "Detailed mode: GPS yardages and a shot marker on each hole, for club distances and strokes gained. Map: \(map). You can set any missing green as you play."
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(Color.tgMuted)
            Text(value).fontWeight(.semibold)
        }
        .font(.subheadline)
    }
}
