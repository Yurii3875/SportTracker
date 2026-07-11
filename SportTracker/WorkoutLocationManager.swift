import CoreLocation
import MapKit

@MainActor
final class WorkoutLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var route: [CLLocationCoordinate2D] = []
    @Published private(set) var totalDistance: CLLocationDistance = 0
    @Published private(set) var isTracking = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var wantsTracking = false

    var distanceText: String {
        if totalDistance >= 1_000 { return String(format: "%.2f км", totalDistance / 1_000) }
        return "\(Int(totalDistance.rounded())) м"
    }

    var routeRegion: MKCoordinateRegion? {
        guard let last = route.last else { return nil }
        guard route.count > 1 else {
            return MKCoordinateRegion(center: last, latitudinalMeters: 650, longitudinalMeters: 650)
        }
        let coordinates = route
        let minLatitude = coordinates.map(\.latitude).min() ?? last.latitude
        let maxLatitude = coordinates.map(\.latitude).max() ?? last.latitude
        let minLongitude = coordinates.map(\.longitude).min() ?? last.longitude
        let maxLongitude = coordinates.map(\.longitude).max() ?? last.longitude
        let center = CLLocationCoordinate2D(latitude: (minLatitude + maxLatitude) / 2, longitude: (minLongitude + maxLongitude) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLatitude - minLatitude) * 1.45, 0.006),
            longitudeDelta: max((maxLongitude - minLongitude) * 1.45, 0.006)
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.activityType = .fitness
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 5
        manager.pausesLocationUpdatesAutomatically = false
        manager.allowsBackgroundLocationUpdates = true
    }

    func start() {
        wantsTracking = true
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestAlwaysAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.startUpdatingLocation()
            isTracking = true
        default:
            isTracking = false
        }
    }

    func stop() {
        wantsTracking = false
        manager.stopUpdatingLocation()
        isTracking = false
        lastLocation = nil
    }

    func reset() {
        stop()
        route = []
        totalDistance = 0
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if wantsTracking { start() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        for location in locations where isUsable(location) {
            defer { lastLocation = location }
            guard let previous = lastLocation else {
                route.append(location.coordinate)
                continue
            }
            let segment = location.distance(from: previous)
            // Отбрасываем типичные GPS-скачки, но учитываем реальное движение.
            guard segment >= 1, segment <= 150 else { continue }
            totalDistance += segment
            route.append(location.coordinate)
        }
    }

    private func isUsable(_ location: CLLocation) -> Bool {
        location.horizontalAccuracy >= 0 && location.horizontalAccuracy <= 50 && location.timestamp.timeIntervalSinceNow > -20
    }
}

