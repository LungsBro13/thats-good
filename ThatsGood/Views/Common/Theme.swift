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

    static let tgBackground = Color(light: 0xF6F7F6, dark: 0x0A0B0B)
    static let tgSurface = Color(light: 0xFFFFFF, dark: 0x131515)
    static let tgLine = Color(light: 0xDDE1DF, dark: 0x262A29)
    static let tgMuted = Color(light: 0x5F6764, dark: 0x8E9693)
    static let tgAccent = Color(light: 0x3F7F22, dark: 0x9BDA6E)
    static let tgLoss = Color(light: 0xB8571F, dark: 0xF0915A)
    static let tgData = Color(light: 0x2F6FA8, dark: 0x6FA8DC)
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

func scoreColor(_ toPar: Int) -> Color {
    toPar < 0 ? .tgAccent : (toPar > 0 ? .tgLoss : .primary)
}
