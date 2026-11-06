import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var originText = ""
    @State private var destText = ""
    @State private var results: [(Place, Int?)] = []
    @State private var searched = false
    @State private var searchOffline = false
    @FocusState private var focused: Field?
    let focus: Field

    private var query: String { (focused == .origin ? originText : destText).trimmingCharacters(in: .whitespaces) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundStyle(Color.grey900)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            HStack(spacing: 8) {
                VStack(spacing: 8) {
                    input("출발", text: $originText, prompt: "내 위치", promptColor: .brandDeep, field: .origin)
                    input("도착", text: $destText, prompt: "어디로 갈까요?", promptColor: .grey500, field: .destination)
                }
                Button(action: swap) {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.grey600).frame(width: 40, height: 40)
                }
            }
            .padding(.top, 8)

            Button { model.path.append(.pick(focused ?? focus)) } label: {
                HStack(spacing: 12) {
                    Image(systemName: "mappin.and.ellipse").font(.system(size: 18))
                    Text("지도에서 선택").font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(Color.grey900).padding(.vertical, 14)
            }
            .padding(.top, 12)
            Divider().overlay(Color.grey100)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if query.isEmpty {
                        if !model.recent.isEmpty {
                            Text("최근 검색").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.grey500).padding(.top, 20)
                        }
                        ForEach(model.recent, id: \.self) { p in row(p, distance: nil) }
                    } else {
                        ForEach(Array(results.enumerated()), id: \.offset) { _, r in row(r.0, distance: r.1) }
                        if searched && results.isEmpty { empty }
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .padding(.horizontal, 16)
        .background(.white)
        .onAppear {
            originText = model.origin?.name ?? ""
            destText = model.destination?.name ?? ""
            focused = focus
        }
        .task(id: query) {
            searched = false
            guard !query.isEmpty else { results = []; return }
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                results = try await Kakao.search(query, near: model.location.coordinate)
                searchOffline = false
            } catch {
                results = []
                searchOffline = isOffline(error)
            }
            searched = true
        }
    }

    private func input(_ label: String, text: Binding<String>, prompt: String, promptColor: Color, field: Field) -> some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 13)).foregroundStyle(Color.grey500).frame(width: 28, alignment: .leading)
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(promptColor))
                .font(.system(size: 17)).foregroundStyle(Color.grey900).focused($focused, equals: field).submitLabel(.search)
            if focused == field && !text.wrappedValue.isEmpty {
                Button { text.wrappedValue = ""; if field == .origin { model.origin = nil } } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.grey400)
                }
            }
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(Color.grey100, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(focused == field ? Color.brand : .clear, lineWidth: 2))
    }

    // 피그마 E5
    private var empty: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(searchOffline ? "인터넷에 연결되지 않았어요" : "검색 결과가 없어요")
                .font(.system(size: 20, weight: .bold)).foregroundStyle(Color.grey900)
            Text(searchOffline ? "와이파이나 데이터 연결을 확인해 주세요." : "이름을 조금 짧게 입력해 보세요.\n지도에서 직접 고를 수도 있어요.")
                .font(.system(size: 15)).foregroundStyle(Color.grey500).lineSpacing(3).padding(.top, 6)
            if !searchOffline {
                PrimaryButton(title: "지도에서 선택하기") { model.path.append(.pick(focused ?? focus)) }.padding(.top, 24)
            }
        }
        .padding(.top, 32)
    }

    private func row(_ p: Place, distance: Int?) -> some View {
        Button { select(p) } label: {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Color.grey900)
                    if !p.address.isEmpty { Text(p.address).font(.system(size: 14)).foregroundStyle(Color.grey500) }
                }
                Spacer()
                if let distance { Text(distanceText(Double(distance))).font(.system(size: 14)).foregroundStyle(Color.grey500) }
            }
            .multilineTextAlignment(.leading).padding(.vertical, 12)
        }
    }

    private func select(_ p: Place) {
        let field = focused ?? focus
        model.set(field, p)
        if field == .origin { originText = p.name } else { destText = p.name }
        if model.destination == nil { focused = .destination } else { model.path = [.result] }
    }

    private func swap() {
        let o = model.originPlace
        model.origin = model.destination
        model.destination = o
        originText = model.origin?.name ?? ""
        destText = model.destination?.name ?? ""
    }
}
