import MapKit
import SwiftUI

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
            Capsule().fill(Token.Surface.handle).frame(width: 36, height: 4)
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
struct CompassButton: View {
    let map: MapHandle
    var body: some View {
        let deg = -map.rotation * 180 / .pi
        Button { map.resetNorth() } label: {
            ZStack {
                Circle().fill(.white).shadow(color: .black.opacity(0.12), radius: 4, y: 2)
                VStack(spacing: 0) {
                    Triangle().fill(Color(hex: 0xF04452)).frame(width: 9, height: 12)
                    Triangle().fill(Color.grey400).frame(width: 9, height: 12).rotationEffect(.degrees(180))
                }
                .rotationEffect(.degrees(deg))
                Text("N").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(hex: 0xF04452))
                    .offset(y: -17).rotationEffect(.degrees(deg))
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
    let ch = level / 12, cw = level / 12 * 1.05 // 카카오 줌 단계 기준 화면당 8~9줄
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

// 많이 축소하면 대여소 대신 지역 묶음(피그마 C1, 숫자 = 대여소 수)
struct StationCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
}

func stationClusters(_ all: [Station], in r: MKCoordinateRegion?) -> [StationCluster] {
    guard let r, r.span.latitudeDelta >= 0.08 else { return [] }
    let level = pow(2, log2(r.span.latitudeDelta).rounded(.up))
    let cell = level / 7 // 화면에 10~15개 정도 (카카오 줌 기준)
    let cellLng = cell / 0.8 // 서울 위도에서 경도 1도가 위도 1도보다 짧아 보정
    struct Cell: Hashable { let x: Int; let y: Int }
    var sum: [Cell: (lat: Double, lng: Double, n: Int)] = [:]
    for s in all {
        let lat = s.coordinate.latitude, lng = s.coordinate.longitude
        guard abs(lat - r.center.latitude) < r.span.latitudeDelta, abs(lng - r.center.longitude) < r.span.longitudeDelta else { continue }
        let k = Cell(x: Int((lng / cellLng).rounded(.down)), y: Int((lat / cell).rounded(.down)))
        let v = sum[k] ?? (0, 0, 0)
        sum[k] = (v.lat + lat, v.lng + lng, v.n + 1)
    }
    return sum.map { k, v in
        StationCluster(id: "\(level)-\(k.x)-\(k.y)",
                       coordinate: .init(latitude: v.lat / Double(v.n), longitude: v.lng / Double(v.n)), count: v.n)
    }
}

// 피그마 C3 묶음 원: 36/46/58 세 크기
struct ClusterBubble: View {
    let count: Int
    var body: some View {
        let d: CGFloat = count < 50 ? 36 : count < 120 ? 46 : 58
        Text("\(count)")
            .font(.system(size: d < 40 ? 13 : d < 50 ? 15 : 17, weight: .bold)).foregroundStyle(.white)
            .frame(width: d, height: d)
            .background(Circle().fill(Color.brand))
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
    }
}

func distanceText(_ m: Double) -> String { m < 1000 ? "\(Int(m))m" : String(format: "%.1fkm", m / 1000) }

func agoText(_ d: Date?, now: Date) -> String {
    guard let d else { return "불러오는 중" }
    let m = Int(now.timeIntervalSince(d) / 60)
    return m < 1 ? "방금" : "\(m)분 전"
}

// 피그마 "핀 UI 시안" B안. SVG 에셋은 iOS가 흰 테두리를 어긋나게 그려서 코드로 그림 (40x56, 끝이 y 50)
struct DropPinShape: View {
    var color: Color = .brand
    var body: some View {
        ZStack(alignment: .top) {
            Ellipse().fill(Color.grey900.opacity(0.18)).frame(width: 14, height: 5).offset(y: 49.5)
            Teardrop().fill(color).overlay(Teardrop().stroke(.white, lineWidth: 2.5))
            Circle().fill(.white).frame(width: 12, height: 12).offset(y: 13.5)
        }
        .frame(width: 40, height: 56, alignment: .top)
    }

    private struct Teardrop: Shape {
        func path(in r: CGRect) -> Path {
            let sx = r.width / 40, sy = r.height / 56
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { .init(x: r.minX + x * sx, y: r.minY + y * sy) }
            var path = Path()
            path.move(to: p(20, 50))
            path.addCurve(to: p(4, 19.5), control1: p(20, 50), control2: p(4, 32.5))
            path.addCurve(to: p(20, 3.5), control1: p(4, 10.4), control2: p(11.2, 3.5))
            path.addCurve(to: p(36, 19.5), control1: p(28.8, 3.5), control2: p(36, 10.4))
            path.addCurve(to: p(20, 50), control1: p(36, 32.5), control2: p(20, 50))
            path.closeSubpath()
            return path
        }
    }
}


// 지도 뷰 전환 (전체 / 대여 / 반납). 피그마 "세그먼트 컨트롤": 174x36 r18 p3, 칸 30 r15 좌우 14, 15 bold
struct SegmentControl: View {
    let items: [String]
    @Binding var selection: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { i in
                Button { withAnimation(.snappy(duration: 0.2)) { selection = i } } label: {
                    Text(items[i]).font(.system(size: 15, weight: .bold))
                        .foregroundStyle(selection == i ? Color.white : Token.Text.secondary)
                        .padding(.horizontal, 14).frame(height: 30)
                        .background(Capsule().fill(selection == i ? Token.Text.primary : .clear))
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Token.Surface.base)).shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }
}

// 결과 시트 카드. 피그마 "빌릴 곳 카드": fill #F2F4F6 r16 p18/20 gap6, 선택 시 초록 테두리 2
struct PlaceCard<Facts: View>: View {
    let label: String
    let name: String
    var selected = false
    @ViewBuilder let facts: Facts
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Text(label).font(.system(size: 12, weight: .bold)).foregroundStyle(Token.Brand.greenDeep)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Token.Brand.greenTint, in: RoundedRectangle(cornerRadius: 8))
                Text(name).font(.system(size: 20, weight: .bold)).foregroundStyle(Token.Text.primary).lineLimit(1)
                HStack(spacing: 14) { facts }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 18).padding(.horizontal, 20)
            .background(Token.Surface.fill, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Token.Brand.green : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

// 카드 안 사실 한 줄: 아이콘 16 + 4 + 14 medium
struct Fact: View {
    enum Icon { case walk, bike }
    let icon: Icon
    let text: String
    var iconColor: Color = Token.Route.walk
    var textColor: Color = Token.Text.primary
    var weight: Font.Weight = .medium
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon == .walk ? "figure.walk" : "bicycle")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(iconColor).frame(width: 16, height: 16)
            Text(text).font(.system(size: 14, weight: weight)).foregroundStyle(textColor)
        }
    }
}

// MARK: 결과 지도 마커 (피그마 SVG 그대로, 그림자 여백 포함 캔버스)

// 자전거 아이콘 선. 바퀴 r, 중심, 프레임은 SVG 좌표
private struct BikeGlyph: SwiftUI.Shape {
    let l: CGPoint, r: CGPoint, rad: CGFloat, frame: [(CGPoint, CGPoint)]
    func path(in _: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: l.x - rad, y: l.y - rad, width: rad * 2, height: rad * 2))
        p.addEllipse(in: CGRect(x: r.x - rad, y: r.y - rad, width: rad * 2, height: rad * 2))
        for (a, b) in frame { p.move(to: a); p.addLine(to: b) }
        return p
    }
}

// 대여소 핀: 44x54 캔버스, 끝 (22,44)
struct RentPin: View {
    static let size = CGSize(width: 44, height: 54)
    static let tip = CGPoint(x: 22, y: 44)
    var body: some View {
        ZStack {
            Teardrop().fill(Token.Brand.green).overlay(Teardrop().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            BikeGlyph(l: .init(x: 16.5, y: 22.5), r: .init(x: 27.5, y: 22.5), rad: 3.3, frame: [
                (.init(x: 27.5, y: 22.5), .init(x: 25.5, y: 16.5)), (.init(x: 25.5, y: 16.5), .init(x: 19.5, y: 16.5)),
                (.init(x: 19.5, y: 16.5), .init(x: 16.5, y: 22.5)), (.init(x: 19.5, y: 16.5), .init(x: 22, y: 22.5)),
                (.init(x: 22, y: 22.5), .init(x: 25.5, y: 16.5)), (.init(x: 18, y: 14), .init(x: 21, y: 14)),
            ]).stroke(.white, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
    private struct Teardrop: SwiftUI.Shape {
        func path(in _: CGRect) -> Path {
            var p = Path()
            p.move(to: .init(x: 22, y: 44))
            p.addCurve(to: .init(x: 7, y: 20), control1: .init(x: 22, y: 44), control2: .init(x: 7, y: 30.5))
            p.addArc(center: .init(x: 22, y: 20), radius: 15, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
            p.addCurve(to: .init(x: 22, y: 44), control1: .init(x: 37, y: 30.5), control2: .init(x: 22, y: 44))
            p.closeSubpath()
            return p
        }
    }
}

// 반납소 핀: 42x49 캔버스, 끝 (21,39). 둥근 사각 + 깃발
struct ReturnPin: View {
    static let size = CGSize(width: 42, height: 49)
    static let tip = CGPoint(x: 21, y: 39)
    var body: some View {
        ZStack {
            PinBody().fill(Token.Marker.ret).overlay(PinBody().stroke(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
            Path { p in p.move(to: .init(x: 17, y: 26.5)); p.addLine(to: .init(x: 17, y: 11.5)) }
                .stroke(.white, style: .init(lineWidth: 1.8, lineCap: .round))
            Path { p in
                p.move(to: .init(x: 17.5, y: 12)); p.addLine(to: .init(x: 26.5, y: 12)); p.addLine(to: .init(x: 24, y: 15.5))
                p.addLine(to: .init(x: 26.5, y: 19)); p.addLine(to: .init(x: 17.5, y: 19)); p.closeSubpath()
            }.fill(.white)
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
    private struct PinBody: SwiftUI.Shape {
        func path(in _: CGRect) -> Path {
            var p = Path(roundedRect: CGRect(x: 7, y: 5, width: 28, height: 28), cornerRadius: 8)
            p.move(to: .init(x: 17, y: 33)); p.addLine(to: .init(x: 21, y: 39)); p.addLine(to: .init(x: 25, y: 33))
            return p
        }
    }
}

// 내 위치와 대여소가 같은 자리일 때: 파란 링 + 흰 링 + 초록 원 + 자전거, 뒤에 halo 48. 캔버스 48, 중심 (24,24)
struct ComboMarker: View {
    static let size = CGSize(width: 48, height: 48)
    var body: some View {
        ZStack {
            Circle().fill(Token.Marker.location.opacity(0.2)).frame(width: 48, height: 48)
            ZStack {
                Circle().fill(Token.Marker.location).frame(width: 32, height: 32).shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                Circle().fill(.white).frame(width: 27, height: 27)
                Circle().fill(Token.Brand.green).frame(width: 23, height: 23)
                BikeGlyph(l: .init(x: 17.6, y: 21.8), r: .init(x: 26.4, y: 21.8), rad: 2.7, frame: [
                    (.init(x: 26.4, y: 21.8), .init(x: 24.8, y: 17)), (.init(x: 24.8, y: 17), .init(x: 20, y: 17)),
                    (.init(x: 20, y: 17), .init(x: 17.6, y: 21.8)), (.init(x: 20, y: 17), .init(x: 22, y: 21.8)),
                    (.init(x: 22, y: 21.8), .init(x: 24.8, y: 17)), (.init(x: 18.8, y: 15.4), .init(x: 21.2, y: 15.4)),
                ]).stroke(.white, style: .init(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    .frame(width: 44, height: 44).offset(y: 2) // SVG 44 캔버스 중심 (22,20) 보정
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

// 도착 점: 12, 흰 테두리 3
struct DestDot: View {
    var color: Color = Token.Route.walk
    var body: some View {
        Circle().fill(color).frame(width: 12, height: 12).overlay(Circle().stroke(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
    }
}

// 핀 옆 라벨: 흰 알약 30 r18, 칩 18 r8 12 bold, 이름 14 bold, 대수 14 bold 진초록
struct PinLabel: View {
    let chip: String
    let chipColor: Color
    let name: String
    var bikes: Int? = nil
    var body: some View {
        HStack(spacing: 8) {
            Text(chip).font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 7).frame(height: 18).background(chipColor, in: RoundedRectangle(cornerRadius: 8))
            if !name.isEmpty { Text(name).font(.system(size: 14, weight: .bold)).foregroundStyle(Token.Text.primary).lineLimit(1) }
            if let bikes { Text("\(bikes)대").font(.system(size: 14, weight: .bold)).foregroundStyle(Token.Brand.greenDeep) }
        }
        .padding(.leading, 10).padding(.trailing, 12).frame(height: 30)
        .fixedSize() // 이미지로 구울 때 글자가 줄임표로 눌리지 않게
        .background(Capsule().fill(.white)).shadow(color: .black.opacity(0.14), radius: 4, y: 2)
    }
}

// 핀 + 라벨을 한 이미지로. 라벨은 핀 머리 높이에 맞춰 왼쪽 또는 오른쪽. tip은 이 뷰 안 좌표
struct LabeledPin<Pin: View>: View {
    let pin: Pin
    let pinSize: CGSize
    let headCenterY: CGFloat
    let label: PinLabel
    let labelOnLeft: Bool
    static var pad: CGFloat { 10 } // 그림자 여백
    var body: some View {
        HStack(alignment: .top, spacing: -6) {
            if labelOnLeft { label.padding(.top, headCenterY - 15); pin.frame(width: pinSize.width, height: pinSize.height) }
            else { pin.frame(width: pinSize.width, height: pinSize.height); label.padding(.top, headCenterY - 15) }
        }
        .padding(Self.pad)
    }
}


// 피그마 컴포넌트 "경로 후보 칩". 선택: 연파랑 배경 + 파랑 bold / 기본: 흰 배경 + 회색 테두리 + 회색 medium
struct RouteChip: View {
    let text: String
    let selected: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.system(size: 14, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Token.Chip.selectedText : Token.Text.secondary)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Capsule().fill(selected ? Token.Chip.selectedBg : Token.Surface.base))
                .overlay(Capsule().strokeBorder(selected ? Token.Chip.selectedBg : Token.Chip.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}


// 대여 핀 오른쪽 위 자전거 수 배지 (대여·반납 보기). 피그마에 없던 요소, 라벨 칩과 같은 색 체계
struct BikeBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)").font(.system(size: 11, weight: .bold)).foregroundStyle(Token.Brand.greenDeep)
            .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
            .background(Capsule().fill(.white)).overlay(Capsule().stroke(Token.Brand.green, lineWidth: 1.5))
            .fixedSize()
    }
}
