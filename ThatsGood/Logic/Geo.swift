import Foundation

struct GeoPoint: Codable, Hashable {
    var lat: Double
    var lon: Double
}

/// Distances on the course. Good to a yard or so over golf distances.
enum Geo {
    static let earthRadius = 6_371_000.0
    static let yardsPerMeter = 1.0936133

    static func meters(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadius * asin(min(1, sqrt(h)))
    }

    static func yards(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        meters(a, b) * yardsPerMeter
    }

    /// Compass bearing from a to b, 0 to 360 degrees.
    static func bearing(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let lat1 = a.lat * .pi / 180, lat2 = b.lat * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The point a given distance away on a bearing.
    static func offset(_ p: GeoPoint, bearing: Double, meters distance: Double) -> GeoPoint {
        let d = distance / earthRadius
        let b = bearing * .pi / 180
        let lat1 = p.lat * .pi / 180, lon1 = p.lon * .pi / 180
        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(b))
        let lon2 = lon1 + atan2(sin(b) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))
        return GeoPoint(lat: lat2 * 180 / .pi, lon: lon2 * 180 / .pi)
    }

    static func centroid(_ points: [GeoPoint]) -> GeoPoint? {
        guard !points.isEmpty else { return nil }
        let n = Double(points.count)
        return GeoPoint(lat: points.reduce(0) { $0 + $1.lat } / n, lon: points.reduce(0) { $0 + $1.lon } / n)
    }

    /// Ray casting. Fine at golf-course scale.
    static func contains(_ polygon: [GeoPoint], _ p: GeoPoint) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let a = polygon[i], b = polygon[j]
            if (a.lat > p.lat) != (b.lat > p.lat),
               p.lon < (b.lon - a.lon) * (p.lat - a.lat) / (b.lat - a.lat) + a.lon {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    /// Yards to the front, middle and back of the green, measured along the line from the player to the middle.
    static func frontMiddleBack(from player: GeoPoint, greenCenter: GeoPoint, outline: [GeoPoint])
        -> (front: Double?, middle: Double, back: Double?) {
        let middle = yards(player, greenCenter)
        guard outline.count >= 3 else { return (nil, middle, nil) }
        let axis = bearing(player, greenCenter)
        let along = outline.map { p -> Double in
            let angle = (bearing(player, p) - axis) * .pi / 180
            return yards(player, p) * cos(angle)
        }
        return (along.min(), middle, along.max())
    }
}
