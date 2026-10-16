import Foundation

enum ServerURL {
    /// Turns whatever the player pasted into a Supabase project URL like https://abcd.supabase.co.
    /// Accepts the real project URL, a dashboard link (supabase.com/dashboard/project/abcd/...),
    /// or a URL with extra paths such as /rest/v1.
    static func normalize(_ raw: String) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let range = text.range(of: "supabase.com/dashboard/project/") {
            let ref = text[range.upperBound...].prefix { $0.isLetter || $0.isNumber }
            guard ref.count >= 10 else { return nil }
            return URL(string: "https://\(ref.lowercased()).supabase.co")
        }

        let withScheme = text.contains("://") ? text : "https://" + text
        guard var parts = URLComponents(string: withScheme), let host = parts.host, host.contains(".") else { return nil }
        if host == "supabase.com" || host.hasSuffix(".supabase.com") { return nil }  // the website, not a project
        parts.scheme = "https"
        parts.path = ""
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }
}
