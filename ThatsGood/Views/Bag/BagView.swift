import SwiftUI
import SwiftData

struct BagView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Course.name) private var courses: [Course]
    @Query private var rounds: [Round]

    @State private var editingCourse: Course?
    @State private var addingCourse = false
    @State private var confirmDelete = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Clubs and stock yardages arrive in Phase 2. They'll be worked out from the shots you mark in Detailed mode.")
                        .font(.subheadline)
                        .foregroundStyle(Color.tgMuted)
                } header: {
                    Text("Clubs")
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
