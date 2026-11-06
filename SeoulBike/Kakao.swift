import CoreLocation
import Foundation

// 카카오 로컬(검색·주소) + 길찾기(자전거·도보) REST
enum Kakao {
    private static func get<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var c = URLComponents(string: "https://dapi.kakao.com\(path)")!
        c.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var req = URLRequest(url: c.url!)
        req.setValue("KakaoAK \(Secrets.kakao)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct Docs<D: Decodable>: Decodable { let documents: [D] }

    static func search(_ q: String, near c: CLLocationCoordinate2D?) async throws -> [(Place, Int?)] {
        struct D: Decodable { let place_name, address_name, road_address_name, x, y: String; let distance: String? }
        var query = ["query": q, "size": "15"]
        if let c { query["x"] = "\(c.longitude)"; query["y"] = "\(c.latitude)" }
        let r: Docs<D> = try await get("/v2/local/search/keyword.json", query)
        return r.documents.compactMap { d in
            guard let x = Double(d.x), let y = Double(d.y) else { return nil }
            let addr = d.road_address_name.isEmpty ? d.address_name : d.road_address_name
            return (Place(name: d.place_name, address: addr, lat: y, lng: x), d.distance.flatMap(Int.init))
        }
    }

    static func address(at c: CLLocationCoordinate2D) async throws -> Place {
        struct A: Decodable { let address_name: String; let building_name: String? }
        struct D: Decodable { let road_address: A?; let address: A? }
        let r: Docs<D> = try await get("/v2/local/geo/coord2address.json", ["x": "\(c.longitude)", "y": "\(c.latitude)"])
        let d = r.documents.first
        let addr = d?.road_address?.address_name ?? d?.address?.address_name ?? "주소 없음"
        let building = d?.road_address?.building_name ?? ""
        return Place(name: building.isEmpty ? addr : building, address: building.isEmpty ? "" : addr,
                     lat: c.latitude, lng: c.longitude)
    }

    enum Mode: String { case bicycle, walk }

    static func route(_ mode: Mode, from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) async throws -> Leg {
        // 30m 이내는 경로 API가 실패하므로 직선
        let m = a.distance(to: b)
        if m < 30 { return Leg(path: [a, b], meters: Int(m), seconds: Int(m / 1.2)) }
        struct R: Decodable {
            struct Route: Decodable { let legs: [L] }
            struct L: Decodable { let properties: P; let steps: [S] }
            struct P: Decodable { let distance: Int; let time: Int }
            struct S: Decodable { let path: Path }
            struct Path: Decodable { let points: [[Double]] }
            let route: Route?
        }
        var q = ["start_x": "\(a.longitude)", "start_y": "\(a.latitude)", "end_x": "\(b.longitude)", "end_y": "\(b.latitude)"]
        if mode == .bicycle { q["route_mode"] = "SHORTEST" }
        let r: R
        do { r = try await get("/v2/routing/\(mode.rawValue)", q) } catch let e as URLError { throw e } catch { throw Trip.PlanError.routeFailed }
        if let legs = r.route?.legs, !legs.isEmpty {
            let pts = legs.flatMap { $0.steps.flatMap { $0.path.points } }.map { CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0]) }
            return Leg(path: pts, meters: legs.reduce(0) { $0 + $1.properties.distance },
                       seconds: legs.reduce(0) { $0 + $1.properties.time })
        }
        throw Trip.PlanError.routeFailed
    }
}

struct Leg {
    let path: [CLLocationCoordinate2D]
    let meters: Int
    let seconds: Int
    var minutes: Int { max(1, Int((Double(seconds) / 60).rounded(.up))) }
}
