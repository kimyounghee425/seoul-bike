import Foundation

struct Trip {
    let origin: Place
    let destination: Place
    let start: Station
    let end: Station
    let walkTo: Leg
    let bike: Leg
    let walkFrom: Leg

    var totalMinutes: Int { walkTo.minutes + bike.minutes + walkFrom.minutes }
    var totalKm: String { String(format: "%.1fkm", Double(walkTo.meters + bike.meters + walkFrom.meters) / 1000) }

    // 일일권 1·2·3시간 (1,000원/시간), 반납 지연 대비 5분 여유
    var pass: (title: String, detail: String) {
        let ride = bike.minutes
        guard let hours = (1...3).first(where: { ride <= $0 * 60 - 5 }) else {
            return ("3시간권으로도 부족해요", "자전거로 \(ride)분이라 중간에 반납하고 다시 빌려야 해요")
        }
        return ("\(hours)시간권이면 충분해요", "\(hours),000원이고 \(hours * 60 - ride)분 여유 있어요")
    }

    enum PlanError: LocalizedError {
        case noLocation, noStation, tooClose
        var errorDescription: String? {
            switch self {
            case .noLocation: "현재 위치를 아직 못 찾았어요"
            case .noStation: "근처에 자전거가 있는 대여소가 없어요"
            case .tooClose: "가까워서 걸어가는 게 더 빨라요"
            }
        }
    }

    static func plan(_ model: AppModel) async throws -> Trip {
        guard let o = model.originPlace, let d = model.destination else { throw PlanError.noLocation }
        guard let s = model.nearest(to: o.coordinate, where: { $0.bikes > 0 }),
              let e = model.nearest(to: d.coordinate) else { throw PlanError.noStation }
        if s.id == e.id { throw PlanError.tooClose }
        async let w1 = Kakao.route(.walk, from: o.coordinate, to: s.coordinate)
        async let b = Kakao.route(.bicycle, from: s.coordinate, to: e.coordinate)
        async let w2 = Kakao.route(.walk, from: e.coordinate, to: d.coordinate)
        return await Trip(origin: o, destination: d, start: s, end: e, walkTo: w1, bike: b, walkFrom: w2)
    }
}

extension Trip {
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
    }
}
