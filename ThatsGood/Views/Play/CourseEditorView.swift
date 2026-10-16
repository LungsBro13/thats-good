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
    @State private var catalogID: Int?
    @State private var center: GeoPoint?
    @State private var query = ""
    @State private var results: [CatalogCourse] = []
    @State private var chosen: CatalogCourse?
    @State private var searching = false
    @State private var searchMessage: String?
    @State private var strokeIndexGuessed = false

    init(course: Course? = nil) {
        self.course = course
        _name = State(initialValue: course?.name ?? "")
        _teeName = State(initialValue: course?.teeName ?? "White")
        _rating = State(initialValue: course?.courseRating ?? 72.0)
        _slope = State(initialValue: course?.slope ?? 113)
        _holes = State(initialValue: course?.holes.sorted { $0.number < $1.number }
                       ?? (1...18).map { CourseHole(number: $0, par: 4, strokeIndex: $0, yards: 0) })
        _geoData = State(initialValue: course?.geoData)
        _catalogID = State(initialValue: course?.catalogID)
        _center = State(initialValue: course.flatMap { c in c.centerLat.flatMap { lat in c.centerLon.map { GeoPoint(lat: lat, lon: $0) } } })
    }

    private var totalPar: Int { holes.reduce(0) { $0 + $1.par } }
    private var strokeIndexesValid: Bool { Set(holes.map(\.strokeIndex)) == Set(1...holes.count) }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && strokeIndexesValid && slope >= 55 && slope <= 155
    }

    var body: some View {
        NavigationStack {
            Form {
                searchSection

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
                        Button(catalogID != nil ? "Load course map" : "Find map by course name") { Task { await findMap(useLocation: false) } }
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
                    Text(!strokeIndexesValid ? "Each stroke index from 1 to \(holes.count) must be used once."
                         : strokeIndexGuessed ? "The database had no stroke indexes for these tees, so they're a guess. Check them against the scorecard."
                         : "Copy par, stroke index (SI) and yards from the scorecard.")
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
            course.catalogID = catalogID
            course.centerLat = center?.lat
            course.centerLon = center?.lon
        } else {
            let newCourse = Course(name: cleanName, teeName: teeName, courseRating: rating, slope: slope, holes: holes)
            newCourse.geoData = geoData
            newCourse.catalogID = catalogID
            newCourse.centerLat = center?.lat
            newCourse.centerLon = center?.lon
            context.insert(newCourse)
        }
        dismiss()
    }

    private func findMap(useLocation: Bool) async {
        loadingMap = true
        mapStatus = nil
        defer { loadingMap = false }
        do {
            // A course from the catalog: use the shared map if someone has saved one.
            if !useLocation, let id = catalogID, let shared = await Backend.shared.sharedMap("gc:\(id)") {
                geoData = shared.encoded()
                mapStatus = "Shared map found: \(shared.summary). Saved when you tap Save."
                return
            }
            let center: GeoPoint
            if !useLocation, let known = self.center {
                center = known
            } else if useLocation {
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
            if let id = catalogID { await Backend.shared.shareMap("gc:\(id)", geo) }
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

extension CourseEditorView {
    @ViewBuilder
    var searchSection: some View {
        Section {
            HStack {
                TextField("Course name, e.g. Chisholm", text: $query)
                    .submitLabel(.search)
                    .onSubmit { Task { await search() } }
                    .autocorrectionDisabled()
                if searching {
                    ProgressView()
                } else {
                    Button("Search") { Task { await search() } }
                        .disabled(query.trimmingCharacters(in: .whitespaces).count < 3)
                }
            }
            if let searchMessage {
                Text(searchMessage).font(.footnote).foregroundStyle(Color.tgMuted)
            }
            if let chosen {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chosen.displayName).font(.body.weight(.semibold))
                    if !chosen.place.isEmpty { Text(chosen.place).font(.caption).foregroundStyle(Color.tgMuted) }
                }
                if chosen.playableTees.isEmpty {
                    Text("No tees with a course rating in the database. Fill in the scorecard below.")
                        .font(.footnote)
                        .foregroundStyle(Color.tgMuted)
                }
                ForEach(chosen.playableTees, id: \.self) { tee in
                    Button { apply(chosen, tee) } label: {
                        HStack {
                            Text(tee.label).foregroundStyle(Color.primary)
                            Spacer()
                            Text(tee.detail).font(.caption).foregroundStyle(Color.tgMuted).monospacedDigit()
                            if catalogID == chosen.id && teeName == tee.label {
                                Image(systemName: "checkmark").foregroundStyle(Color.tgAccent)
                            }
                        }
                    }
                }
                Button("Back to results") { self.chosen = nil }
                    .font(.footnote)
            } else {
                ForEach(results) { course in
                    Button { pick(course) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(course.displayName).font(.body.weight(.semibold)).foregroundStyle(Color.primary)
                            Text([course.place, "\(course.playableTees.count) tees"].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(Color.tgMuted)
                        }
                    }
                }
            }
        } header: {
            Text("Find your course")
        } footer: {
            Text("Fills in course rating, slope, par, stroke index and yards for your tees, and loads the map. Or fill it in yourself below.")
        }
        #if DEBUG
        .onAppear {
            // CI screenshot: sample results, no server needed.
            if ProcessInfo.processInfo.arguments.contains("-catalogDemo"), results.isEmpty {
                let tees = [("Blue", "male", 69.7, 118, 6100), ("White", "male", 68.4, 114, 5720), ("Red", "female", 70.9, 121, 5210)]
                let demo = CatalogCourse(id: 1, club: "Demo Links", course: "Demo Links", city: "Dunedin", country: "New Zealand",
                                         lat: -45.9, lon: 170.5,
                                         tees: tees.map { CatalogTee(name: $0.0, gender: $0.1, rating: $0.2, slope: $0.3, par: 70, yards: $0.4,
                                                                    holes: []) })
                query = "demo links"
                results = [demo, CatalogCourse(id: 2, club: "Demo Golf Club", course: "Hill Course", city: "Auckland",
                                               country: "New Zealand", tees: [])]
                chosen = demo
            }
        }
        #endif
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 3 else { return }
        searching = true
        searchMessage = nil
        chosen = nil
        defer { searching = false }
        do {
            results = try await Backend.shared.searchCourses(text)
            if results.isEmpty { searchMessage = "No courses found. Try part of the club name, or fill it in below." }
        } catch {
            results = []
            searchMessage = error.localizedDescription
        }
    }

    private func pick(_ course: CatalogCourse) {
        chosen = course
        if course.playableTees.count == 1, let tee = course.playableTees.first { apply(course, tee) }
    }

    private func apply(_ course: CatalogCourse, _ tee: CatalogTee) {
        name = course.displayName
        teeName = tee.label
        if let r = tee.rating { rating = r }
        if let s = tee.slope { slope = s }
        let card = CourseCatalog.holes(for: tee)
        holes = card.holes
        strokeIndexGuessed = card.strokeIndexGuessed
        let newCourse = catalogID != course.id
        catalogID = course.id
        center = course.center
        if newCourse || geoData == nil { Task { await findMap(useLocation: false) } }
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
