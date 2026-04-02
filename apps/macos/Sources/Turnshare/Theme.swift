import SwiftUI

/// GitHub Dark color palette — matches the web renderer (docs/index.html).
enum Theme {
    // MARK: - Backgrounds
    static let bg           = Color(hex: 0x0d1117)
    static let bgSurface    = Color(hex: 0x161b22)
    static let bgElevated   = Color(hex: 0x1c2129)

    // MARK: - Borders
    static let border       = Color(hex: 0x30363d)
    static let borderSubtle = Color(hex: 0x21262d)

    // MARK: - Text
    static let text         = Color(hex: 0xe6edf3)
    static let textMuted    = Color(hex: 0x8b949e)
    static let textSubtle   = Color(hex: 0x6e7681)

    // MARK: - Accents
    static let accentBlue   = Color(hex: 0x58a6ff)
    static let accentGreen  = Color(hex: 0x3fb950)
    static let accentOrange = Color(hex: 0xd29922)
    static let accentPurple = Color(hex: 0xbc8cff)
    static let accentRed    = Color(hex: 0xf85149)
    static let accentCyan   = Color(hex: 0x76d9e6)

    // MARK: - Agent badges (background + foreground)
    static let claudeBg     = Color(hex: 0x553518)
    static let claudeText   = Color(hex: 0xf0a050)
    static let codexBg      = Color(hex: 0x1a3a1a)
    static let codexText    = Color(hex: 0x3fb950)
    static let opencodeBg   = Color(hex: 0x1a2a3a)
    static let opencodeText = Color(hex: 0x76d9e6)

    // MARK: - Role indicators (background + foreground)
    static let userBg       = Color(hex: 0x1a2a1a)
    static let userText     = Color(hex: 0x3fb950)
    static let assistantBg  = Color(hex: 0x1a1a2e)
    static let assistantText = Color(hex: 0xbc8cff)
    static let toolBg       = Color(hex: 0x1a2020)
    static let toolText     = Color(hex: 0x76d9e6)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
