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
                Pill(text: "\(model.originPlace?.name ?? "내 위치") → \(model.destination?.name ?? "")")
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
        .task { await plan() }
        #if DEBUG
        .task { // 스크린샷용: -view 1|2
            try? await Task.sleep(for: .seconds(4))
            if let v = UserDefaults.standard.string(forKey: "view").flatMap(Int.init) { view = v }
        }
        #endif
    }

    // 위 헤더, 아래 시트에 가리지 않게 경로 맞춤 여백. 오른쪽은 대여소 라벨이 뻗을 자리
    private var margins: UIEdgeInsets { UIEdgeInsets(top: 120, left: 40, bottom: expanded ? 490 : 230, right: 110) }

    private var locationKey: String {
        "\(model.location.coordinate?.latitude ?? 0),\(model.location.coordinate?.longitude ?? 0),\(model.location.heading ?? -1)"
    }

    @ViewBuilder private var panel: some View {
        BottomPanel {
            if let t = trip {
                Text("\(t.totalMinutes)분 걸려요").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.grey900)
                Text("걷기 \(t.walkMinutes)분 포함").font(.system(size: 14)).foregroundStyle(Color.grey500).padding(.top, 4)
                if expanded {
                    VStack(spacing: 10) {
                        PlaceCard(label: "빌릴 곳", name: t.start.name,
                                  line: Text(Image(systemName: "figure.walk")) + Text(" 걸어서 \(t.walkTo.minutes)분   ") + Text(Image(systemName: "bicycle")) + Text(" 자전거 ") + Text.em("\(t.start.bikes)대"),
                                  selected: view == 1) { view = view == 1 ? 0 : 1 }
                        PlaceCard(label: "반납할 곳", name: t.end.name,
                                  line: Text(Image(systemName: "figure.walk")) + Text(" 목적지까지 걸어서 \(t.walkFrom.minutes)분"),
                                  selected: view == 2) { view = view == 2 ? 0 : 2 }
                    }
                    .padding(.top, 16)
                    (Text(Image(systemName: "bicycle")) + Text(" 자전거 \(t.bike.minutes)분, \(t.passLine)"))
                        .font(.system(size: 14)).foregroundStyle(Color.grey600).padding(.top, 12)
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
