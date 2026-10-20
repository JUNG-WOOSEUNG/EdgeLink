import AppKit
import SwiftUI

// 개발용 디자인 규격(캔버스 5-1) 그대로. 이름은 규격표의 SwiftUI 이름.

extension Color {
    static let brand = Color(light: 0x0097E4, dark: 0x2EA8F0)          // 선, 스위치, 아이콘 (글자 금지)
    static let brandFill = Color(light: 0x0077B6, dark: 0x0077B6)      // 글자 있는 주 버튼 바탕
    static let brandText = Color(light: 0x0077B6, dark: 0x5CC0F5)      // 링크, 보조 버튼 글자
    static let brandTint = Color(light: 0xE5F4FC, darkRGBA: (46, 168, 240, 0.18))
    static let brandStrong = Color(light: 0x094B7B, dark: 0x8FD4F8)
    static let textPrimary = Color(light: 0x1A1A1A, dark: 0xF2F2F2)
    static let textSecondary = Color(light: 0x4D4D4D, dark: 0xABABAB)
    // 흐린 글자에도 쓰여서 대비를 올렸다: 흰 바탕 4.5:1, 다크 창 바탕 5:1 (규격표 값은 0x8C8C8C / 0x6E6E73)
    static let textDecor = Color(light: 0x767676, dark: 0x8E8E93)
    static let bgWindow = Color(light: 0xFFFFFF, dark: 0x1E1E1E)
    static let bgSidebar = Color(light: 0xF5F5F7, dark: 0x252527)
    static let bgPopover = Color(light: 0xFFFFFF, dark: 0x2A2A2C)
    static let line = Color(light: 0xE5E5E5, dark: 0x3A3A3C)
    static let lineSoft = Color(light: 0xF0F0F0, dark: 0x333336)
    static let success = Color(light: 0x28A745, dark: 0x4CD07D)
    static let successText = Color(light: 0x1E7E34, dark: 0x4CD07D)
    static let warningBg = Color(light: 0xFFF6E0, dark: 0x3A2E12)
    static let warningLine = Color(light: 0xFFC107, dark: 0x8A6A1F)
    static let warningText = Color(light: 0x5C3900, dark: 0xF5D48A)
    static let danger = Color(light: 0xEB1E1E, dark: 0xFF6B6B)
    static let dangerText = Color(light: 0xC41818, dark: 0xFF6B6B)
    // 캔버스에서 쓰는 보조 색
    static let infoBg = Color(light: 0xF2FAFE, darkRGBA: (46, 168, 240, 0.12))
    static let infoLine = Color(light: 0xB3DDF5, darkRGBA: (46, 168, 240, 0.4))
    static let segmentBg = Color(light: 0xF0F0F2, dark: 0x333336)
    static let control = Color(light: 0xCCCCCC, dark: 0x4A4A4C)
    static let disabledFill = Color(light: 0xE5E5E5, dark: 0x3A3A3C)

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark ? NSColor(hex: dark) : NSColor(hex: light)
        })
    }

    init(light: UInt32, darkRGBA: (Double, Double, Double, Double)) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.isDark
                ? NSColor(srgbRed: darkRGBA.0 / 255, green: darkRGBA.1 / 255, blue: darkRGBA.2 / 255, alpha: darkRGBA.3)
                : NSColor(hex: light)
        })
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension NSAppearance {
    var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

// MARK: - 글자 (SUIT가 없으면 Apple SD Gothic Neo)

enum Typo {
    static let onboardingTitle = font(22, .heavy)
    static let screenTitle = font(18, .heavy)
    static let sectionTitle = font(15, .bold)
    static let itemTitle = font(14, .semibold)
    static let body = font(13, .regular)
    static let bodyBold = font(13, .bold)
    static let secondary = font(12, .regular)
    static let caption = font(11.5, .regular)

    static func font(_ size: CGFloat, _ weight: Font.Weight) -> Font {
        if NSFont(name: "SUIT-Regular", size: size) != nil { return .custom("SUIT", size: size).weight(weight) }
        return .custom("Apple SD Gothic Neo", size: size).weight(weight)
    }
}

// MARK: - 버튼 4종

enum PillKind { case primary, secondary, plain, danger }

struct PillButtonStyle: ButtonStyle {
    var kind: PillKind = .primary
    var height: CGFloat = 36
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(height >= 40 ? 14 : 13, .bold))
            .padding(.horizontal, height >= 40 ? 28 : 16)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        guard isEnabled else { return .textSecondary }
        switch kind {
        case .primary: return .white
        case .secondary: return .brandText
        case .plain: return .textPrimary
        case .danger: return .dangerText
        }
    }

    private var background: Color {
        guard isEnabled else { return .disabledFill }
        switch kind {
        case .primary: return .brandFill
        case .secondary, .plain, .danger: return .bgWindow
        }
    }

    private var border: Color {
        guard isEnabled else { return .clear }
        switch kind {
        case .primary: return .clear
        case .secondary: return .brand
        case .plain: return .control
        case .danger: return .danger
        }
    }
}

/// 글자만 있는 링크형 버튼 (이전, 건너뛰기)
struct TextLinkStyle: ButtonStyle {
    var color: Color = .textPrimary
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(13, .semibold))
            .foregroundStyle(color)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

// MARK: - 카드

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    var fill: Color = .clear
    /// 같은 줄 카드끼리 높이를 맞출 때만 true (남는 높이를 채운다)
    var stretch = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
    }
}

/// 회색 바탕 카드 (테두리 없음)
struct GrayCard<Content: View>: View {
    var padding: CGFloat = 16
    var radius: CGFloat = 8
    /// 같은 줄 카드끼리 높이를 맞출 때만 true (남는 높이를 채운다)
    var stretch = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: stretch ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: radius).fill(Color.bgSidebar))
    }
}

/// 파란 안내 상자
struct InfoBox<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.infoBg))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.infoLine, lineWidth: 1))
    }
}

/// 안내 카드 (warning 색 3종)
struct Notice: View {
    var title: String
    var message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 1)
            (Text(title).bold() + Text(" " + message))
                .font(Typo.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.warningText)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.warningBg))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.warningLine, lineWidth: 1))
    }
}

/// 번호 원 (단계, 미션)
struct NumberDot: View {
    enum State { case todo, current, done }
    var text: String
    var state: State
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            switch state {
            // 다크에서도 흰 ✓가 보이게 진한 초록 고정
            case .done: Circle().fill(Color(hex: 0x28A745))
            case .current: Circle().fill(Color.brandFill)
            case .todo: Circle().strokeBorder(Color.textDecor, lineWidth: size > 22 ? 1.5 : 1)
            }
            if state == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: size > 22 ? 12 : 10, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(text)
                    .font(Typo.font(size > 22 ? 12 : 11, .heavy))
                    .foregroundStyle(state == .todo ? Color.textSecondary : .white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// 돌아가는 점선 원 (기다리는 중)
struct Spinner: View {
    var size: CGFloat = 12
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: size - 2, height: size - 2)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
            .accessibilityLabel("진행 중")
    }
}

/// 키 모양 표시 (⌃⌥⌘Space)
struct KeyCap: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Typo.bodyBold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.segmentBg))
    }
}

/// 체크박스. 시스템 `.checkbox`는 AppKit 버튼이라, 내용 크기에 맞춰 늘어나는 확인 창에서
/// 크기 계산이 끝없이 반복돼 앱이 꺼졌다 (클립보드 확인 창). 그래서 SwiftUI로 그린다.
struct BoxCheckboxStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3.5)
                    .fill(configuration.isOn ? Color.brand : Color.bgWindow)
                    .overlay(RoundedRectangle(cornerRadius: 3.5)
                        .strokeBorder(configuration.isOn ? Color.brand : Color.control, lineWidth: 1))
                    .overlay(Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .opacity(configuration.isOn ? 1 : 0))
                    .frame(width: 14, height: 14)
                configuration.label
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
    }
}

/// 여백 단계. 화면 안 간격은 이 값만 쓴다 (화면마다 제각각이던 10·14·18·20 같은 값을 정리).
/// - xs 4: 제목과 바로 붙는 부제, 아이콘과 글자
/// - s 8: 같은 묶음 안의 줄 사이, 버튼 사이
/// - m 12: 카드 안 여백(세로), 묶음 제목과 묶음
/// - l 16: 카드 안 여백(가로), 팝오버 가장자리, 카드와 카드
/// - xl 24: 섹션과 섹션, 창 가장자리
/// - xxl 32: 처음 설정처럼 큰 화면의 큰 덩어리 사이
enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}

/// 긴 설명을 접어 두는 ⓘ. 마우스를 올리거나 누르면 말풍선으로 보여준다.
/// 꼭 알아야 하는 것(할 일, 경고)은 숨기지 말고 화면에 쓴다. 왜 그런지·자세한 방식처럼 궁금할 때만 보는 것에 쓴다.
struct InfoTip: View {
    let text: String
    var size: CGFloat = 12
    @State private var shown = false
    @State private var hovering = false

    init(_ text: String, size: CGFloat = 12) {
        self.text = text
        self.size = size
    }

    var body: some View {
        Button { shown.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(hovering || shown ? Color.brandText : Color.textDecor)
                .frame(width: size + 6, height: size + 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            hovering = inside
            if inside {
                // 지나가다 스치는 것까지 띄우지 않게 잠깐 기다린다
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { if hovering { shown = true } }
            } else {
                shown = false
            }
        }
        .popover(isPresented: $shown, arrowEdge: .bottom) {
            Text(text)
                .font(Typo.secondary)
                .foregroundStyle(Color.textPrimary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 260, alignment: .leading)
                .padding(Space.m)
        }
        .help(text)
        .accessibilityLabel("도움말")
        .accessibilityValue(text)
        .accessibilityHint("누르면 설명을 보여줘요")
    }
}
