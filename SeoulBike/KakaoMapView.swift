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
    @ObservationIgnored private var pendingPin: CLLocationCoordinate2D??

    func attach(_ map: KakaoMap) {
        self.map = map
        let lm = map.getLabelManager()
        // 내 위치가 대여소 마커에 가려지지 않게 zOrder 크게 벌림
        for (id, z) in [("clusters", 10), ("stations", 20), ("tags", 30), ("pins", 40), ("me", 100)] {
            _ = lm.addLabelLayer(option: LabelLayerOptions(layerID: id, competitionType: .none, competitionUnit: .symbolFirst, orderType: .rank, zOrder: z))
        }
        let rm = map.getRouteManager()
        _ = rm.addRouteLayer(layerID: "route", zOrder: 0)
        let set = RouteStyleSet(styleID: "trip")
        set.addPattern(RoutePattern(pattern: Self.dotImage, distance: 12, symbol: nil, pinStart: false, pinEnd: false))
        set.addStyle(RouteStyle(styles: [PerLevelRouteStyle(width: 6, color: UIColor(Color.grey600), level: 0, patternIndex: 0)]))
        set.addStyle(RouteStyle(styles: [PerLevelRouteStyle(width: 8, color: UIColor(Color.brand), strokeWidth: 2, strokeColor: .white, level: 0)]))
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
        center = .init(latitude: c.latitude, longitude: c.longitude)
        rotation = map.rotationAngle
        let region = MKCoordinateRegion(center: center!, span: .init(latitudeDelta: abs(a.latitude - b.latitude), longitudeDelta: abs(a.longitude - b.longitude)))
        self.region = region
        applyMe()
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

    func fit(_ points: [CLLocationCoordinate2D]) {
        guard let map, !points.isEmpty else { return }
        let u = CameraUpdate.make(area: AreaRect(points: points.map { MapPoint(longitude: $0.longitude, latitude: $0.latitude) }), levelLimit: 16)
        map.animateCamera(cameraUpdate: u, options: CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 500))
    }

    func resetNorth() {
        map?.resetCameraOrientation(CameraAnimationOptions(autoElevation: false, consecutive: false, durationInMillis: 300))
    }

    func setMargins(_ m: UIEdgeInsets) { margins = m; map?.setMargins(m) }

    // MARK: 마커

    private func style(_ id: String, _ anchor: CGPoint = .init(x: 0.5, y: 0.5), _ make: () -> UIImage?) {
        guard !styles.contains(id), let map, let img = make() else { return }
        map.getLabelManager().addPoiStyle(PoiStyle(styleID: id, styles: [PerLevelPoiStyle(iconStyle: PoiIconStyle(symbol: img, anchorPoint: anchor), level: 0)]))
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
        guard let c = me.coord else {
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

    func setTrip(_ t: Trip?) {
        guard let map, let tags = layer("tags"), let route = map.getRouteManager().getRouteLayer(layerID: "route") else { pendingTrip = .some(t); return }
        tags.clearAllItems()
        route.clearAllRoutes()
        guard let t else { return }
        let seg = { (leg: Leg, idx: UInt) in RouteSegment(points: leg.path.map { MapPoint(longitude: $0.longitude, latitude: $0.latitude) }, styleIndex: idx) }
        let o = RouteOptions(routeID: "trip", styleID: "trip", zOrder: 0)
        o.segments = [seg(t.walkTo, 0), seg(t.bike, 1), seg(t.walkFrom, 0)]
        route.addRoute(option: o)?.show()
        style("tag-start") { Self.render(MapTag(text: "대여").padding(8)) }
        style("tag-end") { Self.render(MapTag(text: "반납").padding(8)) }
        style("dest-dot") { Self.render(Circle().fill(Color.pinOrange).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 3)).padding(4)) }
        for (id, st, c) in [("start", "tag-start", t.start.coordinate), ("end", "tag-end", t.end.coordinate), ("dest", "dest-dot", t.destination.coordinate)] {
            tags.addPoi(option: PoiOptions(styleID: st, poiID: id), at: MapPoint(longitude: c.longitude, latitude: c.latitude))?.show()
        }
    }

    // MARK: 이미지

    static func render<V: View>(_ v: V) -> UIImage? {
        let r = ImageRenderer(content: v)
        r.scale = 2 // SDK는 이미지 픽셀을 @2x 기준으로 그려서 화면 배율로 구우면 1.5배 커짐
        return r.uiImage
    }

    static let dotImage: UIImage = {
        let s = CGSize(width: 6, height: 6)
        return UIGraphicsImageRenderer(size: s).image { ctx in
            UIColor(Color.grey600).setFill()
            ctx.cgContext.fillEllipse(in: CGRect(origin: .zero, size: s))
        }
    }()
}

// 내 위치 점. 방향 부채꼴은 별도 POI(HeadingCone)로 올려 지도 회전에 맞춰 돌림
struct MyLocationDot: View {
    var body: some View {
        ZStack {
            Circle().fill(.white).frame(width: 22, height: 22).shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Circle().fill(Color.brand).frame(width: 14, height: 14)
        }
    }
}

struct HeadingCone: View {
    var body: some View {
        Cone().fill(RadialGradient(colors: [Color.brand.opacity(0.35), Color.brand.opacity(0)], center: .center, startRadius: 6, endRadius: 40))
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
