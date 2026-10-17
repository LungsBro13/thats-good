import SwiftUI
import UIKit

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// A colour that switches with the phone's light or dark setting.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(Color(hex: traits.userInterfaceStyle == .dark ? dark : light))
        })
    }

    // A golf course: rough, fairway, green and fringe, and bunker sand. See design/brand/README.md.
    static let tgBackground = Color(light: 0xF3F6F2, dark: 0x0E2A1F)
    static let tgSurface = Color(light: 0xFFFFFF, dark: 0x133524)
    static let tgLine = Color(light: 0xE3EADF, dark: 0x24503A)
    static let tgMuted = Color(light: 0x4E6457, dark: 0xA9C9B4)
    static let tgAccent = Color(light: 0x2E7F30, dark: 0x6DBE55)  // green text and highlights
    static let tgLoss = Color(light: 0x9C6B2E, dark: 0xE9D6A5)    // wet sand
    static let tgData = Color(light: 0x1F4A33, dark: 0xA9D59A)

    static let tgRough = Color(hex: 0x0E2A1F)
    static let tgRoughStripe = Color(hex: 0x133524)
    static let tgRoughText = Color(hex: 0x1F4A33)
    static let tgFairway = Color(hex: 0x3A9D3C)
    static let tgFairwayStripe = Color(hex: 0x44A846)
    static let tgFairwayDeep = Color(hex: 0x23692A)
    static let tgGreen = Color(hex: 0xDDF1C9)
    static let tgGreenStripe = Color(hex: 0xD2EBBC)
    static let tgFringe = Color(hex: 0xC8E6B0)
    static let tgPale = Color(hex: 0xA9D59A)
    static let tgSand = Color(hex: 0xE9D6A5)
    static let tgSandLight = Color(hex: 0xF1E4C3)
    static let tgSandDeep = Color(hex: 0xB88B4A)
    static let tgSandText = Color(hex: 0x5C4320)
}

func formatToPar(_ value: Int) -> String {
    if value == 0 { return "E" }
    return value > 0 ? "+\(value)" : "−\(-value)"
}

func formatPercent(_ value: Double?) -> String {
    guard let value else { return "–" }
    return "\(Int((value * 100).rounded()))%"
}

func formatDecimal(_ value: Double?, digits: Int = 1) -> String {
    guard let value else { return "–" }
    return value.formatted(.number.precision(.fractionLength(digits)))
}

/// "THAT'S GOOD" in the serif title face, spaced out like the logo.
struct Wordmark: View {
    var size: CGFloat = 22
    var color: Color = .tgRough

    var body: some View {
        Text("THAT’S GOOD")
            .font(.system(size: size, weight: .semibold, design: .serif))
            .tracking(size * 0.14)
            .foregroundStyle(color)
            .accessibilityLabel("That's Good")
    }
}

/// The golfer from the logo. Dark for light backgrounds, light for dark ones.
struct Golfer: View {
    enum Style: String { case dark = "GolferDark", light = "GolferLight", onGreen = "GolferOnGreen" }
    var style: Style = .dark
    var height: CGFloat

    var body: some View {
        Image(style.rawValue)
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityHidden(true)
    }
}

/// Vertical mowing stripes, like a freshly cut fairway.
struct MowingStripes: View {
    let base: Color
    let stripe: Color
    var width: CGFloat = 40

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            var x = width
            while x < size.width {
                context.fill(Path(CGRect(x: x, y: 0, width: width, height: size.height)), with: .color(stripe))
                x += width * 2
            }
        }
    }
}

func scoreColor(_ toPar: Int) -> Color {
    toPar < 0 ? .tgAccent : (toPar > 0 ? .tgLoss : .primary)
}
