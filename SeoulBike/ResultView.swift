import MapKit
import SwiftUI

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @State private var map = MapHandle()
    @State private var trip: Trip?
    @State private var error: Trip.PlanError?
    @State private var expanded = true

    var body: some View {
        KakaoMapView(handle: map)
        .ignoresSafeArea()
        .onAppear {
            // 위 헤더, 아래 시트에 가리지 않게 경로 맞춤 여백
            map.setMargins(UIEdgeInsets(top: 130, left: 40, bottom: 440, right: 40))
            if let c = model.originPlace?.coordinate ?? model.location.coordinate { map.move(to: c, zoom: 15, animated: false) }
        }
        .onChange(of: locationKey, initial: true) { _, _ in map.setMyLocation(model.location.coordinate, heading: model.location.heading) }
        .onChange(of: map.ready) { _, ready in if ready, let t = trip { map.setTrip(t); map.fit(t.allPoints) } }
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
            VStack(alignment: .trailing, spacing: 16) {
                LocateButton(map: map, location: model.location).padding(.trailing, 16)
                panel
            }
        }
        .task { await plan() }
    }

    private var locationKey: String {
        "\(model.location.coordinate?.latitude ?? 0),\(model.location.coordinate?.longitude ?? 0),\(model.location.heading ?? -1)"
    }

    @ViewBuilder private var panel: some View {
        BottomPanel {
            if let t = trip {
                Text("\(t.totalMinutes)분 걸려요").font(.system(size: 26, weight: .bold)).foregroundStyle(Color.grey900)
                Text("자전거로 \(t.bike.minutes)분, 걷는 건 \(t.walkTo.minutes + t.walkFrom.minutes)분이에요")
                    .font(.system(size: 15)).foregroundStyle(Color.grey500).padding(.top, 6)
                if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    InfoRow(tag: "대여", title: t.start.name,
                            detail: Text("자전거 ") + Text.em("\(t.start.bikes)대") + Text(" 남았어요"))
                    InfoRow(tag: "반납", title: t.end.name, detail: Text("목적지까지 걸어서 \(t.walkFrom.minutes)분이에요"))
                    InfoRow(tag: "이용권", title: t.pass.title, detail: Text(t.pass.detail))
                }
                .padding(.top, 16)
                .transition(.opacity)
                }
                PrimaryButton(title: "따릉이 앱 열기") { openBikeSeoul() }.padding(.top, 20)
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
            if let t = trip { map.setTrip(t); map.fit(t.allPoints) }
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
