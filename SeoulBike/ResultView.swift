import MapKit
import SwiftUI

struct ResultView: View {
    @Environment(AppModel.self) private var model
    @State private var cam = MapCam()
    @State private var position: MapCameraPosition = .automatic
    @State private var trip: Trip?
    @State private var error: Trip.PlanError?
    @State private var expanded = true

    private let dash = StrokeStyle(lineWidth: 4, lineCap: .round, dash: [1, 8])

    var body: some View {
        Map(position: $position) {
            if let c = model.location.coordinate {
                Annotation("", coordinate: c, anchor: .center) {
                    MyLocationDot(location: model.location, cam: cam)
                }
                .annotationTitles(.hidden)
            }
            if let t = trip {
                MapPolyline(coordinates: t.walkTo.path).stroke(Color.grey600, style: dash)
                MapPolyline(coordinates: t.bike.path).stroke(Color.brand, style: .init(lineWidth: 6, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: t.walkFrom.path).stroke(Color.grey600, style: dash)
                Annotation("", coordinate: t.start.coordinate) { MapTag(text: "대여") }.annotationTitles(.hidden)
                Annotation("", coordinate: t.end.coordinate) { MapTag(text: "반납") }.annotationTitles(.hidden)
                Annotation("", coordinate: t.destination.coordinate) {
                    Circle().fill(Color.pinOrange).frame(width: 14, height: 14).overlay(Circle().stroke(.white, lineWidth: 3))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {}
        .onMapCameraChange(frequency: .continuous) { cam.camera = $0.camera }
        .safeAreaInset(edge: .top) {
            HStack(spacing: 8) {
                BackPill()
                Pill(text: "\(model.originPlace?.name ?? "내 위치") → \(model.destination?.name ?? "")")
                    .frame(maxWidth: .infinity, alignment: .leading)
                CompassButton(position: $position, cam: cam)
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 16) {
                LocateButton(position: $position, location: model.location, cam: cam).padding(.trailing, 16)
                panel
            }
        }
        .task { await plan() }
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

    // 경로 전체가 보이게 한 번만 맞춤. .automatic 은 다시 그릴 때마다 재맞춤돼서 확대가 막힘
    private func fit(_ t: Trip) -> MapCameraPosition {
        let pts = (t.walkTo.path + t.bike.path + t.walkFrom.path).map(MKMapPoint.init)
        var r = pts.reduce(MKMapRect.null) { $0.union(MKMapRect(origin: $1, size: .init(width: 1, height: 1))) }
        // 위 헤더, 아래 시트에 가리지 않게 여백 (시트가 아래쪽 절반 차지)
        r = MKMapRect(x: r.minX - r.width * 0.25, y: r.minY - r.height * 0.4,
                      width: r.width * 1.5, height: r.height * 2.4)
        return .rect(r)
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
            if let t = trip { withAnimation { position = fit(t) } }
        } catch {
            self.error = Trip.PlanError.from(error)
            // 경로 없으면 전국 지도로 축소되는 문제, 내 위치로
            position = .region(.init(center: model.location.coordinate ?? MKCoordinateRegion.seoulCityHall.center,
                                     span: .init(latitudeDelta: 0.015, longitudeDelta: 0.015)))
        }
    }
}

// 따릉이 공식 앱 스킴. 유니버설 링크·화면별 딥링크 없음(2026-11 확인), 앱 실행까지만
func openBikeSeoul() {
    UIApplication.shared.open(URL(string: "bikeseoul://action")!) { ok in
        if !ok { UIApplication.shared.open(URL(string: "https://apps.apple.com/kr/app/id1037272004")!) }
    }
}
