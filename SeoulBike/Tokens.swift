import SwiftUI

// 피그마 변수 컬렉션 "따비 Color"와 1:1. 이름 바꾸면 피그마도 같이
enum Token {
    enum Brand {
        static let green = Color(hex: 0x12A15C)       // brand/green
        static let greenDeep = Color(hex: 0x0B8A4C)   // brand/green-deep
        static let greenTint = Color(hex: 0xE6F6EC)   // brand/green-tint
    }
    enum Route {
        static let bike = Color(hex: 0x2A4FE0)         // route/bike
        static let bikeInactive = Color(hex: 0xC3CDF7) // route/bike-inactive
        static let walk = Color(hex: 0xFF7A2F)         // route/walk
        static let walkInactive = Color(hex: 0xFFC6A6) // route/walk-inactive
        static let casing = Color.white                 // route/casing
        static let alternative = Color(hex: 0xA3ACB8)  // route/alternative
    }
    enum Chip {
        static let selectedBg = Color(hex: 0xEAEFFD)   // chip/selected-bg
        static let selectedText = Route.bike           // chip/selected-text
        static let border = Surface.handle             // chip/border
    }
    enum Marker {
        static let location = Color(hex: 0x3182F6)   // marker/location
        static let ret = Color(hex: 0x333D4B)        // marker/return
        static let returnChip = Color(hex: 0x4E5968) // marker/return-chip
    }
    enum Text {
        static let primary = Color(hex: 0x191F28)   // text/primary
        static let secondary = Color(hex: 0x6B7684) // text/secondary
        static let tertiary = Color(hex: 0x8B95A1)  // text/tertiary
        static let disabled = Color(hex: 0xB0B8C1)  // text/disabled
    }
    enum Surface {
        static let base = Color.white                 // surface/base
        static let card = Color(hex: 0xF9FAFB)        // surface/card
        static let fill = Color(hex: 0xF2F4F6)        // surface/fill
        static let handle = Color(hex: 0xD1D6DB)      // surface/handle
    }
    static let compass = Color(hex: 0xF04452)        // accent/compass
}

// 기존 이름 유지 (화면 코드 호환). 값은 전부 Token에서
extension Color {
    static let brand = Token.Brand.green
    static let brandDeep = Token.Brand.greenDeep
    static let brandTint = Token.Brand.greenTint
    static let grey900 = Token.Text.primary
    static let grey700 = Token.Marker.returnChip
    static let grey600 = Token.Text.secondary
    static let grey500 = Token.Text.tertiary
    static let grey400 = Token.Text.disabled
    static let grey100 = Token.Surface.fill
    static let pinOrange = Token.Route.walk

    init(hex: UInt32) {
        self.init(red: Double(hex >> 16 & 0xFF) / 255, green: Double(hex >> 8 & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
