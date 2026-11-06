import MapKit
import SwiftUI

struct MapPickView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let field: Field
    @State private var camera: MapCamera?
    @State private var position: MapCameraPosition = .userLocation(fallback: .region(.seoulCityHall))
    @State private var region: MKCoordinateRegion?
    @State private var place: Place?
    @State private var moved = false

    private var isOrigin: Bool { field == .origin }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(visibleStations(model.stations, in: region)) { s in
                Annotation("", coordinate: s.coordinate) { StationMarker(bikes: s.bikes) }.annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {}
        .onMapCameraChange(frequency: .continuous) { camera = $0.camera }
        .onMapCameraChange(frequency: .onEnd) { ctx in
            if region != nil { moved = true }
            region = ctx.region
        }
        .overlay { CenterPin(label: isOrigin ? "출발" : "도착", dark: !isOrigin) }
        .safeAreaInset(edge: .top) {
            VStack(spacing: 12) {
                HStack(spacing: 8) { BackPill(); Pill(text: isOrigin ? "출발지 선택" : "도착지 선택"); Spacer(); CompassButton(position: $position, camera: camera) }
                if !moved { Toast(text: "지도를 움직여 위치를 맞춰주세요") }
            }
            .padding(.horizontal, 16)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .trailing, spacing: 16) {
                LocateButton(position: $position).padding(.trailing, 16)
                panel
            }
        }
        .onAppear {
            let current = isOrigin ? model.origin : model.destination
            if let c = current?.coordinate {
                position = .region(.init(center: c, span: .init(latitudeDelta: 0.008, longitudeDelta: 0.008)))
            }
        }
        .task(id: region.map { "\($0.center.latitude),\($0.center.longitude)" }) {
            guard let c = region?.center else { return }
            place = try? await Kakao.address(at: c)
        }
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

// 피그마 "핀 UI 시안" B안 + 라벨. 출발 초록, 도착 검정
private struct CenterPin: View {
    let label: String
    let dark: Bool
    var body: some View {
        VStack(spacing: 4) {
            Text(label).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 12).frame(height: 28)
                .background(Capsule().fill(dark ? Color.grey900 : .brand))
                .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
            Image(dark ? "PinDark" : "PinGreen").resizable().frame(width: 40, height: 56)
        }
        // 핀 끝(이미지 위에서 50pt)이 지도 중심에 오도록: 전체 88pt 중 끝은 82pt 지점
        .offset(y: -(82 - 44))
        .allowsHitTesting(false)
    }
}
