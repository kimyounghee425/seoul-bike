import KakaoMapsSDK
import SwiftUI

@main
struct SeoulBikeApp: App {
    @AppStorage("onboarded") private var onboarded = false
    @State private var model = AppModel()

    init() {
        SDKInitializer.InitSDK(appKey: Secrets.kakaoNative)
        #if DEBUG
        Trip.selfCheck()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if onboarded { RootView() } else { OnboardingView { onboarded = true } }
            }
            .environment(model)
            .tint(.brand)
        }
    }
}

// ponytail: 키를 앱 번들에 넣는 PoC 방식, 출시 전 프록시 서버로 이전 필요
enum Secrets {
    static let seoul = Bundle.main.object(forInfoDictionaryKey: "SeoulOpenAPIKey") as? String ?? ""
    static let kakao = Bundle.main.object(forInfoDictionaryKey: "KakaoRestAPIKey") as? String ?? ""
    static let kakaoNative = Bundle.main.object(forInfoDictionaryKey: "KakaoNativeAppKey") as? String ?? ""
}
