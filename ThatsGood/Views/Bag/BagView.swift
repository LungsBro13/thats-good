import SwiftUI
import SwiftData

struct BagView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.name) private var courses: [Course]
    @Query private var rounds: [Round]
    @Query(sort: \Club.sortOrder) private var clubs: [Club]

    private var distances: [ClubDistance] {
        ClubStats.summarize(rounds.flatMap(\.clubSamples), order: clubs.map(\.name))
    }

    private var maxYards: Double {
        max(100, distances.map { $0.median + $0.spread }.max() ?? 0)
    }

    @State private var editingCourse: Course?
    @State private var addingCourse = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if distances.isEmpty {
                        Text("Play in Detailed mode and mark your shots. Your stock yardage for each club shows here.")
                            .font(.subheadline)
                            .foregroundStyle(Color.tgMuted)
                    }
                    ForEach(distances) { item in
                        HStack {
                            Text(item.club).font(.body.weight(.semibold)).frame(width: 44, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(Int(item.median.rounded())) yd")
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                                Text("± \(Int(item.spread.rounded())) · \(item.count) shot\(item.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundStyle(Color.tgMuted)
                            }
                            Spacer()
                            ClubRangeBar(item: item, maxYards: maxYards)
                                .frame(width: 140, height: 14)
                        }
                    }
                    NavigationLink("Edit clubs in bag") { ClubListView() }
                } header: {
                    Text("Stock yardages")
                } footer: {
                    Text("Median distance from where each shot was hit to where the next one was marked. Recovery shots aren't counted.")
                }

                Section {
                    ForEach(courses) { course in
                        Button { editingCourse = course } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(course.name).font(.body.weight(.semibold))
                                Text("\(course.teeName) tees · par \(course.par)")
                                    .font(.caption)
                                    .foregroundStyle(Color.tgMuted)
                            }
                        }
                        .foregroundStyle(Color.primary)
                    }
                    .onDelete { offsets in
                        for i in offsets { context.delete(courses[i]) }
                    }
                    Button { addingCourse = true } label: {
                        Label("Add a course", systemImage: "plus")
                    }
                } header: {
                    Text("Courses")
                } footer: {
                    Text("Deleting a course keeps your old rounds.")
                }

                Section {
                    Button("Load demo rounds") { SampleData.load(into: context) }
                    Button("Delete all rounds", role: .destructive) { confirmDelete = true }
                        .disabled(rounds.isEmpty)
                } header: {
                    Text("Test data")
                } footer: {
                    Text("Demo rounds let you try the stats before you've played. \(rounds.count) round\(rounds.count == 1 ? "" : "s") saved.")
                }
            }
            .navigationTitle("Bag")
            .sheet(item: $editingCourse) { course in
                CourseEditorView(course: course)
            }
            .sheet(isPresented: $addingCourse) {
                CourseEditorView()
            }
            .confirmationDialog("Delete all rounds?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete all rounds", role: .destructive) {
                    for round in rounds { context.delete(round) }
                }
            } message: {
                Text("This can't be undone.")
            }
        }
    }
}


/// Shows the typical range for a club: median with one standard deviation either side.
struct ClubRangeBar: View {
    let item: ClubDistance
    let maxYards: Double

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let low = max(0, (item.median - item.spread) / maxYards * w)
            let high = min(w, (item.median + item.spread) / maxYards * w)
            let mid = item.median / maxYards * w
            ZStack(alignment: .leading) {
                Capsule().fill(Color.tgLine).frame(height: 2)
                Capsule().fill(Color.tgData.opacity(0.5)).frame(width: max(2, high - low), height: 8).offset(x: low)
                Rectangle().fill(Color.primary).frame(width: 2, height: 14).offset(x: mid - 1)
            }
            .frame(maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }
}

struct ClubListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Club.sortOrder) private var clubs: [Club]
    @State private var newName = ""

    var body: some View {
        List {
            Section {
                ForEach(clubs) { club in
                    Toggle(club.name, isOn: Binding(get: { club.inBag }, set: { club.inBag = $0 }))
                }
                .onDelete { offsets in
                    for i in offsets { context.delete(clubs[i]) }
                }
            } footer: {
                Text("Clubs switched on show up when you mark a shot.")
            }
            Section("Add a club") {
                HStack {
                    TextField("e.g. 2i or 60", text: $newName)
                    Button("Add") {
                        let name = newName.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        context.insert(Club(name: name, sortOrder: (clubs.map(\.sortOrder).max() ?? 0) + 1))
                        newName = ""
                    }
                }
            }
        }
        .navigationTitle("Clubs")
        .onAppear { Club.ensureDefaults(in: context) }
    }
}
