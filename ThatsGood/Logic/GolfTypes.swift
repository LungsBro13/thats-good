import Foundation

// Plain value types shared by the app and the logic tests.
// Nothing in Logic/ may import SwiftUI or SwiftData, so it can be tested on its own.

enum FairwayResult: String, CaseIterable, Codable, Identifiable {
    case left, hit, right

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum GreenResult: String, CaseIterable, Codable, Identifiable {
    case hit, left, right, short, long

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// One hole as printed on the scorecard for a set of tees.
struct CourseHole: Codable, Hashable, Identifiable {
    var number: Int
    var par: Int
    var strokeIndex: Int
    var yards: Int  // 0 = not entered

    var id: Int { number }
}

/// One played hole, ready for calculations.
struct HoleData {
    var par: Int
    var strokeIndex: Int
    var strokes: Int
    var putts: Int
    var firstPuttFeet: Int?
    var fairway: FairwayResult?  // nil on par 3s or when not recorded
    var green: GreenResult?
    var upAndDown: Bool?         // nil when the green was hit
    var penalties: Int
    var shots: [ShotData] = []   // Detailed mode only; empty in Quick mode
}

/// One played round, ready for calculations.
struct RoundData {
    var date: Date
    var courseRating: Double
    var slope: Int
    var handicapIndex: Double?  // the player's index when the round started
    var holes: [HoleData]

    var par: Int { holes.reduce(0) { $0 + $1.par } }
    var strokes: Int { holes.reduce(0) { $0 + $1.strokes } }
    var toPar: Int { strokes - par }
}
