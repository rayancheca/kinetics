import SwiftUI

// MARK: - Kinetics Design Tokens

extension Color {

    // MARK: Brand Palette

    /// Main app background: #0D0D0D — near-black to keep camera feed as focal point.
    static let kineticsBackground = Color(red: 0.051, green: 0.051, blue: 0.051)

    /// Electric blue accent for skeleton overlays and active UI states: #00C2FF.
    static let kineticsBlue = Color(red: 0.0, green: 0.761, blue: 1.0)

    /// Neon green for real-time metrics badges: #39FF14.
    static let kineticsGreen = Color(red: 0.224, green: 1.0, blue: 0.078)

    /// Primary card background: #131313 — slightly lifted from the app background.
    static let kineticsDark = Color(red: 0.075, green: 0.075, blue: 0.075)

    /// Secondary surface (sheet backgrounds, grouped rows): #1C1C1E.
    static let kineticsMidGray = Color(red: 0.11, green: 0.11, blue: 0.118)

    /// Warning and alert color (postural breakdown alerts, asymmetry flags): #FF4444.
    static let kineticsRed = Color(red: 1.0, green: 0.267, blue: 0.267)

    /// Grappling module accent: #FF8C00.
    static let kineticsOrange = Color(red: 1.0, green: 0.549, blue: 0.0)

    // MARK: Module Colors

    /// Returns the accent color assigned to the given sport module.
    ///
    /// - Iron Tracker → `kineticsBlue`
    /// - Striking Clinic → `kineticsRed`
    /// - Grappling Lab → `kineticsOrange`
    /// - Wall Beta → `kineticsGreen`
    static func moduleColor(for sport: SportType) -> Color {
        switch sport {
        case .striking:    return kineticsRed
        case .grappling:   return kineticsOrange
        case .ironTracker: return kineticsBlue
        case .wallBeta:    return kineticsGreen
        }
    }
}

// MARK: - Hex Color Initializer

extension Color {
    /// Creates a `Color` from a CSS-style hex string.
    ///
    /// Supports 3-digit (`#RGB`), 6-digit (`#RRGGBB`), and 8-digit (`#AARRGGBB`) formats.
    /// The leading `#` is optional.
    ///
    /// ```swift
    /// Color(hex: "#00C2FF")  // Electric blue
    /// Color(hex: "39FF14")   // Neon green (no #)
    /// Color(hex: "#80FF0000") // 50% transparent red
    /// ```
    init(hex: String) {
        // Strip leading # and any whitespace.
        let stripped = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var hexValue: UInt64 = 0
        Scanner(string: stripped).scanHexInt64(&hexValue)

        let alpha: UInt64
        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch stripped.count {
        case 3:
            // Expand shorthand: #RGB → #RRGGBB
            alpha = 255
            red   = (hexValue >> 8) * 17
            green = (hexValue >> 4 & 0xF) * 17
            blue  = (hexValue & 0xF) * 17
        case 6:
            alpha = 255
            red   = hexValue >> 16
            green = hexValue >> 8 & 0xFF
            blue  = hexValue & 0xFF
        case 8:
            // AARRGGBB
            alpha = hexValue >> 24
            red   = hexValue >> 16 & 0xFF
            green = hexValue >> 8 & 0xFF
            blue  = hexValue & 0xFF
        default:
            // Unrecognized format — fall back to opaque black.
            alpha = 255
            red   = 0
            green = 0
            blue  = 0
        }

        self.init(
            .sRGB,
            red: Double(red) / 255.0,
            green: Double(green) / 255.0,
            blue: Double(blue) / 255.0,
            opacity: Double(alpha) / 255.0
        )
    }
}
