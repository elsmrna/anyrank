import SwiftUI

/// Outside services AnyRank imports from or links out to, with their
/// official icons (bundled in `Assets.xcassets/Brands`, taken from each
/// company's own App Store listing or website).
enum ServiceBrand: String, CaseIterable {
    case steam
    case letterboxd
    case imdb
    case goodreads
    case storyGraph
    case spotify
    case googleMaps
    case aniList

    var displayName: String {
        switch self {
        case .steam:      return "Steam"
        case .letterboxd: return "Letterboxd"
        case .imdb:       return "IMDb"
        case .goodreads:  return "Goodreads"
        case .storyGraph: return "StoryGraph"
        case .spotify:    return "Spotify"
        case .googleMaps: return "Maps"
        case .aniList:    return "AniList"
        }
    }

    var assetName: String {
        switch self {
        case .storyGraph: return "brand-storygraph"
        case .googleMaps: return "brand-googlemaps"
        case .aniList:    return "brand-anilist"
        default:          return "brand-\(rawValue)"
        }
    }

    /// The brand behind an import source; nil for a pasted list.
    init?(_ source: ImportSourceKind) {
        switch source {
        case .steam:      self = .steam
        case .letterboxd: self = .letterboxd
        case .imdb:       self = .imdb
        case .goodreads:  self = .goodreads
        case .storyGraph: self = .storyGraph
        case .pastedList: return nil
        }
    }

    /// The brand a link points at, judged by its host.
    init?(url: URL) {
        let host = url.host()?.lowercased() ?? ""
        let path = url.path().lowercased()
        func matches(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if matches("steampowered.com") || matches("steamcommunity.com") { self = .steam }
        else if matches("letterboxd.com") || matches("boxd.it") { self = .letterboxd }
        else if matches("imdb.com") { self = .imdb }
        else if matches("goodreads.com") { self = .goodreads }
        else if matches("thestorygraph.com") { self = .storyGraph }
        else if matches("spotify.com") { self = .spotify }
        else if matches("anilist.co") { self = .aniList }
        else if host == "maps.google.com" || host == "maps.app.goo.gl"
                    || (matches("google.com") && path.hasPrefix("/maps"))
                    || (host == "goo.gl" && path.hasPrefix("/maps")) { self = .googleMaps }
        else { return nil }
    }
}

/// A service's icon as a small rounded tile.
struct BrandIcon: View {
    let brand: ServiceBrand
    var size: CGFloat = 28

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Image(brand.assetName)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .clipShape(shape)
            // Keeps white icons (StoryGraph, Maps) from dissolving into
            // light cards.
            .overlay(shape.strokeBorder(Theme.hairline, lineWidth: 0.5))
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack {
        ForEach(ServiceBrand.allCases, id: \.self) { BrandIcon(brand: $0, size: 36) }
    }
    .padding()
}
