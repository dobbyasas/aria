import SwiftUI

extension Color {
    init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: trimmed).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch trimmed.count {
        case 3:
            red = (value >> 8) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
        default:
            red = value >> 16
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        }

        self.init(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }

    static let ariaBackground = Color(hex: "#111316")
    static let ariaSurface = Color(hex: "#1A1D21")
    static let ariaSurfaceRaised = Color(hex: "#24282E")
    static let ariaTextPrimary = Color(hex: "#F7F2E9")
    static let ariaTextSecondary = Color(hex: "#AAA7A0")
    static let ariaAccent = Color(hex: "#45D6C7")
    static let ariaWarm = Color(hex: "#F28482")
}

extension ShapeStyle where Self == Color {
    static var ariaBackground: Color { Color.ariaBackground }
    static var ariaSurface: Color { Color.ariaSurface }
    static var ariaSurfaceRaised: Color { Color.ariaSurfaceRaised }
    static var ariaTextPrimary: Color { Color.ariaTextPrimary }
    static var ariaTextSecondary: Color { Color.ariaTextSecondary }
    static var ariaAccent: Color { Color.ariaAccent }
    static var ariaWarm: Color { Color.ariaWarm }
}
