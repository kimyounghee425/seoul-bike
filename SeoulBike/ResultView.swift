import MapKit
import SwiftUI

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @State private var map = MapHandle()
    @State private var trip: Trip?
    @State private var error: Trip.PlanError?
    @State private var expanded = true
    @State private var view = 0 // 0 전체 1 대여 2 반납

    var body: some View {
        KakaoMapView(handle: map)
        .ignoresSafeArea()
        .onAppear {
            // 위 헤더, 아래 시트에 가리지 않게 경로 맞춤 여백
            map.setMargins(margins)
            if let c = model.originPlace?.coordinate ?? model.location.coordinate { map.move(to: c, zoom: 15, animated: false) }
        }
        .onChange(of: locationKey, initial: true) { _, _ in map.setMyLocation(model.location.coordinate, heading: model.location.heading) }
        .onChange(of: map.ready) { _, ready in if ready, let t = trip { map.setTrip(t) } }
        .onChange(of: view) { _, v in map.setTripView(.init(rawValue: v) ?? .all) }
        // 시트를 접으면 지도가 넓어지니 경로를 다시 맞춤
        .onChange(of: expanded) { _, _ in map.setMargins(margins); map.setTripView(map.view) }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                BackPill()
                // 출발·도착을 누르면 검색 화면에서 그 칸을 바로 고칠 수 있게
                HStack(spacing: 6) {
                    Button(model.origin?.name ?? "내 위치") { model.path.append(.search(focus: .origin)) }
                    Text("→")
                    Button(model.destination?.name ?? "") { model.path.append(.search(focus: .destination)) }
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.Text.primary).lineLimit(1)
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(.white)).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                CompassButton(map: map)
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                HStack(alignment: .bottom) {
                    if trip != nil { SegmentControl(items: ["전체", "대여", "반납"], selection: $view) }
                    Spacer()
                    LocateButton(map: map, location: model.location)
                }
                .padding(.horizontal, 16)
                panel
            }
        }
        // 출발지나 도착지가 바뀌어 돌아오면 다시 찾음
        .task(id: routeKey) { await plan() }
        #if DEBUG
        .task { // 스크린샷용: -view 1|2
            try? await Task.sleep(for: .seconds(4))
            if let v = UserDefaults.standard.string(forKey: "view").flatMap(Int.init) { view = v }
        }
        #endif
    }

    // 위 헤더, 아래 시트에 가리지 않게 경로 맞춤 여백. 라벨 폭은 MapHandle이 뷰별로 더함
    private var margins: UIEdgeInsets { UIEdgeInsets(top: 120, left: 40, bottom: expanded ? 490 : 230, right: 40) }

    private var routeKey: String {
        let o = model.origin.map { "\($0.lat),\($0.lng)" } ?? "me"
        return o + "|" + (model.destination.map { "\($0.lat),\($0.lng)" } ?? "")
    }

    private var locationKey: String {
        "\(model.location.coordinate?.latitude ?? 0),\(model.location.coordinate?.longitude ?? 0),\(model.location.heading ?? -1)"
    }

    @ViewBuilder private var panel: some View {
        BottomPanel {
            if let t = trip {
                // 피그마 "결과 화면 최종": 제목 블록 위 20, 제목 26 bold, 보조 14 regular secondary, 간격 2
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(t.totalMinutes)분 걸려요").font(.system(size: 26, weight: .bold)).foregroundStyle(Token.Text.primary)
                    Text("걷기 \(t.walkMinutes)분 포함").font(.system(size: 14)).foregroundStyle(Token.Text.secondary)
                } // 핸들 아래 20은 BottomPanel이 줌
                if expanded {
                    VStack(spacing: 10) {
                        PlaceCard(label: "빌릴 곳", name: t.start.name, selected: view == 1) {
                            Fact(icon: .walk, text: t.near == .far ? "걸어서 \(t.walkTo.minutes)분" : "바로 앞이에요")
                            Fact(icon: .bike, text: "자전거 \(t.start.bikes)대", iconColor: Token.Brand.green, textColor: Token.Brand.greenDeep)
                        } action: { view = view == 1 ? 0 : 1 }
                        PlaceCard(label: "반납할 곳", name: t.end.name, selected: view == 2) {
                            Fact(icon: .walk, text: "목적지까지 걸어서 \(t.walkFrom.minutes)분")
                        } action: { view = view == 2 ? 0 : 2 }
                    }
                    .padding(.top, 16)
                    HStack(spacing: 6) {
                        Fact(icon: .bike, text: "자전거 \(t.bike.minutes)분,", iconColor: Token.Text.secondary, textColor: Token.Text.secondary)
                        Text(t.passLine).font(.system(size: 14)).foregroundStyle(Token.Text.secondary)
                    }
                    .padding(.top, 14).padding(.bottom, 2).padding(.leading, 4)
                    .transition(.opacity)
                }
                PrimaryButton(title: "따릉이 앱 열기") { openBikeSeoul() }.padding(.top, 16)
            } else if let error {
                Text(error.title).font(.system(size: 22, weight: .bold)).foregroundStyle(Color.grey900)
                Text(error.detail).font(.system(size: 15)).foregroundStyle(Color.grey500).lineSpacing(3).padding(.top, 6)
                PrimaryButton(title: error.button) { handle(error) }.padding(.top, 24)
                if error == .noLocation {
                    Button("위치 권한 켜기") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                    .font(.system(size: 15)).foregroundStyle(Color.grey600).frame(maxWidth: .infinity).padding(.top, 16)
                }
            } else {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("경로를 찾고 있어요").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.grey700)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        // 손잡이 탭 또는 위아래로 끌어서 접기/펼치기, 접으면 제목·요약·버튼만
        .contentShape(Rectangle())
        .onTapGesture { if trip != nil { withAnimation(.snappy) { expanded.toggle() } } }
        .gesture(DragGesture(minimumDistance: 20).onEnded { v in
            guard trip != nil else { return }
            withAnimation(.snappy) { expanded = v.translation.height < 0 }
        })
    }

    private func handle(_ e: Trip.PlanError) {
        switch e {
        case .noLocation, .farFromOrigin: model.path = [.search(focus: .origin)]
        case .farFromDestination, .tooClose: model.path = [.search(focus: .destination)]
        case .routeFailed, .offline: Task { await plan() }
        }
    }

    private func plan() async {
        error = nil
        trip = nil
        if model.stations.isEmpty { await model.loadStations() }
        // 위치 권한은 있는데 아직 첫 위치를 못 받았으면 잠깐 기다림
        for _ in 0..<6 where model.origin == nil && model.location.coordinate == nil && !model.location.denied {
            try? await Task.sleep(for: .milliseconds(500))
        }
        do {
            trip = try await Trip.plan(model)
            if let t = trip { view = 0; map.setTrip(t) }
        } catch {
            self.error = Trip.PlanError.from(error)
            map.setTrip(nil)
            if let c = model.location.coordinate { map.move(to: c, zoom: 15) }
        }
    }
}

// 따릉이 공식 앱 스킴. 유니버설 링크·화면별 딥링크 없음(2026-11 확인), 앱 실행까지만
func openBikeSeoul() {
    UIApplication.shared.open(URL(string: "bikeseoul://action")!) { ok in
        if !ok { UIApplication.shared.open(URL(string: "https://apps.apple.com/kr/app/id1037272004")!) }
    }
}
