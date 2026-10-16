import Foundation

/// A score from another app or a national handicap system: the total that counted for handicap, plus the
/// hole-by-hole card when there is one.
struct ImportedRound: Equatable {
    var date: Date
    var courseName: String
    var teeName: String
    var adjustedGross: Int
    var courseRating: Double
    var slope: Int
    var pcc: Int = 0                // playing conditions calculation for the day
    var holeStrokes: [Int] = []     // optional gross score per hole
    var holePars: [Int] = []

    /// WHS score differential: 113 ÷ slope × (adjusted gross − course rating − PCC), to one decimal.
    var differential: Double? {
        guard slope > 0 else { return nil }
        let raw = 113.0 / Double(slope) * (Double(adjustedGross) - courseRating - Double(pcc))
        return (raw * 10).rounded() / 10
    }
}

extension Handicap {
    /// Index after each score, oldest first, from app rounds and imported scores together.
    static func history(_ rounds: [RoundData], imported: [ImportedRound]) -> [IndexPoint] {
        let scores = rounds.compactMap { r in scoreDifferential(r).map { (r.date, $0) } }
            + imported.compactMap { r in r.differential.map { (r.date, $0) } }
        var differentials: [Double] = []
        var points: [IndexPoint] = []
        for (date, differential) in scores.sorted(by: { $0.0 < $1.0 }) {
            differentials.insert(differential, at: 0)
            if let value = index(fromDifferentials: differentials) { points.append(IndexPoint(date: date, index: value)) }
        }
        return points
    }

    static func currentIndex(_ rounds: [RoundData], imported: [ImportedRound]) -> Double? {
        history(rounds, imported: imported).last?.index
    }
}

/// Reads scores from CSV or tab-separated text (pasted from a spreadsheet).
/// Needs a header row. Columns can be in any order:
/// date, course, tee, adj_gross (or score), course_rating (or rating), slope, pcc, holes, pars.
/// Dates are day/month/year or year-month-day. Holes and pars are numbers separated by spaces.
enum ScoreImport {
    struct Result {
        var rounds: [ImportedRound]
        var problems: [String]
    }

    static func parse(_ text: String) -> Result {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let headerLine = lines.first else { return Result(rounds: [], problems: ["Nothing to import."]) }
        let separator: Character = headerLine.contains("\t") ? "\t" : ","
        let header = fields(headerLine, separator).map(normalise)

        func column(_ names: String...) -> Int? { header.firstIndex { names.contains($0) } }
        guard let dateCol = column("date", "played"),
              let scoreCol = column("adjgross", "adjustedgross", "score", "gross", "ags"),
              let ratingCol = column("courserating", "rating", "cr"),
              let slopeCol = column("slope", "sloperating") else {
            return Result(rounds: [], problems: ["The first row needs column names: date, course, tee, adj_gross, course_rating, slope."])
        }
        let courseCol = column("course", "coursename", "club")
        let teeCol = column("tee", "teemarker", "tees")
        let pccCol = column("pcc")
        let holesCol = column("holes", "holescores", "card")
        let parsCol = column("pars", "holepars")

        var rounds: [ImportedRound] = []
        var problems: [String] = []
        for (n, line) in lines.dropFirst().enumerated() {
            let f = fields(line, separator)
            func value(_ i: Int?) -> String { i.flatMap { $0 < f.count ? f[$0] : nil } ?? "" }
            let row = n + 2
            guard let date = parseDate(value(dateCol)) else { problems.append("Row \(row): can't read the date \"\(value(dateCol))\"."); continue }
            guard let score = Int(value(scoreCol)), (40...200).contains(score) else { problems.append("Row \(row): score missing."); continue }
            guard let rating = Double(value(ratingCol)), (50...85).contains(rating) else { problems.append("Row \(row): course rating missing."); continue }
            guard let slope = Int(value(slopeCol)), (55...155).contains(slope) else { problems.append("Row \(row): slope missing."); continue }
            var round = ImportedRound(date: date, courseName: value(courseCol).isEmpty ? "Imported" : value(courseCol),
                                      teeName: value(teeCol), adjustedGross: score, courseRating: rating, slope: slope,
                                      pcc: Int(value(pccCol)) ?? 0)
            round.holeStrokes = numbers(value(holesCol))
            round.holePars = numbers(value(parsCol))
            if !round.holeStrokes.isEmpty && round.holeStrokes.count != 9 && round.holeStrokes.count != 18 {
                problems.append("Row \(row): the hole scores need 9 or 18 numbers, so they were left out.")
                round.holeStrokes = []
            }
            if round.holePars.count != round.holeStrokes.count { round.holePars = [] }
            rounds.append(round)
        }
        return Result(rounds: rounds, problems: problems)
    }

    /// Splits one line, allowing "quoted, fields".
    static func fields(_ line: String, _ separator: Character) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        for ch in line {
            if ch == "\"" { quoted.toggle() } else if ch == separator && !quoted {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        out.append(current.trimmingCharacters(in: .whitespaces))
        return out
    }

    static func normalise(_ name: String) -> String {
        name.lowercased().filter { $0.isLetter }
    }

    static func numbers(_ text: String) -> [Int] {
        text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    /// 08/10/2026 (day first, as in New Zealand, the UK and Australia) or 2026-10-08.
    static func parseDate(_ text: String) -> Date? {
        let parts = text.split(whereSeparator: { $0 == "/" || $0 == "-" || $0 == "." }).compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let (d, m, y) = parts[0] > 31 ? (parts[2], parts[1], parts[0]) : (parts[0], parts[1], parts[2] < 100 ? 2000 + parts[2] : parts[2])
        guard (1...12).contains(m), (1...31).contains(d), (1950...2100).contains(y) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        let cal = Calendar(identifier: .gregorian)
        // Reject dates that don't exist, like 31/02, instead of rolling them into the next month.
        guard let date = cal.date(from: c), cal.component(.day, from: date) == d else { return nil }
        return date
    }

    /// Leaves out scores already imported (same day, course and score).
    static func newOnly(_ incoming: [ImportedRound], existing: [ImportedRound]) -> [ImportedRound] {
        let cal = Calendar(identifier: .gregorian)
        func key(_ r: ImportedRound) -> String {
            let d = cal.dateComponents([.year, .month, .day], from: r.date)
            return "\(d.year ?? 0)-\(d.month ?? 0)-\(d.day ?? 0)|\(r.courseName.lowercased())|\(r.adjustedGross)"
        }
        var seen = Set(existing.map(key))
        return incoming.filter { seen.insert(key($0)).inserted }
    }
}
