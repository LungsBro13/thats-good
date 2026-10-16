import SwiftUI
import SwiftData

struct CourseEditorView: View {
    let course: Course?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var teeName: String
    @State private var rating: Double
    @State private var slope: Int
    @State private var holes: [CourseHole]
    @State private var geoData: Data?
    @State private var mapStatus: String?
    @State private var loadingMap = false

    init(course: Course? = nil) {
        self.course = course
        _name = State(initialValue: course?.name ?? "")
        _teeName = State(initialValue: course?.teeName ?? "White")
        _rating = State(initialValue: course?.courseRating ?? 72.0)
        _slope = State(initialValue: course?.slope ?? 113)
        _holes = State(initialValue: course?.holes.sorted { $0.number < $1.number }
                       ?? (1...18).map { CourseHole(number: $0, par: 4, strokeIndex: $0, yards: 0) })
        _geoData = State(initialValue: course?.geoData)
    }

    private var totalPar: Int { holes.reduce(0) { $0 + $1.par } }
    private var strokeIndexesValid: Bool { Set(holes.map(\.strokeIndex)) == Set(1...holes.count) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && strokeIndexesValid && slope >= 55 && slope <= 155
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Course") {
                    TextField("Course name", text: $name)
                    TextField("Tees, e.g. White", text: $teeName)
                    LabeledContent("Course rating") {
                        TextField("72.0", value: $rating, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Slope") {
                        TextField("113", value: $slope, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }

                Section {
                    Text(CourseGeo.decode(geoData)?.summary ?? "No map data")
                        .font(.subheadline.weight(.semibold))
                    if let mapStatus {
                        Text(mapStatus).font(.footnote).foregroundStyle(Color.tgMuted)
                    }
                    if loadingMap {
                        ProgressView("Downloading map…")
                    } else {
                        Button("Find map by course name") { Task { await findMap(useLocation: false) } }
                            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Find map at my location") { Task { await findMap(useLocation: true) } }
                    }
                } header: {
                    Text("Map")
                } footer: {
                    Text("Greens, bunkers and water come from OpenStreetMap. If a green is missing you can set it on the hole while you play.")
                }

                Section {
                    HStack {
                        Text("Hole").frame(width: 36, alignment: .leading)
                        Text("Par").frame(maxWidth: .infinity)
                        Text("SI").frame(width: 44)
                        Text("Yards").frame(width: 56)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.tgMuted)

                    ForEach($holes) { $hole in
                        HoleEditRow(hole: $hole)
                    }
                } header: {
                    Text("Holes · par \(totalPar)")
                } footer: {
                    Text(strokeIndexesValid
                         ? "Copy par, stroke index (SI) and yards from the scorecard."
                         : "Each stroke index from 1 to 18 must be used once.")
                }
            }
            .navigationTitle(course == nil ? "New course" : "Edit course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!canSave)
                }
            }
        }
    }

    private func save() {
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        if let course {
            course.name = cleanName
            course.teeName = teeName
            course.courseRating = rating
            course.slope = slope
            course.holes = holes
            course.geoData = geoData
        } else {
            let newCourse = Course(name: cleanName, teeName: teeName, courseRating: rating, slope: slope, holes: holes)
            newCourse.geoData = geoData
            context.insert(newCourse)
        }
        dismiss()
    }

    private func findMap(useLocation: Bool) async {
        loadingMap = true
        mapStatus = nil
        defer { loadingMap = false }
        do {
            let center: GeoPoint
            if useLocation {
                LocationManager.shared.start()
                for _ in 0..<20 where LocationManager.shared.point == nil {
                    try await Task.sleep(nanoseconds: 250_000_000)
                }
                guard let here = LocationManager.shared.point else { throw CourseMapError.noLocation }
                center = here
            } else {
                center = try await CourseMapService.locate(courseName: name)
            }
            let geo = try await CourseMapService.download(around: center)
            geoData = geo.encoded()
            if holes.allSatisfy({ $0.par == 4 }) {
                // A brand new course: copy pars from the map where it has them.
                for i in holes.indices {
                    if let par = geo.hole(holes[i].number)?.par { holes[i].par = par }
                }
            }
            mapStatus = geo.holes.isEmpty
                ? "Found the course area but no numbered holes. You can set each green as you play."
                : "Map saved when you tap Save."
        } catch {
            mapStatus = error.localizedDescription
        }
    }
}

private struct HoleEditRow: View {
    @Binding var hole: CourseHole

    var body: some View {
        HStack {
            Text("\(hole.number)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
                .frame(width: 36, alignment: .leading)
            Picker("Par for hole \(hole.number)", selection: $hole.par) {
                Text("3").tag(3)
                Text("4").tag(4)
                Text("5").tag(5)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            TextField("SI", value: $hole.strokeIndex, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .frame(width: 44)
                .accessibilityLabel("Stroke index for hole \(hole.number)")
            TextField("–", value: $hole.yards, format: .number)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
                .accessibilityLabel("Yards for hole \(hole.number)")
        }
    }
}
