import XCTest
@testable import AnyRank

final class ServiceBrandTests: XCTestCase {

    func test_brandFromLink() {
        func brand(_ s: String) -> ServiceBrand? { ServiceBrand(url: URL(string: s)!) }
        XCTAssertEqual(brand("https://store.steampowered.com/app/1145360/"), .steam)
        XCTAssertEqual(brand("https://steamcommunity.com/my/edit/settings"), .steam)
        XCTAssertEqual(brand("https://boxd.it/abc"), .letterboxd)
        XCTAssertEqual(brand("https://letterboxd.com/settings/data/"), .letterboxd)
        XCTAssertEqual(brand("https://www.imdb.com/title/tt1375666/"), .imdb)
        XCTAssertEqual(brand("https://www.goodreads.com/book/show/1"), .goodreads)
        XCTAssertEqual(brand("https://app.thestorygraph.com/books/x"), .storyGraph)
        XCTAssertEqual(brand("https://open.spotify.com/album/1"), .spotify)
        XCTAssertEqual(brand("https://anilist.co/anime/1"), .aniList)
        XCTAssertEqual(brand("https://www.google.com/maps/place/?q=place_id:abc"), .googleMaps)
        XCTAssertEqual(brand("https://maps.google.com/?cid=123"), .googleMaps)
        XCTAssertNil(brand("https://www.google.com/search?q=x"), "Google, but not Maps")
        XCTAssertNil(brand("https://notimdb.com/title/tt1"), "lookalike domain")
        XCTAssertNil(brand("https://www.igdb.com/games/hades"))
    }

    func test_everyBrandHasAnIcon() {
        for brand in ServiceBrand.allCases {
            XCTAssertNotNil(UIImage(named: brand.assetName), "\(brand) icon missing from the asset catalog")
        }
    }

    func test_brandForSources() {
        XCTAssertEqual(ServiceBrand(ImportSourceKind.steam), .steam)
        XCTAssertNil(ServiceBrand(ImportSourceKind.pastedList))
    }
}
