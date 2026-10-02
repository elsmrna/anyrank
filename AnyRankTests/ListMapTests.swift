import MapKit
import XCTest
@testable import AnyRank

/// How a list's map opens, how pins stack, and which Places result is
/// trusted when filling in a missing location.
final class ListMapTests: XCTestCase {

    private let downtownLA = CLLocationCoordinate2D(latitude: 34.0522, longitude: -118.2437)
    private let artsDistrict = CLLocationCoordinate2D(latitude: 34.0337, longitude: -118.2295) // ~1.5 mi from downtown
    private let venice = CLLocationCoordinate2D(latitude: 33.9906, longitude: -118.4649)       // ~14 mi
    private let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)

    func test_somethingWithinFiveMiles_centersOnUser_fiveMilesEachWay() throws {
        let region = try XCTUnwrap(MapFraming.initialRegion(pins: [artsDistrict, sanFrancisco], user: downtownLA))
        XCTAssertEqual(region.center.latitude, downtownLA.latitude, accuracy: 0.0001)
        XCTAssertEqual(region.center.longitude, downtownLA.longitude, accuracy: 0.0001)
        // 10 miles top to bottom is about 0.145° of latitude.
        XCTAssertEqual(region.span.latitudeDelta, 0.145, accuracy: 0.01)
    }

    func test_nothingNearby_fitsEveryPin() throws {
        let region = try XCTUnwrap(MapFraming.initialRegion(pins: [venice, sanFrancisco], user: CLLocationCoordinate2D(latitude: 40.71, longitude: -74.0)))
        for pin in [venice, sanFrancisco] {
            XCTAssertLessThanOrEqual(abs(pin.latitude - region.center.latitude), region.span.latitudeDelta / 2)
            XCTAssertLessThanOrEqual(abs(pin.longitude - region.center.longitude), region.span.longitudeDelta / 2)
        }
    }

    func test_withoutLocation_fitsEveryPin() throws {
        let region = try XCTUnwrap(MapFraming.initialRegion(pins: [artsDistrict, venice], user: nil))
        XCTAssertEqual(region.center.latitude, (artsDistrict.latitude + venice.latitude) / 2, accuracy: 0.0001)
    }

    func test_singlePin_isNotStreetLevel() throws {
        let region = try XCTUnwrap(MapFraming.initialRegion(pins: [venice], user: nil))
        XCTAssertGreaterThanOrEqual(region.span.latitudeDelta, 0.02)
    }

    func test_noPins_noRegion() {
        XCTAssertNil(MapFraming.initialRegion(pins: [], user: downtownLA))
    }

    func test_higherRanksDrawOnTop() {
        let first = MapFraming.zPriority(forRank: 1, of: 10)
        let second = MapFraming.zPriority(forRank: 2, of: 10)
        let last = MapFraming.zPriority(forRank: 10, of: 10)
        XCTAssertGreaterThan(first.rawValue, second.rawValue)
        XCTAssertGreaterThan(second.rawValue, last.rawValue)
        XCTAssertLessThan(first.rawValue, MKAnnotationViewZPriority.max.rawValue, "selected pins still go above")
    }

    func test_backfill_onlyTrustsAnExactNameMatch() {
        let results = [
            PlaceSearchResult(id: "a", name: "Bestia Bar", address: "", latitude: 0, longitude: 0, mapsURL: URL(string: "https://maps.google.com")!),
            PlaceSearchResult(id: "b", name: "BESTIA", address: "", latitude: 34, longitude: -118, mapsURL: URL(string: "https://maps.google.com")!),
        ]
        XCTAssertEqual(PlaceBackfill.match(for: "Bestia", in: results)?.id, "b")
        XCTAssertNil(PlaceBackfill.match(for: "Kismet", in: results))
    }
}
