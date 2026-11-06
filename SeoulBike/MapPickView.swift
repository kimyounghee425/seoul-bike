import MapKit
import SwiftUI

struct MapPickView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let field: Field
    @State private var map = MapHandle()
    @State private var region: MKCoordinateRegion?
    @State private var place: Place?
    @State private var moved = false

    private var isOrigin: Bool { field == .origin }

    var body: some View {
        KakaoMapView(handle: map)
        .ignoresSafeArea()
        .onAppear {
            map.onCamera = { r, final in
                guard final else { return }
                if region != nil { moved = true }
                region = r
            }
            map.onClusterTap = { c in map.move(to: c, zoom: 14) }
            // 이미 고른 장소가 있으면 그곳, 아니면 홈에서 보던 지도 그대로 (네이버 지도 방식)
            let current = isOrigin ? model.origin : model.destination
            if let c = current?.coordinate {
                map.move(to: c, zoom: 16, animated: false)
            } else if let r = model.homeRegion {
                map.show(r)
            } else if let c = model.location.coordinate {
                map.move(to: c, zoom: 15, animated: false)
            }
        }
        .onChange(of: markerKey, initial: true) { _, _ in
            map.setClusters(stationClusters(model.stations, in: region))
            map.setStations(visibleStations(model.stations, in: region), selected: nil, dimmed: model.stationsOffline)
        }
        .onChange(of: locationKey, initial: true) { _, _ in map.setMyLocation(model.location.coordinate, heading: model.location.heading) }
        .overlay { CenterPin(label: isOrigin ? "출발" : "도착") }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 12) {
                HStack(spacing: 8) { BackPill(); Pill(text: isOrigin ? "출발지 선택" : "도착지 선택"); Spacer(); CompassButton(map: map) }
                if !moved { Toast(text: "지도를 움직여 위치를 맞춰주세요") }
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 16) {
                LocateButton(map: map, location: model.location).padding(.trailing, 16)
                panel
            }
        }
        .task(id: region.map { "\($0.center.latitude),\($0.center.longitude)" }) {
            guard let c = region?.center else { return }
            place = try? await Kakao.address(at: c)
        }
    }

    private var markerKey: String {
        "\(region.map { "\($0.center.latitude),\($0.center.longitude),\($0.span.latitudeDelta)" } ?? "")|\(model.stationsUpdatedAt?.timeIntervalSince1970 ?? 0)|\(model.stationsOffline)"
    }

    private var locationKey: String {
        "\(model.location.coordinate?.latitude ?? 0),\(model.location.coordinate?.longitude ?? 0),\(model.location.heading ?? -1)"
    }

    private var panel: some View {
        BottomPanel {
            Text(place?.name ?? "위치를 찾는 중…").font(.system(size: 22, weight: .bold)).foregroundStyle(Color.grey900)
            if let a = place?.address, !a.isEmpty {
                Text(a).font(.system(size: 15)).foregroundStyle(Color.grey500).padding(.top, 6)
            }
            if let c = region?.center, let s = model.nearest(to: c, where: { !isOrigin || $0.bikes > 0 }) {
                let walk = Int((c.distance(to: s.coordinate) / 1.2 / 60).rounded(.up))
                InfoRow(tag: isOrigin ? "대여" : "반납", title: s.name,
                        detail: isOrigin ? Text("걸어서 \(max(1, walk))분, 자전거 ") + Text.em("\(s.bikes)대") + Text(" 남았어요")
                                         : Text("목적지까지 걸어서 \(max(1, walk))분이에요"))
                    .padding(.horizontal, 14).padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(hex: 0xF9FAFB), in: RoundedRectangle(cornerRadius: 12))
                    .padding(.top, 12)
            }
            PrimaryButton(title: isOrigin ? "여기서 출발" : "여기로 도착") {
                guard let place else { return }
                model.set(field, place)
                if isOrigin && model.destination == nil { dismiss() } else { model.path = [.result] }
            }
            .disabled(place == nil)
            .padding(.top, 16)
        }
    }
}

// 피그마 "핀 UI 시안" B안 + 라벨. 출발·도착 모두 주황, 라벨로 구분
private struct CenterPin: View {
    let label: String
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(Color.pinOrange))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            DropPinShape(color: .pinOrange)
        }
        // 핀 끝(이미지 위에서 50pt)이 지도 중심에 오도록: 전체 88pt 중 끝은 82pt 지점
        .offset(y: -(82 - 44))
        .allowsHitTesting(false)
    }
}
