import MapKit
import SwiftUI

extension Color {
    static let brand = Color(hex: 0x12A15C)
    static let brandDeep = Color(hex: 0x0B8A4C)
    static let brandTint = Color(hex: 0xE6F6EC)
    static let grey900 = Color(hex: 0x191F28)
    static let grey700 = Color(hex: 0x4E5968)
    static let grey600 = Color(hex: 0x6B7684)
    static let grey500 = Color(hex: 0x8B95A1)
    static let grey400 = Color(hex: 0xB0B8C1)
    static let grey100 = Color(hex: 0xF2F4F6)

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

struct PrimaryButton: View {
    let title: String
    var gray = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(gray ? Color.grey700 : .white)
                .background(gray ? Color.grey100 : .brand, in: RoundedRectangle(cornerRadius: 16))
        }
    }
}

// 지도 위 하단 시트 (드래그 없는 고정형)
struct BottomPanel<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color(hex: 0xD1D6DB)).frame(width: 36, height: 4)
                .frame(maxWidth: .infinity).padding(.bottom, 20)
            content
        }
        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 8)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                .fill(.white).shadow(color: .black.opacity(0.06), radius: 16, y: -2)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

struct InfoRow: View {
    let tag: String
    let title: String
    let detail: Text
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(tag)
                .font(.system(size: 12, weight: .bold)).foregroundStyle(Color.brandDeep)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color.brandTint, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.grey900)
                detail.font(.system(size: 14)).foregroundStyle(Color.grey500)
            }
        }
        .padding(.vertical, 10)
    }
}

extension Text {
    static func em(_ s: String) -> Text { Text(s).foregroundColor(.brandDeep).bold() }
}

struct StationMarker: View {
    let bikes: Int
    var selected = false
    var body: some View {
        let empty = bikes == 0
        HStack(spacing: 4) {
            Image(systemName: "bicycle").font(.system(size: 11, weight: .bold))
                .foregroundStyle(selected ? .white : empty ? Color.grey400 : .brand)
            Text("\(bikes)").font(.system(size: 14, weight: .bold))
                .foregroundStyle(selected ? .white : empty ? Color.grey400 : .grey900)
        }
        .padding(.leading, 8).padding(.trailing, 10).frame(height: 30)
        .background(Capsule().fill(selected ? Color.brand : .white))
        .shadow(color: selected ? Color.brand.opacity(0.4) : .black.opacity(0.18), radius: selected ? 4 : 2.5, y: 1)
        .scaleEffect(selected ? 1.15 : 1)
    }
}

struct MapTag: View {
    let text: String
    var dark = false
    var body: some View {
        Text(text).font(.system(size: 13, weight: .bold)).foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(Capsule().fill(dark ? Color.grey900 : .brand))
            .overlay(Capsule().stroke(.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.2), radius: 3, y: 2)
    }
}

struct RoundButton: View {
    let systemName: String
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName).font(.system(size: 19, weight: .semibold))
                .foregroundStyle(active ? .white : Color.grey900)
                .frame(width: 48, height: 48)
                .background(Circle().fill(active ? Color.brand : .white))
                .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        }
    }
}

// 항상 보이는 나침반, 바늘이 지도 방향 따라 회전, 탭하면 북쪽 정렬
// 지도 카메라를 담는 작은 상자. 이걸 읽는 뷰(나침반, 내 위치 점)만 매 프레임 다시 그려짐
@Observable final class MapCam { var camera: MapCamera? }

struct CompassButton: View {
    @Binding var position: MapCameraPosition
    let cam: MapCam
    var body: some View {
        let camera = cam.camera
        Button {
            guard let c = camera else { return }
            withAnimation {
                position = .camera(MapCamera(centerCoordinate: c.centerCoordinate, distance: c.distance, heading: 0, pitch: 0))
            }
        } label: {
            ZStack {
                Circle().fill(.white).shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                VStack(spacing: 0) {
                    Triangle().fill(Color(hex: 0xF04452)).frame(width: 9, height: 12)
                    Triangle().fill(Color.grey400).frame(width: 9, height: 12).rotationEffect(.degrees(180))
                }
                .rotationEffect(.degrees(-(camera?.heading ?? 0)))
                Text("N").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(hex: 0xF04452))
                    .offset(y: -17).rotationEffect(.degrees(-(camera?.heading ?? 0)))
            }
            .frame(width: 48, height: 48)
        }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        Path { p in p.move(to: .init(x: r.midX, y: r.minY)); p.addLine(to: .init(x: r.maxX, y: r.maxY)); p.addLine(to: .init(x: r.minX, y: r.maxY)); p.closeSubpath() }
    }
}

struct BackPill: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold)).foregroundStyle(Color.grey900)
                .frame(width: 44, height: 44).background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
    }
}

struct Pill: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.grey900).lineLimit(1)
            .padding(.horizontal, 16).frame(height: 44)
            .background(Capsule().fill(.white)).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

struct Banner: View {
    let text: String
    let action: String
    let onTap: () -> Void
    var body: some View {
        HStack {
            Text(text)
            Spacer()
            Button(action, action: onTap).fontWeight(.bold).foregroundStyle(Color(hex: 0x8FE3B5))
        }
        .font(.system(size: 15)).foregroundStyle(.white)
        .padding(.horizontal, 16).frame(height: 48)
        .background(Color.grey900, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct Toast: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 14)).foregroundStyle(.white)
            .padding(.horizontal, 18).frame(height: 40)
            .background(Capsule().fill(Color.grey900.opacity(0.85)))
    }
}

// 지도 좌표에 고정된 격자(줌 단계별)에서 칸마다 자전거 가장 많은 대여소 1개
// 같은 배율이면 이동해도 칸이 안 바뀌어 마커가 그대로, 화면 밖 반 화면씩 미리 그림
// ponytail: 격자 솎아내기, 숫자 묶음 클러스터가 필요해지면 교체
func visibleStations(_ all: [Station], in r: MKCoordinateRegion?) -> [Station] {
    guard let r, r.span.latitudeDelta < 0.08 else { return [] }
    let level = pow(2, log2(r.span.latitudeDelta).rounded(.up))
    let ch = level / 9, cw = level / 9 * 1.05
    let halfLat = r.span.latitudeDelta, halfLng = r.span.longitudeDelta // 화면의 2배 범위
    struct Cell: Hashable { let x: Int; let y: Int }
    var best: [Cell: Station] = [:]
    for s in all {
        let lat = s.coordinate.latitude, lng = s.coordinate.longitude
        guard abs(lat - r.center.latitude) < halfLat, abs(lng - r.center.longitude) < halfLng else { continue }
        let key = Cell(x: Int((lng / cw).rounded(.down)), y: Int((lat / ch).rounded(.down)))
        if s.bikes > best[key]?.bikes ?? -1 { best[key] = s }
    }
    return Array(best.values)
}

// 지도 이동 중 마커 다시 고를 때: 중심이 1/4 화면 넘게 움직였거나 배율이 바뀌었을 때만
func movedEnough(_ old: MKCoordinateRegion?, _ new: MKCoordinateRegion) -> Bool {
    guard let old else { return true }
    return abs(new.center.latitude - old.center.latitude) > old.span.latitudeDelta / 4
        || abs(new.center.longitude - old.center.longitude) > old.span.longitudeDelta / 4
        || abs(log2(new.span.latitudeDelta / old.span.latitudeDelta)) > 0.3
}

func zoomedOut(_ r: MKCoordinateRegion?) -> Bool { (r?.span.latitudeDelta ?? 0) >= 0.08 }

func distanceText(_ m: Double) -> String { m < 1000 ? "\(Int(m))m" : String(format: "%.1fkm", m / 1000) }

func agoText(_ d: Date?, now: Date) -> String {
    guard let d else { return "불러오는 중" }
    let m = Int(now.timeIntervalSince(d) / 60)
    return m < 1 ? "방금" : "\(m)분 전"
}

// iOS 기본 위치 표시는 정확도 낮을 때 큰 오차 원을 그려서 직접 그림. 초록 점 + 바라보는 방향
struct MyLocationDot: View {
    let location: LocationService
    let cam: MapCam
    var body: some View {
        // 지도 회전 보정한 기기 방향(도)
        let heading = location.heading.map { $0 - (cam.camera?.heading ?? 0) }
        ZStack {
            if let heading {
                Cone().fill(RadialGradient(colors: [Color.brand.opacity(0.35), Color.brand.opacity(0)],
                                           center: .center, startRadius: 6, endRadius: 40))
                    .rotationEffect(.degrees(heading))
            }
            Circle().fill(.white).frame(width: 22, height: 22).shadow(color: .black.opacity(0.25), radius: 3, y: 1)
            Circle().fill(Color.brand).frame(width: 14, height: 14)
        }
        .frame(width: 80, height: 80)
        .allowsHitTesting(false)
    }

    private struct Cone: Shape {
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
