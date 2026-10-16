import Foundation

enum ShotLie: String, Codable, CaseIterable, Identifiable {
    case tee, fairway, rough, sand, recovery, green

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FeatureKind: String, Codable {
    case green, tee, fairway, bunker, water
}

struct MapFeature: Codable, Hashable {
    var kind: FeatureKind
    var points: [GeoPoint]
}

struct HoleGeo: Codable, Hashable {
    var number: Int
    var par: Int?
    var tee: GeoPoint?
    var greenCenter: GeoPoint
    var greenOutline: [GeoPoint]
}

/// Map data for a course: one entry per hole plus every mapped area (greens, bunkers, water...).
struct CourseGeo: Codable {
    var holes: [HoleGeo] = []
    var features: [MapFeature] = []

    func hole(_ number: Int) -> HoleGeo? {
        holes.first { $0.number == number }
    }

    var summary: String {
        let greens = features.filter { $0.kind == .green }.count
        if holes.isEmpty && greens == 0 { return "No map data" }
        return "\(holes.count) hole\(holes.count == 1 ? "" : "s") and \(greens) green\(greens == 1 ? "" : "s") mapped"
    }

    /// Sets a hole's green. Snaps to a mapped green if the tap was inside one.
    mutating func setGreen(hole number: Int, at point: GeoPoint) {
        let polygon = features.first { $0.kind == .green && Geo.contains($0.points, point) }?.points ?? []
        let center = Geo.centroid(polygon) ?? point
        if let i = holes.firstIndex(where: { $0.number == number }) {
            holes[i].greenCenter = center
            holes[i].greenOutline = polygon
        } else {
            holes.append(HoleGeo(number: number, par: nil, tee: nil, greenCenter: center, greenOutline: polygon))
            holes.sort { $0.number < $1.number }
        }
    }

    /// Best guess at the lie from mapped areas. Nil when the course has no areas mapped.
    func lie(at point: GeoPoint) -> ShotLie? {
        guard !features.isEmpty else { return nil }
        func inside(_ kind: FeatureKind) -> Bool {
            features.contains { $0.kind == kind && Geo.contains($0.points, point) }
        }
        if inside(.green) { return .green }
        if inside(.bunker) { return .sand }
        if inside(.tee) { return .tee }
        if inside(.fairway) { return .fairway }
        if inside(.water) { return .recovery }
        return .rough
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(_ data: Data?) -> CourseGeo? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(CourseGeo.self, from: data)
    }
}

/// Reads golf course data from the OpenStreetMap Overpass API.
enum OSMParser {
    static func query(around p: GeoPoint, radius: Int) -> String {
        let area = "(around:\(radius),\(p.lat),\(p.lon))"
        return """
        [out:json][timeout:25];
        (
          way["golf"~"^(green|tee|fairway|bunker|hole|water_hazard|lateral_water_hazard)$"]\(area);
          way["natural"="water"]\(area);
        );
        out geom;
        """
    }

    private struct Response: Decodable {
        let elements: [Element]
    }

    private struct Element: Decodable {
        let type: String
        let tags: [String: String]?
        let geometry: [LatLon]?
    }

    private struct LatLon: Decodable {
        let lat: Double
        let lon: Double
    }

    static func parse(_ data: Data) throws -> CourseGeo {
        let response = try JSONDecoder().decode(Response.self, from: data)
        var geo = CourseGeo()
        var lines: [(number: Int, par: Int?, points: [GeoPoint])] = []

        for element in response.elements where element.type == "way" {
            let tags = element.tags ?? [:]
            let points = (element.geometry ?? []).map { GeoPoint(lat: $0.lat, lon: $0.lon) }
            guard points.count >= 2 else { continue }

            if tags["golf"] == "hole" {
                if let ref = tags["ref"], let number = Int(ref.prefix { $0.isNumber }) {
                    lines.append((number, tags["par"].flatMap(Int.init), points))
                }
                continue
            }

            let kind: FeatureKind?
            switch tags["golf"] {
            case "green": kind = .green
            case "tee": kind = .tee
            case "fairway": kind = .fairway
            case "bunker": kind = .bunker
            case "water_hazard", "lateral_water_hazard": kind = .water
            default: kind = tags["natural"] == "water" ? .water : nil
            }
            if let kind, points.count >= 3 {
                geo.features.append(MapFeature(kind: kind, points: points))
            }
        }

        let greens = geo.features.filter { $0.kind == .green }
        for line in lines.sorted(by: { $0.number < $1.number }) {
            guard !geo.holes.contains(where: { $0.number == line.number }),
                  let start = line.points.first, let end = line.points.last else { continue }
            let nearest = greens
                .compactMap { green -> (MapFeature, Double)? in
                    guard let c = Geo.centroid(green.points) else { return nil }
                    return (green, Geo.meters(c, end))
                }
                .min { $0.1 < $1.1 }
            let green = (nearest?.1 ?? .infinity) < 100 ? nearest?.0 : nil
            geo.holes.append(HoleGeo(
                number: line.number,
                par: line.par,
                tee: start,
                greenCenter: green.flatMap { Geo.centroid($0.points) } ?? end,
                greenOutline: green?.points ?? []
            ))
        }
        return geo
    }
}
