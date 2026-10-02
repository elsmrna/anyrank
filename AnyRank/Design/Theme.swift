import SwiftUI
import UIKit

/// AnyRank's design tokens. Every color in the app routes through here so
/// the palette is swappable in one place.
///
/// Source palette (earthy, calm):
///   Terracotta  #A3622C — the single accent: primary actions, tint, "Loved"
///   Stone       #DBD8D3 — hairlines, chips, muted fills
///   Taupe       #9B8667 — secondary text, "Fine"
///   Espresso    #4E3413 — ink; the dark-mode canvas is derived from it
///   Olive       #4D5735 — "Liked"
///
/// Light mode reads as warm paper with white cards; dark mode is a deep
/// espresso with lifted, slightly brighter versions of the same hues.
enum Theme {

    // MARK: Surfaces

    /// Screen background — warm paper / deep espresso.
    static let background = Color(light: 0xF5F3EF, dark: 0x17120D)
    /// Card and row surface sitting on `background`.
    static let surface = Color(light: 0xFFFFFF, dark: 0x231C15)
    /// Muted fill for search fields, chips, image placeholders.
    static let surfaceMuted = Color(light: 0xECE9E4, dark: 0x2F271F)
    /// Hairlines and card borders (Stone).
    static let hairline = Color(light: 0xDBD8D3, dark: 0x3A3027)

    // MARK: Ink

    static let textPrimary = Color(light: 0x33251A, dark: 0xF0ECE6)
    static let textSecondary = Color(light: 0x77684F, dark: 0xAB9D88)
    static let textTertiary = Color(light: 0xA6987F, dark: 0x746858)

    // MARK: Brand

    /// Terracotta. Slightly lifted in dark mode so it holds contrast.
    static let accent = Color(light: 0xA3622C, dark: 0xCC8249)
    /// Text/icon color to place on top of `accent`.
    static let onAccent = Color(light: 0xFFFBF6, dark: 0x1B130B)
    static let olive = Color(light: 0x4D5735, dark: 0x9BA673)
    static let taupe = Color(light: 0x9B8667, dark: 0xB5A283)
    static let espresso = Color(light: 0x4E3413, dark: 0xD8C6AB)
    static let danger = Color(light: 0xA8432F, dark: 0xE07A62)

    // MARK: Shape & spacing

    static let cornerRadius: CGFloat = 18
    static let smallCornerRadius: CGFloat = 12
    static let gutter: CGFloat = 20

    // MARK: Motion

    /// Default spring for state changes — quick, lightly damped, never bouncy
    /// enough to feel toy-like.
    static let spring = Animation.snappy(duration: 0.32, extraBounce: 0.04)
    /// Press-down feedback on tappable surfaces.
    static let press = Animation.spring(response: 0.22, dampingFraction: 0.7)
}

// MARK: - Typography

extension Font {
    /// Serif display face (New York) for screen titles and hero text.
    static func display(_ style: Font.TextStyle = .largeTitle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    /// Rounded numerals for scores and counts.
    static func score(_ style: Font.TextStyle = .body, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .rounded, weight: weight).monospacedDigit()
    }
}

// MARK: - Color helpers

extension Color {
    /// Dynamic color from two hex literals, resolved per trait collection.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

// MARK: - Bucket styling

extension Bucket {
    /// Fill color for the bucket — dots, bars, solid chips.
    var color: Color {
        switch self {
        case .loved:     return Color(light: 0xA3622C, dark: 0xD08A52)
        case .liked:     return Color(light: 0x66733F, dark: 0xA0AC74)
        case .fine:      return Color(light: 0xB39C72, dark: 0xC2AE88)
        case .didntLike: return Color(light: 0x5C4128, dark: 0x9C8676)
        }
    }

    /// Higher-contrast variant for text drawn on a `color`-tinted background.
    var ink: Color {
        switch self {
        case .loved:     return Color(light: 0x8A4C1C, dark: 0xE2A273)
        case .liked:     return Color(light: 0x4D5735, dark: 0xB7C28B)
        case .fine:      return Color(light: 0x76603A, dark: 0xD6C4A2)
        case .didntLike: return Color(light: 0x4E3413, dark: 0xC2AE9F)
        }
    }

    /// Secondary, non-color signal so buckets stay distinguishable for
    /// colorblind users.
    var symbolName: String {
        switch self {
        case .loved:     return "heart.fill"
        case .liked:     return "hand.thumbsup.fill"
        case .fine:      return "minus"
        case .didntLike: return "hand.thumbsdown.fill"
        }
    }

    /// One-line explanation shown on the bucket picker.
    var blurb: String {
        switch self {
        case .loved:     return "One of the best"
        case .liked:     return "Would happily go back"
        case .fine:      return "It was okay"
        case .didntLike: return "Not for me"
        }
    }
}

// MARK: - Category styling

extension Category {
    /// Tint for the category's icon tile. Rotates through the palette so the
    /// home screen has some rhythm without introducing new hues.
    var tint: Color {
        switch self {
        case .restaurants, .anime:         return Theme.accent
        case .bars, .games, .manga:        return Theme.olive
        case .movies, .albums, .stays:     return Theme.espresso
        case .books, .custom:              return Theme.taupe
        }
    }

    /// Singular noun, e.g. "Add restaurant".
    var itemNoun: String {
        switch self {
        case .restaurants: return "restaurant"
        case .bars:        return "bar"
        case .stays:       return "stay"
        case .movies:      return "movie"
        case .books:       return "book"
        case .anime:       return "anime"
        case .manga:       return "manga"
        case .games:       return "game"
        case .albums:      return "album"
        case .custom:      return "item"
        }
    }

    /// Plural noun, e.g. "12 restaurants left to rank".
    var pluralNoun: String {
        switch self {
        case .anime, .manga: return itemNoun
        case .custom:        return "items"
        default:             return itemNoun + "s"
        }
    }

    /// Placeholder shown in the create-list name field.
    var namePlaceholder: String {
        switch self {
        case .restaurants: return "e.g. Tokyo ramen"
        case .bars:        return "e.g. Cocktail bars — NYC"
        case .stays:       return "e.g. Hotels in Japan"
        case .movies:      return "e.g. Films of 2025"
        case .books:       return "e.g. Sci-fi favorites"
        case .anime:       return "e.g. Seasonal anime"
        case .manga:       return "e.g. Shōnen favorites"
        case .games:       return "e.g. Co-op games"
        case .albums:      return "e.g. Desert island albums"
        case .custom:      return "e.g. Natural wines"
        }
    }

    /// Whether this category has cover art worth showing (posters, covers).
    var hasArtwork: Bool {
        switch self {
        case .movies, .books, .anime, .manga, .games, .albums: return true
        case .restaurants, .bars, .stays, .custom: return false
        }
    }

    /// Aspect ratio (width / height) of the category's cover art.
    var artworkAspectRatio: CGFloat {
        switch self {
        case .movies, .books, .anime, .manga, .games: return 2.0 / 3.0
        case .albums, .restaurants, .bars, .stays, .custom: return 1
        }
    }
}

// MARK: - App-wide UIKit appearance

enum AppAppearance {
    /// UIKit-backed chrome that SwiftUI can't style directly: serif
    /// navigation titles and the global tint used by alerts and menus.
    @MainActor
    static func configure() {
        let ink = UIColor(Theme.textPrimary)

        let nav = UINavigationBar.appearance()
        nav.largeTitleTextAttributes = [
            .font: serifFont(size: 34, weight: .bold, textStyle: .largeTitle),
            .foregroundColor: ink,
        ]
        nav.titleTextAttributes = [
            .font: serifFont(size: 17, weight: .semibold, textStyle: .headline),
            .foregroundColor: ink,
        ]

        UIView.appearance(whenContainedInInstancesOf: [UIAlertController.self]).tintColor = UIColor(Theme.accent)
    }

    private static func serifFont(size: CGFloat, weight: UIFont.Weight, textStyle: UIFont.TextStyle) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let font = base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }
}
