import CoreLocation
import Foundation

struct Station: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
    let bikes: Int
}

// 서울시 따릉이 실시간 대여정보 (bikeList), 1회 최대 1000건이라 페이지 단위 호출
enum StationAPI {
    private struct Response: Decodable {
        struct Body: Decodable { let row: [Row]? }
        struct Row: Decodable {
            let stationId, stationName, stationLatitude, stationLongitude, parkingBikeTotCnt: String
        }
        let rentBikeStatus: Body?
    }

    // 약 2,700개라 3페이지를 동시에, 더 있으면 이어서
    static func fetchAll() async throws -> [Station] {
        var all = try await withThrowingTaskGroup(of: (Int, [Station]).self) { g in
            for i in 0..<3 { g.addTask { (i, try await fetch(start: i * 1000 + 1, end: i * 1000 + 1000)) } }
            var pages: [(Int, [Station])] = []
            for try await p in g { pages.append(p) }
            return pages.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        var start = 3001
        while all.count == start - 1 {
            let page = try await fetch(start: start, end: start + 999)
            all += page
            if page.count < 1000 { break }
            start += 1000
        }
        return all
    }

    private static func fetch(start: Int, end: Int) async throws -> [Station] {
        let url = URL(string: "http://openapi.seoul.go.kr:8088/\(Secrets.seoul)/json/bikeList/\(start)/\(end)/")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let rows = try JSONDecoder().decode(Response.self, from: data).rentBikeStatus?.row ?? []
        return rows.compactMap { r in
            guard let lat = Double(r.stationLatitude), let lng = Double(r.stationLongitude) else { return nil }
            return Station(
                id: r.stationId,
                name: displayName(r.stationName),
                coordinate: .init(latitude: lat, longitude: lng),
                bikes: Int(r.parkingBikeTotCnt) ?? 0
            )
        }
    }

    // "102. 망원역 1번출구 앞" → "망원역 1번출구 앞"
    static func displayName(_ raw: String) -> String {
        guard let dot = raw.firstIndex(of: "."), raw[..<dot].allSatisfy(\.isNumber) else { return raw }
        return raw[raw.index(after: dot)...].trimmingCharacters(in: .whitespaces)
    }
}

// 폰 저장용
extension Station: Codable {
    private enum K: String, CodingKey { case id, name, lat, lng, bikes }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: K.self)
        self.init(id: try c.decode(String.self, forKey: .id), name: try c.decode(String.self, forKey: .name),
                  coordinate: .init(latitude: try c.decode(Double.self, forKey: .lat), longitude: try c.decode(Double.self, forKey: .lng)),
                  bikes: try c.decode(Int.self, forKey: .bikes))
    }
    func encode(to e: Encoder) throws {
        var c = e.container(keyedBy: K.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(coordinate.latitude, forKey: .lat); try c.encode(coordinate.longitude, forKey: .lng)
        try c.encode(bikes, forKey: .bikes)
    }
}
