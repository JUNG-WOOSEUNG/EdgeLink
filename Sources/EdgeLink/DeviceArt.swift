import SwiftUI

// 온보딩 그림용 기기 화면. 애플 로고 대신 노치·메뉴 막대·Dock, 다이내믹 아일랜드·앱 격자·홈 막대로
// 맥북과 아이폰처럼 보이게 한다 (상표 가이드라인상 다른 회사 앱에서 애플 로고를 쓰지 않는다).

/// 맥 화면 안쪽: 위 메뉴 막대, 노치, 아래 Dock
struct MacScreenArt: View {
    var notch = true
    var dark = false

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let bar = max(4, h * 0.07)
            ZStack(alignment: .top) {
                LinearGradient(colors: dark ? [Color(hex: 0x2B3A4A), Color(hex: 0x12161B)]
                                            : [Color(hex: 0xE3F2FB), Color(hex: 0xCFE6F6)],
                               startPoint: .top, endPoint: .bottom)
                // 메뉴 막대
                HStack(spacing: max(2, w * 0.02)) {
                    ForEach(0..<3, id: \.self) { _ in
                        Capsule().fill(Color.black.opacity(0.18)).frame(width: w * 0.05, height: bar * 0.32)
                    }
                    Spacer()
                    ForEach(0..<2, id: \.self) { _ in
                        Circle().fill(Color.black.opacity(0.18)).frame(width: bar * 0.4, height: bar * 0.4)
                    }
                }
                .padding(.horizontal, w * 0.04)
                .frame(height: bar)
                .background(Color.white.opacity(dark ? 0.08 : 0.55))
                if notch {
                    UnevenCapsule(height: bar * 0.95)
                        .fill(Color(hex: 0x1A1A1A))
                        .frame(width: w * 0.14, height: bar * 0.95)
                }
                // Dock
                VStack {
                    Spacer()
                    HStack(spacing: max(2, w * 0.018)) {
                        ForEach(Self.dockColors.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: max(1.5, w * 0.012))
                                .fill(Self.dockColors[i])
                                .frame(width: max(5, w * 0.05), height: max(5, w * 0.05))
                        }
                    }
                    .padding(.horizontal, w * 0.02).padding(.vertical, w * 0.012)
                    .background(RoundedRectangle(cornerRadius: max(2, w * 0.02)).fill(Color.white.opacity(dark ? 0.12 : 0.6)))
                    .padding(.bottom, h * 0.04)
                }
            }
        }
        .accessibilityHidden(true)
    }

    static let dockColors: [Color] = [
        Color(hex: 0x5AC8FA), Color(hex: 0x34C759), Color(hex: 0xFF9500),
        Color(hex: 0xFF3B30), Color(hex: 0xAF52DE), Color(hex: 0x8E8E93),
    ]
}

/// 아래만 둥근 노치 모양
struct UnevenCapsule: Shape {
    var height: CGFloat
    func path(in rect: CGRect) -> Path {
        let r = min(rect.height * 0.5, rect.width * 0.25)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 아이폰 화면 안쪽: 다이내믹 아일랜드, 앱 격자, 홈 막대
struct PhoneScreenArt: View {
    var dark = true
    var apps = true

    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack(alignment: .top) {
                LinearGradient(colors: dark ? [Color(hex: 0x2B3A4A), Color(hex: 0x12161B)]
                                            : [Color(hex: 0xF2F2F7), Color(hex: 0xE5E5EA)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                // 다이내믹 아일랜드
                Capsule().fill(Color.black)
                    .frame(width: w * 0.34, height: max(4, w * 0.1))
                    .padding(.top, h * 0.025)
                if apps {
                    let cell = w * 0.17, gap = w * 0.06
                    VStack(spacing: gap) {
                        ForEach(0..<4, id: \.self) { r in
                            HStack(spacing: gap) {
                                ForEach(0..<4, id: \.self) { c in
                                    RoundedRectangle(cornerRadius: cell * 0.25)
                                        .fill(Self.appColors[(r * 4 + c) % Self.appColors.count].opacity(dark ? 0.55 : 0.8))
                                        .frame(width: cell, height: cell)
                                }
                            }
                        }
                    }
                    .padding(.top, h * 0.13)
                }
                // 홈 막대
                VStack {
                    Spacer()
                    Capsule().fill(dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6))
                        .frame(width: w * 0.36, height: max(2, w * 0.022))
                        .padding(.bottom, h * 0.02)
                }
            }
        }
        .accessibilityHidden(true)
    }

    static let appColors: [Color] = [
        Color(hex: 0x34C759), Color(hex: 0x0A84FF), Color(hex: 0xFF9F0A), Color(hex: 0xFF375F),
        Color(hex: 0x64D2FF), Color(hex: 0xBF5AF2), Color(hex: 0xFFD60A), Color(hex: 0x8E8E93),
    ]
}

/// 검은 테두리가 있는 아이폰
struct PhoneArt<Screen: View>: View {
    var width: CGFloat
    var height: CGFloat
    var bezel: CGFloat = 4
    @ViewBuilder var screen: Screen

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.22).fill(Color(hex: 0x1A1A1A))
            .frame(width: width, height: height)
            .overlay(
                screen
                    .clipShape(RoundedRectangle(cornerRadius: width * 0.22 - bezel))
                    .padding(bezel)
            )
            .accessibilityHidden(true)
    }
}
