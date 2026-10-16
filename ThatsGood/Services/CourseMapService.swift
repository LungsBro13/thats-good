import Foundation
import MapKit

enum CourseMapError: LocalizedError {
    case courseNotFound
    case server(Int)
    case noLocation

    var errorDescription: String? {
        switch self {
        case .courseNotFound: return "Couldn't find that course on the map. Try \"Use my location\" when you're there."
        case .server(let code): return "The map server didn't answer (code \(code)). Try again in a minute."
        case .noLocation: return "Your location isn't available yet. Check location is allowed for That's Good."
        }
    }
}

/// Finds a course and downloads its greens, tees, fairways, bunkers and water from OpenStreetMap.
enum CourseMapService {
    /// The main Overpass server, then a mirror if it's busy.
    static let overpassURLs = [
        URL(string: "https://overpass-api.de/api/interpreter")!,
        URL(string: "https://overpass.kumi.systems/api/interpreter")!,
    ]

    /// Uses Apple Maps search to turn a course name into a position.
    static func locate(courseName: String) async throws -> GeoPoint {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "\(courseName) golf"
        request.resultTypes = .pointOfInterest
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else { throw CourseMapError.courseNotFound }
        return GeoPoint(item.placemark.coordinate)
    }

    static func download(around point: GeoPoint, radius: Int = 1800) async throws -> CourseGeo {
        var lastError: Error = CourseMapError.server(0)
        for url in overpassURLs {
            do {
                return try await download(from: url, around: point, radius: radius)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func download(from url: URL, around point: GeoPoint, radius: Int) async throws -> CourseGeo {
        let query = OSMParser.query(around: point, radius: radius)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("ThatsGood/0.2 (iOS golf app)", forHTTPHeaderField: "User-Agent")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw CourseMapError.server(status) }
        return try OSMParser.parse(data)
    }
}
