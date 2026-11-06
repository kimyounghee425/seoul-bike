import MapKit
import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var phase
    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.path) {
            HomeView()
                .navigationDestination(for: Screen.self) { s in
                    Group {
                        switch s {
                        case .search(let f): SearchView(focus: f)
                        case .pick(let f): MapPickView(field: f)
                        case .result: ResultView()
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            await model.loadStations()
            #if DEBUG
            try? await Task.sleep(for: .seconds(1)) // 대여소 다 받고 내비 스택 준비 후
            demo()
            #endif
        }
        .onChange(of: phase) { _, p in if p == .active { Task { await model.refreshIfStale() } } }
        .onAppear {
            model.location.request()
        }
    }

    #if DEBUG
    // 스크린샷 확인용: simctl launch ... -demo result|search|pickOrigin|pickDest
    private func demo() {
        let forest = Place(name: "서울숲", address: "성동구 뚝섬로 273", lat: 37.5443, lng: 127.0376)
        switch UserDefaults.standard.string(forKey: "demo") {
        case "result": model.destination = forest; model.path = [.result]
        case "far": model.destination = Place(name: "가평 자라섬", address: "", lat: 37.8205, lng: 127.5194); model.path = [.result]
        case "search": model.path = [.search(focus: .destination)]
        case "pickOrigin": model.path = [.pick(.origin)]
        case "pickDest": model.path = [.pick(.destination)]
        default: break
        }
    }
    #endif
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var map = MapHandle()
    @State private var region: MKCoordinateRegion?
    @State private var selected: Station?
    @State private var centered = false
    @State private var pressed: CLLocationCoordinate2D?
    @State private var pressedPlace: Place?

    var body: some View {
        KakaoMapView(handle: map)
        .ignoresSafeArea()
        .onAppear {
            map.onCamera = { r, final in
                if final { region = r; model.homeRegion = r } else if movedEnough(region, r) { region = r } // 움직이는 중에도 미리 갱신
            }
            // 지도 꾹 누르기 → 그 위치를 출발·도착으로 (손 떼기 전에 바로)
            map.onLongPress = { c in
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                withAnimation(.snappy) { selected = nil; pressed = c; pressedPlace = nil }
                Task { pressedPlace = try? await Kakao.address(at: c) }
            }
            map.onStationTap = { id in
                guard let s = model.stations.first(where: { $0.id == id }) else { return }
                withAnimation(.snappy) { pressed = nil; selected = s }
            }
            map.onClusterTap = { c in map.move(to: c, zoom: 14) }
        }
        .onChange(of: markerKey, initial: true) { _, _ in
            map.setClusters(stationClusters(model.stations, in: region))
            map.setStations(visibleStations(model.stations, in: region), selected: selected?.id, dimmed: model.stationsOffline)
        }
        .onChange(of: pressed.map { "\($0.latitude),\($0.longitude)" }, initial: true) { _, _ in map.setDroppedPin(pressed) }
        .onChange(of: locationKey, initial: true) { _, _ in map.setMyLocation(model.location.coordinate, heading: model.location.heading) }
        #if DEBUG
        .task { // 스크린샷 확인용: -demo zoom → 축소 묶음 화면
            guard UserDefaults.standard.string(forKey: "demo") == "zoom" else { return }
            try? await Task.sleep(for: .seconds(2))
            map.move(to: .init(latitude: 37.55, longitude: 127.0), zoom: 12)
        }
        #endif
        // 위치가 지도보다 늦게 잡히면 기본 위치(시청)에 머무르는 문제, 첫 위치 수신 시 한 번 이동
        .onChange(of: model.location.coordinate == nil, initial: true) { _, missing in
            guard !missing, !centered, let c = model.location.coordinate else { return }
            centered = true
            map.move(to: c, zoom: 15, animated: false)
        }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 8) {
                Button { model.path = [.search(focus: .destination)] } label: { SearchBar() }
                if model.location.denied { Banner(text: "위치 권한이 꺼져 있어요", action: "설정", onTap: openSettings) }
                if model.stationsFailed {
                    Banner(text: model.stationsOffline ? "인터넷 연결이 끊겼어요" : "대여소 정보를 못 불러왔어요", action: "다시 시도") {
                        Task { await model.loadStations() }
                    }
                }
                HStack { Spacer(); CompassButton(map: map) }
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 16) {
                HStack(alignment: .bottom) {
                    RefreshChip()
                    Spacer()
                    LocateButton(map: map, location: model.location)
                }
                .padding(.horizontal, 16).padding(.bottom, selected == nil && pressed == nil ? 8 : 0)
                bottomPanel
            }
        }
    }

    // 마커를 다시 고를 조건: 지도 영역, 대여소 갱신, 선택, 오프라인
    private var markerKey: String {
        "\(region.map { "\($0.center.latitude),\($0.center.longitude),\($0.span.latitudeDelta)" } ?? "")|\(model.stationsUpdatedAt?.timeIntervalSince1970 ?? 0)|\(selected?.id ?? "")|\(model.stationsOffline)"
    }

    private var locationKey: String {
        "\(model.location.coordinate?.latitude ?? 0),\(model.location.coordinate?.longitude ?? 0),\(model.location.heading ?? -1)"
    }

    // 대여소 탭, 꾹 누르기 시트. 칩과 현위치 버튼은 그 위에 붙어서 같이 올라감
    @ViewBuilder private var bottomPanel: some View {
            if let s = selected {
                PlacePanel(title: s.name, detail: stationDetail(s),
                           place: Place(name: s.name, address: "따릉이 대여소", lat: s.coordinate.latitude, lng: s.coordinate.longitude)) { selected = nil }
            } else if pressed != nil {
                PlacePanel(title: pressedPlace?.name ?? "위치를 찾는 중…",
                           detail: Text(pressedPlace?.address.isEmpty == false ? pressedPlace!.address : " "),
                           place: pressedPlace) { pressed = nil }
            }
    }

    // "120m 거리에 자전거 8대 남았어요"
    private func stationDetail(_ s: Station) -> Text {
        let d = model.location.coordinate.map { distanceText($0.distance(to: s.coordinate)) + " 거리에 " } ?? ""
        return Text(d + "자전거 ") + Text.em("\(s.bikes)대") + Text(" 남았어요")
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}

private struct SearchBar: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 17, weight: .semibold))
            Text("어디로 갈까요?")
            Spacer()
        }
        .font(.system(size: 16)).foregroundStyle(Color.grey500)
        .padding(.horizontal, 18).frame(height: 52)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.1), radius: 10, y: 2)
    }
}

private struct RefreshChip: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Button { Task { await model.loadStations() } } label: {
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                HStack(spacing: 6) {
                    if model.stationsLoading { ProgressView().controlSize(.mini) }
                    else { Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .bold)) }
                    Text("대여소 업데이트")
                    Text(model.stationsLoading ? "불러오는 중" : agoText(model.stationsUpdatedAt, now: ctx.date))
                        .foregroundStyle(Color.grey500)
                }
            }
            .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.grey700)
            .padding(.horizontal, 14).frame(height: 36)
            .background(Capsule().fill(.white)).shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
        .disabled(model.stationsLoading)
    }
}

// 지금 배율과 방향 그대로 내 위치로 이동. 북쪽 정렬은 나침반 버튼 담당
struct LocateButton: View {
    let map: MapHandle
    let location: LocationService

    var body: some View {
        let c = location.coordinate
        let centered = c != nil && map.center.map { $0.distance(to: c!) < 30 } == true
        RoundButton(systemName: centered ? "location.fill" : "location") {
            guard let c else { location.request(); return }
            map.move(to: c)
        }
    }
}

// 대여소 탭·지도 꾹 누르기 공용 시트: 제목, 보조 문구, [여기로 도착] [여기서 출발]
private struct PlacePanel: View {
    @Environment(AppModel.self) private var model
    let title: String
    let detail: Text
    let place: Place?
    let close: () -> Void

    var body: some View {
        BottomPanel {
            HStack(alignment: .top) {
                Text(title).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.grey900)
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.grey500)
                        .frame(width: 32, height: 32)
                }
            }
            detail.font(.system(size: 15)).foregroundStyle(Color.grey500).padding(.top, 6)
            HStack(spacing: 8) {
                PrimaryButton(title: "여기로 도착", gray: true) { go(.destination) }
                PrimaryButton(title: "여기서 출발") { go(.origin) }
            }
            .padding(.top, 24)
            .disabled(place == nil)
        }
        .gesture(DragGesture().onEnded { if $0.translation.height > 60 { close() } })
    }

    private func go(_ f: Field) {
        guard let place else { return }
        model.set(f, place)
        close()
        model.proceed()
    }
}
