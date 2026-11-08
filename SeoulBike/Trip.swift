import CoreLocation
import Foundation

struct Trip {
    let origin: Place
    let destination: Place
    let start: Station
    let end: Station
    let walkTo: Leg
    let bike: Leg
    let walkFrom: Leg
    // 출발지(내 위치)와 대여소 근접: same 복합 마커, close 마커 둘, 둘 다 도보선 없음 (피그마 C2 C3 C8)
    enum Near { case far, close, same }
    var near: Near = .far

    var allPoints: [CLLocationCoordinate2D] { walkTo.path + bike.path + walkFrom.path }
    var totalMinutes: Int { (near == .far ? walkTo.minutes : 0) + bike.minutes + walkFrom.minutes }
    var totalKm: String { String(format: "%.1fkm", Double(walkTo.meters + bike.meters + walkFrom.meters) / 1000) }

    // 일일권 1·2·3시간 (1,000원/시간), 반납 지연 대비 5분 여유
    var pass: (title: String, detail: String) {
        let ride = bike.minutes
        guard let hours = (1...3).first(where: { ride <= $0 * 60 - 5 }) else {
            return ("3시간권으로도 부족해요", "자전거로 \(ride)분이라 중간에 반납하고 다시 빌려야 해요")
        }
        return ("\(hours)시간권이면 충분해요", "\(hours),000원이고 \(hours * 60 - ride)분 여유 있어요")
    }

    // 결과 시트 한 줄용: "1시간권 1,000원이면 충분해요"
    var passLine: String {
        let ride = bike.minutes
        guard let hours = (1...3).first(where: { ride <= $0 * 60 - 5 }) else { return "3시간권으로도 부족해요" }
        return "\(hours)시간권 \(hours),000원이면 충분해요"
    }
    var walkMinutes: Int { (near == .far ? walkTo.minutes : 0) + walkFrom.minutes }

    // 문구는 피그마 "엣지케이스" E1~E6
    enum PlanError: Error {
        case noLocation, farFromOrigin, farFromDestination, tooClose, routeFailed, offline

        var title: String {
            switch self {
            case .noLocation: "지금 위치를 알 수 없어요"
            case .farFromOrigin: "출발지 근처에 대여소가 없어요"
            case .farFromDestination: "도착지 근처에 대여소가 없어요"
            case .tooClose: "걸어가는 게 더 빨라요"
            case .routeFailed: "경로를 불러오지 못했어요"
            case .offline: "인터넷에 연결되지 않았어요"
            }
        }
        var detail: String {
            switch self {
            case .noLocation: "위치 권한이 꺼져 있어요.\n출발지를 직접 정하면 바로 찾아 드릴게요."
            case .farFromOrigin: "가장 가까운 대여소가 1km 넘게 떨어져 있어요.\n출발지를 바꿔서 다시 찾아 주세요."
            case .farFromDestination: "가장 가까운 대여소가 1km 넘게 떨어져 있어요.\n도착지를 바꿔서 다시 찾아 주세요."
            case .tooClose: "출발지와 도착지가 같은 대여소를 써요.\n도착지를 바꿔서 다시 찾아 주세요."
            case .routeFailed: "잠시 문제가 생겼어요.\n조금 뒤에 다시 찾아 주세요."
            case .offline: "와이파이나 데이터 연결을 확인하고\n다시 찾아 주세요."
            }
        }
        var button: String {
            switch self {
            case .noLocation: "출발지 정하기"
            case .farFromOrigin: "출발지 바꾸기"
            case .farFromDestination, .tooClose: "도착지 바꾸기"
            case .routeFailed, .offline: "다시 찾기"
            }
        }

        static func from(_ e: Error) -> PlanError {
            if let p = e as? PlanError { return p }
            return isOffline(e) ? .offline : .routeFailed
        }
    }

    static let maxWalkToStation = 1000.0 // m

    static func plan(_ model: AppModel) async throws -> Trip {
        guard let o = model.originPlace, let d = model.destination else { throw PlanError.noLocation }
        if model.stations.isEmpty { throw model.stationsOffline ? PlanError.offline : PlanError.routeFailed }
        guard let s = model.nearest(to: o.coordinate, where: { $0.bikes > 0 }),
              s.coordinate.distance(to: o.coordinate) <= maxWalkToStation else { throw PlanError.farFromOrigin }
        guard let e = model.nearest(to: d.coordinate),
              e.coordinate.distance(to: d.coordinate) <= maxWalkToStation else { throw PlanError.farFromDestination }
        if s.id == e.id { throw PlanError.tooClose }
        async let w1 = Kakao.route(.walk, from: o.coordinate, to: s.coordinate)
        async let b = Kakao.route(.bicycle, from: s.coordinate, to: e.coordinate)
        async let w2 = Kakao.route(.walk, from: e.coordinate, to: d.coordinate)
        var t = try await Trip(origin: o, destination: d, start: s, end: e, walkTo: w1, bike: b, walkFrom: w2)
        t.near = near(origin: o.coordinate, station: s.coordinate, isMyLocation: model.origin == nil, accuracy: model.location.accuracy)
        return t
    }
}

extension Trip {
    // d ≤ min(max(15, 정확도), 30) → 같은 자리, 50m 이하 → 가까움. 정확도 65m 넘으면 합치지 않음
    static func near(origin: CLLocationCoordinate2D, station: CLLocationCoordinate2D, isMyLocation: Bool, accuracy: Double?) -> Near {
        let d = origin.distance(to: station)
        if d > 50 { return .far }
        guard isMyLocation, let acc = accuracy, acc <= 65 else { return .close }
        return d <= min(max(15, acc), 30) ? .same : .close
    }

    // assert 기반 자체 점검
    static func selfCheck() {
        func trip(_ min: Int) -> Trip {
            let p = Place(name: "", address: "", lat: 0, lng: 0)
            let st = Station(id: "", name: "", coordinate: .init(), bikes: 1)
            let z = Leg(path: [], meters: 0, seconds: 0)
            return Trip(origin: p, destination: p, start: st, end: st, walkTo: z,
                        bike: Leg(path: [], meters: 0, seconds: min * 60), walkFrom: z)
        }
        assert(trip(14).pass.title.hasPrefix("1시간권"))
        assert(trip(55).pass.title.hasPrefix("1시간권"))
        assert(trip(56).pass.title.hasPrefix("2시간권"))
        assert(trip(176).pass.title.hasPrefix("3시간권으로도"))
        let a = CLLocationCoordinate2D(latitude: 37.5446, longitude: 127.0565)
        let at = { (m: Double) in CLLocationCoordinate2D(latitude: a.latitude + m / 111_000, longitude: a.longitude) }
        assert(near(origin: a, station: at(10), isMyLocation: true, accuracy: 5) == .same)
        assert(near(origin: a, station: at(20), isMyLocation: true, accuracy: 5) == .close)   // 기준 15m
        assert(near(origin: a, station: at(25), isMyLocation: true, accuracy: 28) == .same)   // 정확도만큼 넓힘
        assert(near(origin: a, station: at(40), isMyLocation: true, accuracy: 60) == .close)  // 30m 상한
        assert(near(origin: a, station: at(10), isMyLocation: true, accuracy: 80) == .close)  // 정확도 나쁨
        assert(near(origin: a, station: at(10), isMyLocation: false, accuracy: 5) == .close)  // 검색한 출발지
        assert(near(origin: a, station: at(70), isMyLocation: true, accuracy: 5) == .far)
        let line = MapHandle.dashes([a, at(100)], dash: 10, gap: 5)
        // 10 5 10 5 ... 약 100m → 막대·빈칸 번갈아 13~14조각, 막대로 시작
        assert(line.first?.on == true && (13...14).contains(line.count) && zip(line, line.dropFirst()).allSatisfy { $0.on != $1.on })
    }
}

func isOffline(_ e: Error) -> Bool {
    guard let u = e as? URLError else { return false }
    return [.notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .cannotConnectToHost, .timedOut].contains(u.code)
}
