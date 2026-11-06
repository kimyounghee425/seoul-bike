import CoreLocation
import MapKit
import SwiftUI

struct Place: Codable, Hashable {
    var name: String
    var address: String
    var lat: Double
    var lng: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: lat, longitude: lng) }
}

enum Field: Hashable { case origin, destination }

enum Screen: Hashable {
    case search(focus: Field)
    case pick(Field)
    case result
}

@Observable
final class AppModel {
    var stations: [Station] = []
    var stationsUpdatedAt: Date?
    var stationsFailed = false
    var stationsOffline = false
    var stationsLoading = false

    var origin: Place?        // nil = 내 위치
    var destination: Place?
    var path: [Screen] = []
    var homeRegion: MKCoordinateRegion? // 홈에서 마지막으로 보던 지도, 지도에서 선택이 여기서 시작

    let location = LocationService()

    var recent: [Place] {
        get { (try? JSONDecoder().decode([Place].self, from: UserDefaults.standard.data(forKey: "recent") ?? Data())) ?? [] }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(Array(newValue.prefix(10))), forKey: "recent") }
    }

    private static let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: "stations.json")

    // 마지막으로 받은 대여소를 바로 그리고, 최신 숫자는 뒤에서 갱신
    init() {
        if let d = try? Data(contentsOf: Self.cacheURL), let s = try? JSONDecoder().decode([Station].self, from: d) {
            stations = s
            stationsUpdatedAt = (try? FileManager.default.attributesOfItem(atPath: Self.cacheURL.path)[.modificationDate]) as? Date
        }
    }

    func loadStations() async {
        guard !stationsLoading else { return }
        stationsLoading = true
        defer { stationsLoading = false }
        do {
            stations = try await StationAPI.fetchAll()
            stationsUpdatedAt = .now
            try? JSONEncoder().encode(stations).write(to: Self.cacheURL)
            stationsFailed = false
            stationsOffline = false
        } catch {
            stationsFailed = true
            stationsOffline = isOffline(error)
        }
    }

    // 앱 다시 열 때 1분 넘게 지났으면 자동 갱신
    func refreshIfStale() async {
        if let t = stationsUpdatedAt, Date.now.timeIntervalSince(t) < 60 { return }
        await loadStations()
    }

    func set(_ field: Field, _ place: Place) {
        if field == .origin { origin = place } else { destination = place }
        if place.name != "내 위치" { recent = [place] + recent.filter { $0 != place } }
    }

    // 출발지(없으면 내 위치)·도착지 다 정해지면 결과 화면, 아니면 빈 칸 검색
    func proceed() {
        if destination == nil { path = [.search(focus: .destination)]; return }
        path = [.result]
    }

    var originPlace: Place? {
        if let origin { return origin }
        guard let c = location.coordinate else { return nil }
        return Place(name: "내 위치", address: "", lat: c.latitude, lng: c.longitude)
    }

    func nearest(to c: CLLocationCoordinate2D, where ok: (Station) -> Bool = { _ in true }) -> Station? {
        let p = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return stations.filter(ok).min { p.distance(from: $0.location) < p.distance(from: $1.location) }
    }
}

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var status: CLAuthorizationStatus = .notDetermined
    var coordinate: CLLocationCoordinate2D?
    var heading: Double? // 진북 기준 기기 방향(도)

    var denied: Bool { status == .denied || status == .restricted }

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 5
        status = manager.authorizationStatus
    }

    func request() { manager.requestWhenInUseAuthorization() }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        status = m.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways { m.startUpdatingLocation(); m.startUpdatingHeading() }
    }

    func locationManager(_ m: CLLocationManager, didUpdateHeading h: CLHeading) {
        heading = h.trueHeading >= 0 ? h.trueHeading : h.magneticHeading
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        coordinate = locs.last?.coordinate
    }
}

extension Station {
    var location: CLLocation { .init(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}

extension CLLocationCoordinate2D {
    func distance(to o: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: .init(latitude: o.latitude, longitude: o.longitude))
    }
}

extension MKCoordinateRegion {
    static let seoulCityHall = MKCoordinateRegion(
        center: .init(latitude: 37.5663, longitude: 126.9779),
        span: .init(latitudeDelta: 0.02, longitudeDelta: 0.02)
    )
}
