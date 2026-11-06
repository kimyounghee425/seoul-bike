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

    static func fetchAll() async throws -> [Station] {
        var all: [Station] = []
        var start = 1
        while true {
            let page = try await fetch(start: start, end: start + 999)
            all += page
            if page.count < 1000 { return all }
            start += 1000
        }
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
