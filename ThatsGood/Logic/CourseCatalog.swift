import Foundation

/// A course from the shared catalog (GolfCourseAPI, tidied by the course-search edge function).
struct CatalogCourse: Codable, Identifiable, Hashable, Sendable {
    var id: String
    var club: String
    var course: String
    var city: String?
    var country: String?
    var lat: Double?
    var lon: Double?
    var tees: [CatalogTee]
    var note: String? = nil  // what the database sent, when no tee could be used

    /// "Chisholm Links", or "Royal Auckland and Grange – Grange/Middlemore" when the club has several courses.
    var displayName: String {
        let c = course.trimmingCharacters(in: .whitespaces), k = club.trimmingCharacters(in: .whitespaces)
        if c.isEmpty || c.caseInsensitiveCompare(k) == .orderedSame { return k.isEmpty ? c : k }
        if k.isEmpty || c.localizedCaseInsensitiveContains(k) { return c }
        return "\(k) – \(c)"
    }

    var place: String { [city, country].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ") }

    var center: GeoPoint? {
        guard let lat, let lon else { return nil }
        return GeoPoint(lat: lat, lon: lon)
    }

    /// Tees that can be played: they have a rating and slope.
    var playableTees: [CatalogTee] { tees.filter { $0.rating != nil && $0.slope != nil } }

    /// Key for the shared course map.
    var mapKey: String { "gc:\(id)" }
}

struct CatalogTee: Codable, Hashable, Sendable {
    var name: String
    var gender: String  // "male" or "female"
    var rating: Double?
    var slope: Int?
    var par: Int?
    var yards: Int?
    var holes: [CatalogHole]

    var label: String { gender == "female" ? "\(name) (women's)" : name }

    var detail: String {
        var parts: [String] = []
        if let rating, let slope { parts.append("\(String(format: "%.1f", rating)) / \(slope)") }
        if let par = par ?? (holes.isEmpty ? nil : holes.reduce(0) { $0 + ($1.par ?? 4) }) { parts.append("par \(par)") }
        if let yards, yards > 0 { parts.append("\(yards) yd") }
        return parts.joined(separator: " · ")
    }
}

struct CatalogHole: Codable, Hashable, Sendable {
    var par: Int?
    var yards: Int?
    var si: Int?
}

enum CourseCatalog {
    /// Scorecard holes for a tee. When the stroke indexes are missing or don't use 1…n once each,
    /// they're replaced by a guess (hardest holes first by length) and `strokeIndexGuessed` is true.
    static func holes(for tee: CatalogTee) -> (holes: [CourseHole], strokeIndexGuessed: Bool) {
        let count = tee.holes.isEmpty ? 18 : tee.holes.count
        var holes = (0..<count).map { i -> CourseHole in
            let h = i < tee.holes.count ? tee.holes[i] : CatalogHole()
            let par = h.par.map { min(6, max(3, $0)) } ?? 4
            return CourseHole(number: i + 1, par: par, strokeIndex: h.si ?? 0, yards: max(0, h.yards ?? 0))
        }
        if Set(holes.map(\.strokeIndex)) == Set(1...count) { return (holes, false) }

        // Guess: longer holes for their par are harder. Odd numbers on the front nine, even on the back, as usual.
        func difficulty(_ h: CourseHole) -> Double { Double(h.yards) / Double(h.par) }
        if count == 18 {
            let front = holes.prefix(9).sorted { difficulty($0) > difficulty($1) }
            let back = holes.suffix(9).sorted { difficulty($0) > difficulty($1) }
            for (rank, h) in front.enumerated() { holes[h.number - 1].strokeIndex = 2 * rank + 1 }
            for (rank, h) in back.enumerated() { holes[h.number - 1].strokeIndex = 2 * rank + 2 }
        } else {
            for (rank, h) in holes.sorted(by: { difficulty($0) > difficulty($1) }).enumerated() { holes[h.number - 1].strokeIndex = rank + 1 }
        }
        return (holes, true)
    }
}
