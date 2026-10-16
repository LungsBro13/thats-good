import Foundation
import Supabase

private struct CatalogRequest: Encodable, Sendable {
    var query: String?
    var id: Int?
}

private struct CatalogResponse: Decodable, Sendable {
    var courses: [CatalogCourse]
}

private struct FunctionError: Decodable { var error: String }

private struct CourseMapDTO: Codable, Sendable {
    var key: String
    var geo: CourseGeo
}

extension SupabaseAPI {
    fileprivate func catalog(_ request: CatalogRequest) async throws -> [CatalogCourse] {
        do {
            let response: CatalogResponse = try await client.functions.invoke(
                "course-search", options: FunctionInvokeOptions(body: request))
            return response.courses
        } catch let FunctionsError.httpError(code, data) {
            if let message = try? JSONDecoder().decode(FunctionError.self, from: data).error { throw CatalogError.message(message) }
            throw code == 404 ? CatalogError.notSetUp : CatalogError.message("Course search failed (code \(code)).")
        }
    }

    func courseMap(_ key: String) async throws -> CourseGeo? {
        let rows: [CourseMapDTO] = try await client.from("course_maps").select().eq("key", value: key).limit(1).execute().value
        return rows.first?.geo
    }

    func saveCourseMap(_ key: String, _ geo: CourseGeo) async throws {
        try await client.from("course_maps").upsert(CourseMapDTO(key: key, geo: geo)).execute()
    }
}

enum CatalogError: LocalizedError {
    case notSignedIn, notSetUp, message(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in on the Friends tab to search the course database."
        case .notSetUp: return "Course search isn't set up on the server yet (the course-search function)."
        case .message(let text): return text
        }
    }
}

extension Backend {
    private func signedInAPI() throws -> SupabaseAPI {
        guard status == .signedIn, let api else { throw CatalogError.notSignedIn }
        return api
    }

    func searchCourses(_ query: String) async throws -> [CatalogCourse] {
        try await signedInAPI().catalog(CatalogRequest(query: query))
    }

    func catalogCourse(_ id: Int) async throws -> CatalogCourse? {
        try await signedInAPI().catalog(CatalogRequest(id: id)).first
    }

    /// A shared map for this course, if anyone has saved one. Nil when offline or not signed in.
    func sharedMap(_ key: String) async -> CourseGeo? {
        guard let api = try? signedInAPI() else { return nil }
        return try? await api.courseMap(key)
    }

    /// Shares a course map so the next player gets it straight away. Quietly does nothing when offline.
    func shareMap(_ key: String, _ geo: CourseGeo) async {
        guard let api = try? signedInAPI(), !geo.holes.isEmpty || !geo.features.isEmpty else { return }
        try? await api.saveCourseMap(key, geo)
    }
}
