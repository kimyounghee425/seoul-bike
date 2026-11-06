import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var page = 0
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page == 0 ? "목적지만 정하면\n따릉이 길을 알려드려요" : "내 주변 대여소를 찾을 때\n위치를 사용해요")
                .font(.system(size: 28, weight: .bold)).foregroundStyle(Color.grey900).lineSpacing(4)
                .padding(.top, 66)
            Text(page == 0 ? "빌릴 곳과 반납할 곳, 가는 길과\n필요한 이용권까지 한 번에 보여드려요"
                           : "위치는 대여소와 경로를 찾는 데만 써요.\n허용하지 않아도 출발지를 직접 정할 수 있어요.")
                .font(.system(size: 16)).foregroundStyle(Color.grey600).lineSpacing(5).padding(.top, 12)
            Spacer()
            Image(page == 0 ? "OnboardingBike" : "OnboardingMap")
                .resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 250)
                .id(page).transition(.opacity)
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<2) { i in
                    Capsule().fill(i == page ? Color.brand : Color(hex: 0xD1D6DB)).frame(width: i == page ? 18 : 6, height: 6)
                }
            }
            .frame(maxWidth: .infinity).padding(.bottom, 24)
            if page == 0 {
                PrimaryButton(title: "다음") { withAnimation { page = 1 } }
            } else {
                // 심사 5.1.1: 권한 안내 버튼은 중립 문구, 건너뛰기 없이 시스템 팝업으로
                PrimaryButton(title: "계속") { model.location.request(); done() }
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
        .background(.white)
    }
}
