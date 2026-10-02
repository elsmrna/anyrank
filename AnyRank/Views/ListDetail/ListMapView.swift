import MapKit
import SwiftUI

/// A place list on a map: one pin per located item in its bucket color with
/// its rank, higher ranks drawn on top, clustered when zoomed out. Opens
/// centered on the user when something is within 5 miles, otherwise fitted
/// to the whole list. Shown in place of the ranked list from list detail.
struct ListMapView: View {
    let list: RankList

    @Environment(Repository.self) private var repository
    @Environment(\.placesService) private var placesService
    @AppStorage(LocationProvider.useOnMapsKey) private var useLocation = true

    @State private var location = LocationProvider.shared
    @State private var selectedID: UUID?
    @State private var region: MKCoordinateRegion?
    @State private var regionRequest = 0
    @State private var openedAt = Date()
    @State private var reframedForUser = false
    @State private var dismissedLocationBanner = false
    @State private var finding = false
    @State private var findMessage: String?

    private var ranked: [RankItem] { list.itemsSortedByScore() }

    private var pins: [ItemPin] {
        let items = ranked
        return items.enumerated().compactMap { index, item in
            guard let lat = item.latitude, let lon = item.longitude else { return nil }
            return ItemPin(
                id: item.id,
                name: item.name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                rank: index + 1,
                total: items.count,
                bucket: item.bucket
            )
        }
    }

    private var unlocatedCount: Int {
        list.items.filter { $0.latitude == nil || $0.longitude == nil }.count
    }

    private var usableUserLocation: CLLocationCoordinate2D? {
        guard useLocation, location.isAuthorized else { return nil }
        return location.location?.coordinate
    }

    var body: some View {
        ZStack {
            if pins.isEmpty {
                noLocations
            } else {
                RankedMapView(
                    pins: pins,
                    showsUserLocation: useLocation && location.isAuthorized,
                    region: region,
                    regionRequest: regionRequest,
                    selectedID: $selectedID
                )
                .ignoresSafeArea(edges: .bottom)
            }
        }
        .overlay(alignment: .top) {
            VStack(spacing: 8) {
                if useLocation && location.isDenied && !dismissedLocationBanner {
                    locationBanner
                }
                if unlocatedCount > 0 && !pins.isEmpty {
                    missingPill
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            if let selected = list.items.first(where: { $0.id == selectedID }) {
                SelectedPlaceCard(item: selected, list: list, rank: (ranked.firstIndex { $0.id == selected.id } ?? 0) + 1) {
                    selectedID = nil
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Theme.spring, value: selectedID)
        .onAppear {
            openedAt = Date()
            frame()
            if useLocation { location.start() }
        }
        .onChange(of: location.location) {
            // A fix that arrives just after opening can still re-center on
            // the user; later ones don't yank the map around.
            guard !reframedForUser, Date().timeIntervalSince(openedAt) < 5,
                  let user = usableUserLocation,
                  MapFraming.hasPin(pins.map(\.coordinate), within: MapFraming.nearbyRadius, of: user)
            else { return }
            reframedForUser = true
            frame()
        }
        .onChange(of: pins.count) { frame() }
    }

    private func frame() {
        region = MapFraming.initialRegion(pins: pins.map(\.coordinate), user: usableUserLocation)
        regionRequest += 1
    }

    // MARK: Overlays

    private var locationBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "location.slash")
                .foregroundStyle(Theme.accent)
            Text("Turn on location to see what's near you.")
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.footnote.weight(.semibold))
            Button {
                dismissedLocationBanner = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityLabel("Not now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private var missingPill: some View {
        HStack(spacing: 8) {
            Text(findMessage ?? "\(unlocatedCount) \(unlocatedCount == 1 ? "item has" : "items have") no location")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            findButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surface, in: Capsule())
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
    }

    private var findButton: some View {
        Button {
            Task { await findLocations() }
        } label: {
            if finding {
                ProgressView().controlSize(.small)
            } else {
                Text("Find").font(.footnote.weight(.semibold))
            }
        }
        .disabled(finding)
    }

    private var noLocations: some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.slash")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(list.category.tint)
            Text("Nothing to map yet")
                .font(.display(.title3))
                .foregroundStyle(Theme.textPrimary)
            Text(findMessage ?? "None of these \(list.category.itemNoun)s have a location. Find them on Google Maps by name?")
                .font(.callout)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task { await findLocations() }
            } label: {
                if finding { ProgressView() } else { Text("Find locations") }
            }
            .buttonStyle(.secondary)
            .disabled(finding)
            .fixedSize()
        }
        .padding(.horizontal, Theme.gutter)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func findLocations() async {
        let missing = unlocatedCount
        finding = true
        let found = await PlaceBackfill.run(on: list, using: placesService, repository: repository)
        finding = false
        findMessage = found == 0
            ? "Couldn't find \(missing == 1 ? "it" : "them") on Google Maps"
            : "Found \(found) of \(missing)"
    }
}

/// One located item on the map.
struct ItemPin: Equatable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
    let rank: Int
    let total: Int
    let bucket: Bucket

    static func == (a: ItemPin, b: ItemPin) -> Bool {
        a.id == b.id && a.name == b.name && a.rank == b.rank && a.total == b.total && a.bucket == b.bucket
            && a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude
    }
}

/// Card for the selected pin: what it is, where it ranks, and ways to open it.
private struct SelectedPlaceCard: View {
    let item: RankItem
    let list: RankList
    let rank: Int
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink {
                ItemDetailView(item: item, list: list)
            } label: {
                HStack(spacing: 12) {
                    Text("\(rank)")
                        .font(.score(.headline, weight: .bold))
                        .foregroundStyle(item.bucket.ink)
                        .frame(width: 36, height: 36)
                        .background(item.bucket.color.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if let address = item.address {
                            Text(address)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if let maps = item.mapsURLString.flatMap(URL.init(string:)) {
                Link(destination: maps) {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityLabel("Open in Google Maps")
            }
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityLabel("Close")
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

// MARK: - MapKit

/// MKMapView wrapper: SwiftUI's `Map` can't cluster annotations or set
/// their stacking order, which this needs.
struct RankedMapView: UIViewRepresentable {
    let pins: [ItemPin]
    let showsUserLocation: Bool
    /// Applied whenever `regionRequest` changes.
    let region: MKCoordinateRegion?
    let regionRequest: Int
    @Binding var selectedID: UUID?

    func makeCoordinator() -> Coordinator { Coordinator(selectedID: $selectedID) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.pointOfInterestFilter = .excludingAll
        map.showsCompass = false
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: Coordinator.pinID)
        map.register(ClusterBadgeView.self, forAnnotationViewWithReuseIdentifier: Coordinator.clusterID)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.selectedID = $selectedID
        map.showsUserLocation = showsUserLocation

        if coordinator.pins != pins {
            coordinator.pins = pins
            map.removeAnnotations(map.annotations.filter { $0 is ItemAnnotation })
            map.addAnnotations(pins.map(ItemAnnotation.init))
        }

        if let region, coordinator.appliedRegionRequest != regionRequest {
            coordinator.appliedRegionRequest = regionRequest
            map.setRegion(region, animated: coordinator.hasAppliedRegion)
            coordinator.hasAppliedRegion = true
        }

        let selected = map.selectedAnnotations.compactMap { ($0 as? ItemAnnotation)?.pin.id }.first
        if selected != selectedID {
            if let selectedID, let annotation = map.annotations.first(where: { ($0 as? ItemAnnotation)?.pin.id == selectedID }) {
                map.selectAnnotation(annotation, animated: true)
            } else {
                map.selectedAnnotations.forEach { map.deselectAnnotation($0, animated: true) }
            }
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        static let pinID = "pin"
        static let clusterID = "cluster"

        var selectedID: Binding<UUID?>
        var pins: [ItemPin] = []
        var appliedRegionRequest = -1
        var hasAppliedRegion = false

        init(selectedID: Binding<UUID?>) {
            self.selectedID = selectedID
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let cluster = annotation as? MKClusterAnnotation {
                return mapView.dequeueReusableAnnotationView(withIdentifier: Self.clusterID, for: cluster)
            }
            guard let item = annotation as? ItemAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: Self.pinID, for: item) as! MKMarkerAnnotationView
            view.clusteringIdentifier = "items"
            view.markerTintColor = UIColor(item.pin.bucket.color)
            view.glyphText = "\(item.pin.rank)"
            view.titleVisibility = .adaptive
            view.subtitleVisibility = .hidden
            view.displayPriority = .defaultHigh
            view.zPriority = MapFraming.zPriority(forRank: item.pin.rank, of: item.pin.total)
            view.selectedZPriority = .max
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            if let cluster = annotation as? MKClusterAnnotation {
                mapView.deselectAnnotation(cluster, animated: false)
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                return
            }
            if let item = annotation as? ItemAnnotation, selectedID.wrappedValue != item.pin.id {
                selectedID.wrappedValue = item.pin.id
            }
        }

        func mapView(_ mapView: MKMapView, didDeselect annotation: MKAnnotation) {
            if let item = annotation as? ItemAnnotation, selectedID.wrappedValue == item.pin.id {
                selectedID.wrappedValue = nil
            }
        }
    }
}

/// A group of nearby places when zoomed out: a round badge with the count,
/// in ink rather than a bucket color and without a pin's point, so it can't
/// be mistaken for a ranked place.
final class ClusterBadgeView: MKAnnotationView {
    private let label = UILabel()
    private let size: CGFloat = 38

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        layer.cornerRadius = size / 2
        layer.borderWidth = 2.5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.18
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        label.frame = bounds
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 15, weight: .bold)
        addSubview(label)
        displayPriority = .required
        zPriority = .max
        collisionMode = .circle
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var annotation: MKAnnotation? {
        didSet {
            let count = (annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0
            label.text = "\(count)"
            accessibilityLabel = "\(count) places"
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }

    private func applyColors() {
        let traits = traitCollection
        backgroundColor = UIColor(Theme.textPrimary).resolvedColor(with: traits)
        layer.borderColor = UIColor(Theme.surface).resolvedColor(with: traits).cgColor
        label.textColor = UIColor(Theme.background).resolvedColor(with: traits)
    }
}

final class ItemAnnotation: NSObject, MKAnnotation {
    let pin: ItemPin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.name }

    init(_ pin: ItemPin) {
        self.pin = pin
    }
}
