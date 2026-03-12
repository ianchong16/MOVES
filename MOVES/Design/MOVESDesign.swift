import SwiftUI

// MARK: - Color Palette
// Brutalist-minimal. SSENSE / Yeezy Supply direction.
// Pure monochrome. No accent color in the UI chrome.
// Accent exists only for tiny functional moments (challenge badge, success states).
// The restraint IS the brand.

extension Color {
    // Foundation — true black, true white
    static let movesBlack = Color(hex: "191919")
    static let movesWhite = Color(hex: "FFFFFF")
    static let movesOffWhite = Color(hex: "F5F5F5")

    // Grays — cold, not warm. Fashion-forward.
    static let movesGray100 = Color(hex: "EBEBEB")
    static let movesGray200 = Color(hex: "D4D4D4")
    static let movesGray300 = Color(hex: "999999")
    static let movesGray400 = Color(hex: "666666")
    static let movesGray500 = Color(hex: "333333")

    // Accent — used VERY sparingly. Only for: challenge badge, success checkmark.
    static let movesAccent = Color(hex: "191919")
    static let movesAccentSoft = Color(hex: "191919").opacity(0.06)

    // Semantic
    static let movesSuccess = Color(hex: "191919")
    static let movesError = Color(hex: "D42020")

    // Adaptive
    static let movesPrimaryBg = Color.movesWhite
    static let movesSecondaryBg = Color.movesOffWhite
    static let movesPrimaryText = Color.movesBlack
    static let movesSecondaryText = Color.movesGray400
    static let movesTertiaryText = Color.movesGray300
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = ((int >> 24) & 0xFF, (int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Typography
// Helvetica Neue / system sans-serif at its leanest.
// Tight, functional, no decoration. Let weight and size do the work.
// Monospaced for metadata. Serif ONLY for the one poetic line per move — the warmth contrast.

struct MOVESTypography {
    // Hero — the MOVES wordmark, the CTA
    static func hero() -> Font {
        .system(size: 48, weight: .bold, design: .default)
    }

    // Large title — screen headers. Thinner than before. Confidence, not shouting.
    static func largeTitle() -> Font {
        .system(size: 28, weight: .medium, design: .default)
    }

    // Title — move titles, section headers
    static func title() -> Font {
        .system(size: 22, weight: .medium, design: .default)
    }

    // Headline — sub-headers
    static func headline() -> Font {
        .system(size: 16, weight: .medium, design: .default)
    }

    // Body — reading text. Light weight. Breathes.
    static func body() -> Font {
        .system(size: 15, weight: .regular, design: .default)
    }

    // Caption — metadata
    static func caption() -> Font {
        .system(size: 12, weight: .regular, design: .default)
    }

    // Mono — distances, times, costs. The utility layer.
    static func mono() -> Font {
        .system(size: 11, weight: .regular, design: .monospaced)
    }

    // Mono small — tags, labels, section headers
    static func monoSmall() -> Font {
        .system(size: 10, weight: .medium, design: .monospaced)
    }

    // Serif — ONLY for the poetic setup line on a move.
    // One serif moment per screen, max. That's the rule.
    static func serif() -> Font {
        .system(size: 15, weight: .regular, design: .serif)
    }

    static func serifLarge() -> Font {
        .system(size: 19, weight: .regular, design: .serif)
    }
}

// MARK: - Spacing
// Even more generous. Let everything breathe. Yeezy-level negative space.

struct MOVESSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 36
    static let xxl: CGFloat = 56
    static let xxxl: CGFloat = 80
    static let huge: CGFloat = 120

    // Screen edges — wider than most apps. That's the point.
    static let screenH: CGFloat = 28
    static let screenV: CGFloat = 20
}

// MARK: - Corner Radius
// Brutal. Square or barely-there. No pill shapes. No soft rounding.
// SSENSE uses 0. Yeezy uses 0. We use 0-2.

struct MOVESRadius {
    static let sm: CGFloat = 0
    static let md: CGFloat = 0
    static let lg: CGFloat = 2
    static let xl: CGFloat = 2
    static let pill: CGFloat = 0  // No pills. Rectangles.
}

// MARK: - Animation
// Restrained. Fast fades, no bounce. Disappear and appear. Like a page turn.

struct MOVESAnimation {
    static let quick: Animation = .easeOut(duration: 0.15)
    static let standard: Animation = .easeInOut(duration: 0.3)
    static let slow: Animation = .easeInOut(duration: 0.45)
    static let spring: Animation = .easeOut(duration: 0.25)
}
