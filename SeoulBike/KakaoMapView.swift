import CoreLocation
import KakaoMapsSDK
import MapKit
import SwiftUI

// 카카오맵 지도 한 장. 화면(홈·지도에서 선택·추천 결과)은 MapHandle로만 지도를 다룸
// 마커는 SwiftUI 뷰를 이미지로 구워 POI로 올림 (숫자별 캐시)
struct KakaoMapView: UIViewRepresentable {
    let handle: MapHandle

    func makeUIView(context: Context) -> KMViewContainer {
        let view = KMViewContainer(frame: UIScreen.main.bounds)
        context.coordinator.handle = handle
        context.coordinator.controller = KMController(viewContainer: view)
        context.coordinator.controller?.delegate = context.coordinator
        context.coordinator.controller?.prepareEngine()
        return view
    }

    func updateUIView(_ uiView: KMViewContainer, context: Context) {
        if let c = context.coordinator.controller, c.isEnginePrepared, !c.isEngineActive { c.activateEngine() }
    }

    static func dismantleUIView(_ uiView: KMViewContainer, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
        coordinator.controller?.pauseEngine()
        coordinator.controller?.resetEngine()
        MainActor.assumeIsolated { coordinator.handle?.map = nil }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MapControllerDelegate, KakaoMapEventDelegate {
        var controller: KMController?
        weak var handle: MapHandle?
        var timer: Timer?
        private var observers: [NSObjectProtocol] = []

        override init() {
            super.init()
            let nc = NotificationCenter.default
            observers = [
                nc.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.controller?.pauseEngine()
                },
                nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                    self?.controller?.activateEngine()
                },
            ]
        }

        deinit { observers.forEach(NotificationCenter.default.removeObserver) }

        // SDK 델리게이트는 메인 스레드에서 불림
        func addViews() {
            let start = MainActor.assumeIsolated { handle?.initialCamera }
            let center = start?.center ?? MKCoordinateRegion.seoulCityHall.center
            let info = MapviewInfo(viewName: "mapview", viewInfoName: "map",
                                   defaultPosition: MapPoint(longitude: center.longitude, latitude: center.latitude),
                                   defaultLevel: start?.zoom ?? 15)
            controller?.addView(info)
        }

        func addViewSucceeded(_ viewName: String, viewInfoName: String) {
            guard let map = controller?.getView(viewName) as? KakaoMap else { return }
            map.eventDelegate = self
            map.setLogoPosition(origin: GuiAlignment(vAlign: .top, hAlign: .left), position: CGPoint(x: 16, y: 130))
            MainActor.assumeIsolated { handle?.attach(map) }
        }

        func addViewFailed(_ viewName: String, viewInfoName: String) {}

        func containerDidResized(_ size: CGSize) {
            let map = controller?.getView("mapview") as? KakaoMap
            map?.viewRect = CGRect(origin: .zero, size: size)
        }

        func authenticationFailed(_ errorCode: Int, desc: String) {
            // 키·번들 ID 불일치 등. 지도는 안 뜨지만 앱은 계속 동작
            print("KakaoMap auth failed \(errorCode): \(desc)")
        }

        // MARK: 지도 이벤트

        func cameraWillMove(kakaoMap: KakaoMap, by: MoveBy) {
            guard timer == nil else { return }
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle?.readCamera(final: false) }
            }
        }

        func cameraDidStopped(kakaoMap: KakaoMap, by: MoveBy) {
            timer?.invalidate()
            timer = nil
            MainActor.assumeIsolated { handle?.readCamera(final: true) }
        }

        func terrainDidLongPressed(kakaoMap: KakaoMap, position: MapPoint) {
            let c = position.wgsCoord
            MainActor.assumeIsolated { handle?.onLongPress?(.init(latitude: c.latitude, longitude: c.longitude)) }
        }

        func poiDidTapped(kakaoMap: KakaoMap, layerID: String, poiID: String, position: MapPoint) {
            let c = position.wgsCoord
            MainActor.assumeIsolated {
                switch layerID {
                case "stations": handle?.onStationTap?(poiID)
                case "clusters": handle?.onClusterTap?(.init(latitude: c.latitude, longitude: c.longitude))
                default: break
                }
            }
        }
    }
}

@Observable
@MainActor
final class MapHandle {
    // 화면이 읽는 상태
    var center: CLLocationCoordinate2D?
    var rotation: Double = 0 // 라디안, 시계 방향
    var region: MKCoordinateRegion?
    var ready = false

    // 화면이 거는 콜백
    var onCamera: ((MKCoordinateRegion, _ final: Bool) -> Void)?
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    var onStationTap: ((String) -> Void)?
    var onClusterTap: ((CLLocationCoordinate2D) -> Void)?

    // 지도가 뜨기 전 요청은 보관했다가 attach 때 적용
    var initialCamera: (center: CLLocationCoordinate2D, zoom: Int)?
    var margins = UIEdgeInsets.zero

    @ObservationIgnored weak var map: KakaoMap?
    @ObservationIgnored private var styles = Set<String>()
    @ObservationIgnored private var shownStations: [String: String] = [:] // id → styleID
    @ObservationIgnored private var shownClusters: [String: String] = [:]
    @ObservationIgnored private var me: (coord: CLLocationCoordinate2D?, heading: Double?) = (nil, nil)
    @ObservationIgnored private var mePois: (dot: Poi?, cone: Poi?) = (nil, nil)
    @ObservationIgnored private var meApplied: (coord: CLLocationCoordinate2D?, orient: Double?, coneShown: Bool) = (nil, nil, false)
    @ObservationIgnored private var pendingTrip: Trip??
    @ObservationIgnored private var trip: Trip?
    @ObservationIgnored private var routeSeq = 0
    @ObservationIgnored private var labelWidths: [String: CGFloat] = [:]
    @ObservationIgnored private var hideMe = false // 복합 마커일 때 내 위치 점 숨김
    private(set) var view: TripView = .all
    @ObservationIgnored private var pendingPin: CLLocationCoordinate2D??

    func attach(_ map: KakaoMap) {
        self.map = map
        let lm = map.getLabelManager()
        // 내 위치가 대여소 마커에 가려지지 않게 zOrder 크게 벌림
        for (id, z) in [("clusters", 10), ("stations", 20), ("tags", 10030), ("pins", 10040), ("me", 10100)] {
            _ = lm.addLabelLayer(option: LabelLayerOptions(layerID: id, competitionType: .none, competitionUnit: .symbolFirst, orderType: .rank, zOrder: z))
        }
        let rm = map.getRouteManager()
        _ = rm.addRouteLayer(layerID: "route", zOrder: 0)
        // 자전거: #2A4FE0 8 + 흰 테두리 3(피그마 2.5, SDK는 정수만) + 흰 쉐브론 38 / 비활성 #C3CDF7 + 진파랑 쉐브론 57
        // 도보: SDK에 점선이 없고 패턴은 정사각형으로만 찍혀서, 경로를 막대 조각으로 잘라 그림 (drawRoutes)
        let set = RouteStyleSet(styleID: "trip")
        let walk = UIColor(Token.Route.walk), walkOff = UIColor(Token.Route.walkInactive)
        let bike = UIColor(Token.Route.bike), bikeOff = UIColor(Token.Route.bikeInactive)
        set.addPattern(RoutePattern(pattern: Self.chevron(.white, 1.8), distance: 38, symbol: nil, pinStart: false, pinEnd: false))
        set.addPattern(RoutePattern(pattern: Self.chevron(bike, 2), distance: 57, symbol: nil, pinStart: false, pinEnd: false))
        for st in [PerLevelRouteStyle(width: 8, color: bike, strokeWidth: 3, strokeColor: .white, level: 0, patternIndex: 0),    // 0 자전거
                   PerLevelRouteStyle(width: 8, color: bikeOff, strokeWidth: 3, strokeColor: .white, level: 0, patternIndex: 1),  // 1 자전거 비활성
                   PerLevelRouteStyle(width: 5, color: walk, level: 0),       // 2 도보 막대
                   PerLevelRouteStyle(width: 7, color: walk, level: 0),       // 3 도보 막대 선택
                   PerLevelRouteStyle(width: 5, color: walkOff, level: 0),    // 4 도보 막대 비활성
                   PerLevelRouteStyle(width: 5, color: .clear, level: 0),     // 5 막대 사이 빈칸
                   PerLevelRouteStyle(width: 9, color: .white, level: 0),     // 6 도보 흰 바탕
                   PerLevelRouteStyle(width: 12, color: .white, level: 0)] {  // 7 도보 흰 바탕 선택
            set.addStyle(RouteStyle(styles: [st]))
        }
        rm.addRouteStyleSet(set)
        if margins != .zero { map.setMargins(margins) }
        // 지도 뜨기 전 들어온 이동 요청 (addViews 전에 못 받았을 수 있음)
        if let ic = initialCamera { initialCamera = nil; move(to: ic.center, zoom: ic.zoom, animated: false) }
        ready = true
        readCamera(final: true)
        applyMe()
        if let t = pendingTrip { setTrip(t); pendingTrip = nil }
        if let p = pendingPin { setDroppedPin(p); pendingPin = nil }
    }

    // MARK: 카메라

    func readCamera(final: Bool) {
        guard let map else { return }
        let r = map.viewRect
        guard r.width > 0 else { return }
        let c = map.getPosition(CGPoint(x: r.midX, y: r.midY)).wgsCoord
        let a = map.getPosition(CGPoint(x: r.minX, y: r.minY)).wgsCoord
        let b = map.getPosition(CGPoint(x: r.maxX, y: r.maxY)).wgsCoord
        let newCenter = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
        // 같은 값이면 대입 안 함: @Observable은 같은 값 대입에도 화면을 다시 그림
        if center.map({ $0.distance(to: newCenter) > 0.5 }) ?? true { center = newCenter }
        if abs(rotation - map.rotationAngle) > 0.001 { rotation = map.rotationAngle }
        let region = MKCoordinateRegion(center: newCenter, span: .init(latitudeDelta: abs(a.latitude - b.latitude), longitudeDelta: abs(a.longitude - b.longitude)))
        if final { self.region = region }
        applyMe()
        if final, trip != nil, map.zoomLevel != dashZoom { drawRoutes() }
        onCamera?(region, final)
    }

    // 카카오 줌 레벨 ↔ 화면 위도 폭 (iPhone 세로 기준 15레벨 ≈ 0.022도, 실측)
    static func zoom(forLatDelta d: Double) -> Int { max(6, min(20, Int(log2(0.022 / max(d, 1e-6)).rounded()) + 15)) }

    func move(to c: CLLocationCoordinate2D, zoom: Int? = nil, animated: Bool = true) {
        guard let map else { initialCamera = (c, zoom ?? 15); return }
        let p = MapPoint(longitude: c.longitude, latitude: c.latitude)
        let u = zoom.map { CameraUpdate.make(target: p, zoomLevel: $0, mapView: map) } ?? CameraUpdate.make(target: p, mapView: map)
        if animated { map.animateCamera(cameraUpdate: u, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 400)) }
        else { map.moveCamera(u) }
    }

    func show(_ r: MKCoordinateRegion, animated: Bool = false) {
        move(to: r.center, zoom: Self.zoom(forLatDelta: r.span.latitudeDelta), animated: animated)
    }

    func fit(_ points: [CLLocationCoordinate2D], animated: Bool = true) {
        guard let map, !points.isEmpty else { return }
        let u = CameraUpdate.make(area: AreaRect(points: points.map { MapPoint(longitude: $0.longitude, latitude: $0.latitude) }), levelLimit: 17)
        if animated { map.animateCamera(cameraUpdate: u, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 400)) }
        else { map.moveCamera(u) }
    }

    func resetNorth() {
        map?.resetCameraOrientation(CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 300))
    }

    func setMargins(_ m: UIEdgeInsets) { margins = m; map?.setMargins(m) }

    // MARK: 마커

    private func style(_ id: String, _ anchor: CGPoint = .init(x: 0.5, y: 0.5), _ make: () -> UIImage?) {
        style(id, anchor: { _ in anchor }, make)
    }

    // anchor를 구운 이미지 크기로 계산해야 할 때 (점이 왼쪽에 붙은 라벨 등)
    private func style(_ id: String, anchor: (CGSize) -> CGPoint, _ make: () -> UIImage?) {
        guard !styles.contains(id), let map, let img = make() else { return }
        map.getLabelManager().addPoiStyle(PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle: PoiIconStyle(symbol: img, anchorPoint: anchor(img.size)), level: 0)]))
        styles.insert(id)
    }

    private func layer(_ id: String) -> LabelLayer? { map?.getLabelManager().getLabelLayer(layerID: id) }

    // 보여줄 목록과 지금 떠 있는 목록을 비교해 추가·삭제·스타일 변경만
    private func sync(layer id: String, shown: inout [String: String], want: [(id: String, style: String, coord: CLLocationCoordinate2D)], clickable: Bool) {
        guard let layer = layer(id) else { return }
        let wantIDs = Set(want.map(\.id))
        let gone = shown.keys.filter { !wantIDs.contains($0) }
        if !gone.isEmpty { layer.removePois(poiIDs: gone); gone.forEach { shown[$0] = nil } }
        for w in want {
            if let cur = shown[w.id] {
                if cur != w.style { layer.getPoi(poiID: w.id)?.changeStyle(styleID: w.style); shown[w.id] = w.style }
            } else {
                let o = PoiOptions(styleID: w.style, poiID: w.id)
                o.clickable = clickable
                layer.addPoi(option: o, at: MapPoint(longitude: w.coord.longitude, latitude: w.coord.latitude))?.show()
                shown[w.id] = w.style
            }
        }
    }

    func setStations(_ list: [Station], selected: String?, dimmed: Bool) {
        guard map != nil else { return }
        var want: [(String, String, CLLocationCoordinate2D)] = []
        for s in list {
            let sel = s.id == selected
            let id = "st-\(s.bikes)-\(sel ? 1 : 0)-\(dimmed ? 1 : 0)"
            style(id) { Self.render(StationMarker(bikes: s.bikes, selected: sel).opacity(dimmed ? 0.4 : 1).padding(8)) }
            want.append((s.id, id, s.coordinate))
        }
        sync(layer: "stations", shown: &shownStations, want: want, clickable: true)
    }

    func setClusters(_ list: [StationCluster]) {
        guard map != nil else { return }
        var want: [(String, String, CLLocationCoordinate2D)] = []
        for g in list {
            let id = "cl-\(g.count)"
            style(id) { Self.render(ClusterBubble(count: g.count).padding(8)) }
            want.append((g.id, id, g.coordinate))
        }
        sync(layer: "clusters", shown: &shownClusters, want: want, clickable: true)
    }

    func setMyLocation(_ c: CLLocationCoordinate2D?, heading: Double?) {
        me = (c, heading)
        applyMe()
    }

    // 좌표·방향이 실제로 바뀐 경우에만 갱신. 카메라 틱(50ms)마다 position을 다시 쓰면 SDK가 지웠다 그려서 깜빡임
    private func applyMe() {
        guard let layer = layer("me") else { return }
        guard let c = me.coord, !hideMe else {
            if mePois.dot != nil { layer.clearAllItems(); mePois = (nil, nil); meApplied = (nil, nil, false) }
            return
        }
        let p = MapPoint(longitude: c.longitude, latitude: c.latitude)
        style("me-dot") { Self.render(MyLocationDot().padding(4)) }
        style("me-cone") { Self.render(HeadingCone()) }
        if mePois.dot == nil {
            let cone = PoiOptions(styleID: "me-cone", poiID: "cone"); cone.rank = 0
            let dot = PoiOptions(styleID: "me-dot", poiID: "dot"); dot.rank = 1
            mePois.cone = layer.addPoi(option: cone, at: p)
            mePois.dot = layer.addPoi(option: dot, at: p)
            mePois.dot?.show()
            meApplied.coord = c
        } else if let old = meApplied.coord, old.distance(to: c) < 0.5 {
            // 제자리, 건너뜀
        } else {
            mePois.dot?.moveAt(p, duration: 0)
            mePois.cone?.moveAt(p, duration: 0)
            meApplied.coord = c
        }
        if let h = me.heading {
            let o = h * .pi / 180 - rotation
            if meApplied.orient == nil || abs(meApplied.orient! - o) > 0.01 {
                mePois.cone?.orientation = o
                meApplied.orient = o
            }
            if !meApplied.coneShown { mePois.cone?.show(); meApplied.coneShown = true }
        } else if meApplied.coneShown {
            mePois.cone?.hide(); meApplied.coneShown = false
        }
    }

    func setDroppedPin(_ c: CLLocationCoordinate2D?) {
        guard let layer = layer("pins") else { pendingPin = .some(c); return }
        layer.clearAllItems()
        guard let c else { return }
        style("pin-orange", CGPoint(x: 0.5, y: (8 + 50) / (56 + 16))) { Self.render(DropPinShape(color: .pinOrange).padding(8)) }
        layer.addPoi(option: PoiOptions(styleID: "pin-orange", poiID: "pin"), at: MapPoint(longitude: c.longitude, latitude: c.latitude))?.show()
    }

    enum TripView: Int { case all, rent, ret }

    func setTrip(_ t: Trip?) {
        guard let map, layer("tags") != nil, map.getRouteManager().getRouteLayer(layerID: "route") != nil else { pendingTrip = .some(t); return }
        trip = t
        hideMe = t?.near == .same
        applyMe()
        guard t != nil else { layer("tags")?.clearAllItems(); map.getRouteManager().getRouteLayer(layerID: "route")?.clearAllRoutes(); routeSeq = 0; return }
        setTripView(view, animated: false)
    }

    // 라벨 방향. 전체: 대여·반납 라벨이 서로 바깥쪽 (안 겹치게) / 대여·반납 보기: 화면 안쪽 (가장자리에 안 잘리게)
    private func labelSides(_ t: Trip, _ v: TripView) -> (rentLeft: Bool, retLeft: Bool) {
        let s = t.start.coordinate, e = t.end.coordinate
        switch v {
        case .all: return (s.longitude <= e.longitude, e.longitude < s.longitude)
        case .rent: return (t.origin.coordinate.longitude < s.longitude, e.longitude < s.longitude)
        case .ret: return (s.longitude < e.longitude, t.destination.coordinate.longitude < e.longitude)
        }
    }

    private func placeMarkers(_ t: Trip, _ v: TripView) -> (rentW: CGFloat, retW: CGFloat, sides: (rentLeft: Bool, retLeft: Bool)) {
        guard let tags = layer("tags") else { return (0, 0, (false, false)) }
        tags.clearAllItems()
        let sides = labelSides(t, v)
        let pad = LabeledPin<RentPin>.pad
        func add(_ id: String, _ st: String, _ c: CLLocationCoordinate2D, rank: Int) {
            let o = PoiOptions(styleID: st, poiID: id); o.rank = rank
            tags.addPoi(option: o, at: MapPoint(longitude: c.longitude, latitude: c.latitude))?.show()
        }
        func pinStyle<P: View>(_ id: String, pin: P, size: CGSize, tip: CGPoint, head: CGFloat, label: PinLabel, left: Bool) {
            style(id, anchor: { s in CGPoint(x: (left ? s.width - pad - (size.width - tip.x) : pad + tip.x) / s.width, y: (pad + tip.y) / s.height) }) {
                Self.render(LabeledPin(pin: pin, pinSize: size, headCenterY: head, label: label, labelOnLeft: left))
            }
        }
        // 피그마 C1: 핀 머리 중심 대여 (22,20), 반납 (21,19), 복합 (24,24)
        // 전체 보기는 실제 경로가 넓으면 이름 라벨이 화면 끝에 잘려서 칩만 (이름은 시트 카드에)
        let compact = v == .all
        let rentLabel = PinLabel(chip: "대여", chipColor: Token.Brand.green, name: compact ? "" : t.start.name, bikes: t.start.bikes)
        let retLabel = PinLabel(chip: "반납", chipColor: Token.Marker.returnChip, name: compact ? "" : t.end.name)
        let same = t.near == .same
        let rentID = "\(same ? "combo" : "rent")-\(t.start.id)-\(t.start.bikes)-\(sides.rentLeft)-\(compact)"
        if same { pinStyle(rentID, pin: ComboMarker(), size: ComboMarker.size, tip: .init(x: 24, y: 24), head: 24, label: rentLabel, left: sides.rentLeft) }
        else { pinStyle(rentID, pin: RentPin(), size: RentPin.size, tip: RentPin.tip, head: 20, label: rentLabel, left: sides.rentLeft) }
        let retID = "ret-\(t.end.id)-\(sides.retLeft)-\(compact)"
        pinStyle(retID, pin: ReturnPin(), size: ReturnPin.size, tip: ReturnPin.tip, head: 19, label: retLabel, left: sides.retLeft)
        add("start", rentID, t.start.coordinate, rank: 3)
        add("end", retID, t.end.coordinate, rank: 2)
        style("dest-dot") { Self.render(DestDot().padding(6)) }
        add("dest", "dest-dot", t.destination.coordinate, rank: 1)
        // 출발지를 검색으로 정했으면 내 위치 점 대신 작은 점 (피그마에 없는 경우, 도착 점과 같은 모양 진회색)
        if t.origin.name != "내 위치" {
            style("origin-dot") { Self.render(DestDot(color: Token.Text.primary).padding(6)) }
            add("origin", "origin-dot", t.origin.coordinate, rank: 1)
        }
        let w = { (l: PinLabel) -> CGFloat in
            let key = "\(l.chip)|\(l.name)|\(l.bikes ?? -1)"
            if let c = self.labelWidths[key] { return c }
            let v = (Self.render(l)?.size.width ?? 200) + 10
            self.labelWidths[key] = v
            return v
        }
        return (w(rentLabel), w(retLabel), sides)
    }

    // 구간마다 경로를 따로 그려 겹칠 때 위아래 순서를 정함
    // 전체: 자전거가 위. 대여/반납: 선택 도보가 위, 나머지 비활성
    func setTripView(_ v: TripView, animated: Bool = true) {
        view = v
        guard let map, let t = trip else { return }
        labels = placeMarkers(t, v)
        drawRoutes()
        refit(animated: animated)
    }

    @ObservationIgnored private var labels: (rentW: CGFloat, retW: CGFloat, sides: (rentLeft: Bool, retLeft: Bool)) = (0, 0, (false, false))

    // 카메라만 다시 맞춤 (시트 접고 펼 때). 마커·경로는 그대로
    func refit(animated: Bool = true) {
        guard let map, let t = trip else { return }
        let v = view
        let fitPts: [CLLocationCoordinate2D] = switch v {
        case .all: t.allPoints
        case .rent: t.near == .far ? t.walkTo.path + [t.start.coordinate] : [t.origin.coordinate, t.start.coordinate]
        case .ret: t.walkFrom.path + [t.end.coordinate]
        }
        // 전체 보기는 라벨이 바깥쪽이라 그 폭만큼 여백 추가
        var m = margins
        if v == .all {
            let left = max(labels.sides.rentLeft ? labels.rentW : 0, labels.sides.retLeft ? labels.retW : 0)
            let right = max(labels.sides.rentLeft ? 0 : labels.rentW, labels.sides.retLeft ? 0 : labels.retW)
            // 양쪽 합이 화면 폭 - 140을 넘으면 맞출 영역이 없어 전국 지도로 축소됨 → 비율로 줄임
            let room = max(0, (map.viewRect.width - 140) - (m.left + m.right))
            let want = left + right
            let k = want > room && want > 0 ? room / want : 1
            m.left += left * k; m.right += right * k
        }
        map.setMargins(m)
        fit(fitPts, animated: animated)
    }

    // 도보 막대 길이는 화면 기준 10pt + 빈칸 6pt(선택 14 + 7). 줌이 바뀌면 다시 자름
    @ObservationIgnored private var dashZoom = -1

    private func drawRoutes() {
        guard let map, let t = trip, let route = map.getRouteManager().getRouteLayer(layerID: "route") else { return }
        dashZoom = map.zoomLevel
        let r = map.viewRect
        let mPerPt = r.height > 0 ? (region?.span.latitudeDelta ?? 0.02) * 111_000 / r.height : 1
        enum Walk { case normal, selected, inactive }
        let (to, from): (Walk, Walk) = switch view { case .all: (.normal, .normal); case .rent: (.selected, .inactive); case .ret: (.inactive, .selected) }
        let z: (bike: Int, to: Int, from: Int) = switch view { case .all: (20, 10, 10); case .rent: (20, 30, 0); case .ret: (20, 0, 30) }
        let old = (route.getAllRoutes() ?? []).map(\.routeID)
        routeSeq += 1
        var n = 0
        func add(_ segs: [RouteSegment], z: Int) {
            n += 1
            let o = RouteOptions(routeID: "trip-\(routeSeq)-\(n)", styleID: "trip", zOrder: z)
            o.segments = segs
            route.addRoute(option: o)?.show()
        }
        let pts = { (c: [CLLocationCoordinate2D]) in c.map { MapPoint(longitude: $0.longitude, latitude: $0.latitude) } }
        add([RouteSegment(points: pts(t.bike.path), styleIndex: view == .all ? 0 : 1)], z: z.bike)
        func walkLeg(_ leg: Leg, _ w: Walk, _ z: Int) {
            let sel = w == .selected
            let (dash, gap): (Double, Double) = sel ? (14, 7) : (10, 6)
            if w != .inactive { add([RouteSegment(points: pts(leg.path), styleIndex: sel ? 7 : 6)], z: z) }
            let pieces = Self.dashes(leg.path, dash: dash * mPerPt, gap: gap * mPerPt)
            let style: UInt = switch w { case .normal: 2; case .selected: 3; case .inactive: 4 }
            add(pieces.map { RouteSegment(points: pts($0.points), styleIndex: $0.on ? style : 5) }, z: z + 1)
        }
        if t.near == .far { walkLeg(t.walkTo, to, z.to) } // 50m 이하는 도보선 없음
        walkLeg(t.walkFrom, from, z.from)
        // 같은 ID로 지우고 바로 다시 넣으면 삭제 전이라 추가가 실패함 → 새 ID로 넣고 옛것 제거
        if !old.isEmpty { route.removeRoutes(routeIDs: old) }
    }

    // 경로를 막대(on)와 빈칸(off) 조각으로. 길이는 m
    nonisolated static func dashes(_ path: [CLLocationCoordinate2D], dash: Double, gap: Double) -> [(points: [CLLocationCoordinate2D], on: Bool)] {
        guard path.count > 1, dash > 0, gap > 0 else { return [(path, true)] }
        var out: [(points: [CLLocationCoordinate2D], on: Bool)] = []
        var cur = [path[0]], on = true, left = dash
        for i in 1..<path.count {
            var a = path[i - 1]
            let b = path[i]
            var seg = a.distance(to: b)
            while seg > left {
                let f = left / seg
                let m = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * f, longitude: a.longitude + (b.longitude - a.longitude) * f)
                cur.append(m); out.append((cur, on))
                on.toggle(); cur = [m]; seg -= left; a = m; left = on ? dash : gap
            }
            cur.append(b); left -= seg
        }
        if cur.count > 1 { out.append((cur, on)) }
        return out
    }

    // MARK: 이미지

    static func dot(_ d: CGFloat, _ color: UIColor) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 2
        return UIGraphicsImageRenderer(size: .init(width: d, height: d), format: f).image { ctx in
            color.setFill(); ctx.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: d, height: d))
        }
    }

    // 경로 방향 = 이미지 가로축 (가로로 긴 캡슐)
    static func dash(_ len: CGFloat, _ w: CGFloat, _ color: UIColor) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 2
        return UIGraphicsImageRenderer(size: .init(width: len, height: w), format: f).image { _ in
            color.setFill(); UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: len, height: w), cornerRadius: w / 2).fill()
        }
    }

    // 피그마 쉐브론 6x3.2 (8x5 캔버스). 진행 방향 = 이미지 위쪽
    static func chevron(_ color: UIColor, _ w: CGFloat) -> UIImage {
        let f = UIGraphicsImageRendererFormat(); f.scale = 2
        return UIGraphicsImageRenderer(size: .init(width: 8, height: 5), format: f).image { _ in
            let p = UIBezierPath()
            p.move(to: .init(x: 0.9, y: 4.1)); p.addLine(to: .init(x: 4, y: 0.9)); p.addLine(to: .init(x: 7.1, y: 4.1))
            p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round
            color.setStroke(); p.stroke()
        }
    }

    static func render<V: View>(_ v: V) -> UIImage? {
        let r = ImageRenderer(content: v)
        r.scale = 2 // SDK는 이미지 픽셀을 @2x 기준으로 그려서 화면 배율로 구우면 1.5배 커짐
        return r.uiImage
    }
}

// 내 위치 점. 피그마 "내 위치": #3182F6 16, 흰 테두리 3, halo 40 @0.2. 방향 부채꼴은 별도 POI
struct MyLocationDot: View {
    var body: some View {
        ZStack {
            Circle().fill(Token.Marker.location.opacity(0.2)).frame(width: 40, height: 40)
            Circle().fill(Token.Marker.location).frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(color: .black.opacity(0.25), radius: 2, y: 1)
        }
    }
}

struct HeadingCone: View {
    var body: some View {
        Cone().fill(RadialGradient(colors: [Token.Marker.location.opacity(0.35), Token.Marker.location.opacity(0)], center: .center, startRadius: 6, endRadius: 40))
            .frame(width: 80, height: 80)
    }

    private struct Cone: SwiftUI.Shape {
        func path(in r: CGRect) -> Path {
            Path { p in
                let c = CGPoint(x: r.midX, y: r.midY)
                p.move(to: c)
                p.addArc(center: c, radius: r.width / 2, startAngle: .degrees(-90 - 30), endAngle: .degrees(-90 + 30), clockwise: false)
                p.closeSubpath()
            }
        }
    }
}
