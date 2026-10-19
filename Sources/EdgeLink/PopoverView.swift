import AppKit
import EdgeLinkCore
import SwiftUI

/// 팝오버가 보여줄 상태 (캔버스 2-1 ~ 2-4)
enum PopoverState: Equatable {
    case setup
    case problem(PopoverProblem)
    case disconnected
    case connected
}

enum PopoverProblem: Equatable {
    case permission(Permissions.Kind)
    /// 1분이 지나도 권한이 켜지지 않음 (회사 정책일 수 있음)
    case policy(Permissions.Kind)
    case bluetoothOff
    case bluetoothDenied
}

/// 캡처용: 실제 설정을 건드리지 않고 상태를 정해서 그린다
struct PopoverPreview {
    var state: PopoverState
    var menuOpen = false
    /// 연결 끊김 상태에서 페어링한 기기가 없는 것처럼 (캔버스 4-3)
    var noDevice = false
}

/// 메뉴바 팝오버. 너비 360, 높이는 내용에 맞춤(최대 640).
struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissions: Permissions
    var preview: PopoverPreview?

    init(preview: PopoverPreview? = nil) { self.preview = preview }

    var body: some View {
        let state = preview?.state ?? liveState
        return VStack(alignment: .leading, spacing: 0) {
            PopoverHeader(state: state)
            content(state)
            PopoverFooter()
        }
        .frame(width: 360)
        .frame(maxHeight: 640)
        .background(Color.bgPopover)
        .foregroundStyle(Color.textPrimary)
        .noFocusRing()
    }

    private var liveState: PopoverState {
        if !settings.onboardingDone { return .setup }
        if permissions.bluetooth == .denied { return .problem(.bluetoothDenied) }
        if let k = permissions.revoked ?? permissions.firstMissing {
            return .problem(permissions.waitingTooLong ? .policy(k) : .permission(k))
        }
        if !model.bluetoothPoweredOn { return .problem(.bluetoothOff) }
        return model.isConnected ? .connected : .disconnected
    }

    @ViewBuilder private func content(_ state: PopoverState) -> some View {
        switch state {
        case .setup:
            SetupCard().padding(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
        case let .problem(p):
            ProblemCard(problem: p).padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
        case .disconnected:
            DisconnectedCard(devices: model.devices, previewNoDevice: preview?.noDevice ?? false).padding(EdgeInsets(top: 8, leading: 16, bottom: 24, trailing: 16))
        case .connected:
            ConnectedPanel(devices: model.devices, menuOpen: preview?.menuOpen ?? false)
        }
    }
}

extension View {
    /// 알약 버튼에 네모난 초점 테두리가 겹쳐 보이지 않게 한다 (macOS 14부터)
    @ViewBuilder func noFocusRing() -> some View {
        if #available(macOS 14.0, *) { focusEffectDisabled() } else { self }
    }
}

// MARK: - 팝오버 전용 색

extension Color {
    /// 문제 있음 상태 줄 (#8A4B00)
    static let warningStrong = Color(light: 0x8A4B00, dark: 0xF5C26B)
    static let warningDot = Color(light: 0xFF9500, dark: 0xFF9F0A)
    /// 조작 기기 전환 바탕과 고른 칸
    static let segmentTrack = Color(light: 0xF0F0F2, dark: 0x1E1E20)
    static let segmentOn = Color(light: 0xFFFFFF, dark: 0x48484A)
    /// 배치 미리보기 모니터
    static let screenFill = Color(light: 0xE3F2FB, dark: 0x1F3A4D)
    static let switchOff = Color(light: 0xCCCCCC, dark: 0x48484A)
    static let pillBorder = Color(light: 0xCCCCCC, dark: 0x545458)
}

// MARK: - 머리

struct PopoverHeader: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    let state: PopoverState

    var body: some View {
        HStack(spacing: 12) {
            icon
            VStack(alignment: .leading, spacing: 3) {
                Text("EdgeLink").font(Typo.font(15, .bold))
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if case .connected = state {
                Button { model.openSettings() } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15))
                        .foregroundStyle(Color.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverFillStyle(radius: 8))
                .accessibilityLabel("설정 열기")
                .help("설정 열기 (⌘,)")
            }
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
    }

    private var isConnected: Bool { if case .connected = state { return true } else { return false } }
    private var isProblem: Bool { if case .problem = state { return true } else { return false } }

    private var icon: some View {
        let glyph: PhoneGlyph.Kind = isConnected ? .linked : isProblem ? .plain : .slashed
        return ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(isConnected ? Color.brand : .disabledFill)
                .frame(width: 36, height: 36)
                .overlay(
                    PhoneGlyph(kind: glyph)
                        .stroke(isConnected ? Color.white : .textSecondary,
                                style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                        .frame(width: 20, height: 20)
                )
            if isProblem {
                Circle().fill(Color.warningDot)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().strokeBorder(Color.bgPopover, lineWidth: 2))
                    .offset(x: 3, y: -3)
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder private var status: some View {
        switch state {
        case let .problem(p):
            Text(Self.problemStatus(p))
                .font(Typo.font(12, .semibold))
                .foregroundStyle(Color.warningStrong)
        default:
            HStack(spacing: 6) {
                Circle().fill(dotColor).frame(width: 8, height: 8)
                Text(statusText).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
    }

    static func problemStatus(_ p: PopoverProblem) -> String {
        switch p {
        case .permission: return "권한이 꺼져 있어요"
        case .policy: return "권한을 켤 수 없어요"
        case .bluetoothOff: return "Mac 블루투스가 꺼져 있어요"
        case .bluetoothDenied: return "블루투스 권한이 없어요"
        }
    }

    private var dotColor: Color {
        switch state {
        case .connected: return .success
        case .disconnected:
            if case .failed = model.connection { return .danger }
            return .textDecor
        default: return .textDecor
        }
    }

    private var statusText: String {
        switch state {
        case .setup: return "설정 중 · 연결된 기기 없음"
        case .disconnected:
            switch model.connection {
            case .connecting: return "연결하는 중…"
            case .pairing: return "페어링하는 중…"
            case .failed: return "연결 실패"
            default: return "연결 끊김"
            }
        case .connected:
            switch model.controlMode {
            case .mac: return "연결됨 · Mac 조작 중"
            case .phone: return "연결됨 · \(settings.profile.model.isPad ? "아이패드" : "아이폰") 조작 중"
            case .calibrating: return "연결됨 · 보정 중"
            }
        case .problem: return ""
        }
    }
}

/// 24×24 기준 아이폰 선 그림 (캔버스의 SVG와 같은 좌표)
struct PhoneGlyph: Shape {
    enum Kind { case linked, slashed, plain, plus }
    var kind: Kind

    func path(in r: CGRect) -> Path {
        let s = min(r.width, r.height) / 24
        let ox = r.midX - 12 * s, oy = r.midY - 12 * s
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * s, y: oy + y * s) }
        var path = Path(roundedRect: CGRect(x: ox + 7 * s, y: oy + 3 * s, width: 10 * s, height: 18 * s), cornerRadius: 2.5 * s)
        switch kind {
        case .linked:
            path.move(to: p(2, 12)); path.addLine(to: p(6, 12))
            path.move(to: p(4, 10)); path.addLine(to: p(6, 12)); path.addLine(to: p(4, 14))
        case .slashed:
            path.move(to: p(3, 3)); path.addLine(to: p(21, 21))
        case .plus:
            path.move(to: p(12, 8)); path.addLine(to: p(12, 13))
            path.move(to: p(9.5, 10.5)); path.addLine(to: p(14.5, 10.5))
        case .plain:
            break
        }
        return path
    }
}

// MARK: - 바닥

struct PopoverFooter: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.line).frame(height: 1)
            HStack {
                Button { model.openSettings() } label: {
                    HStack(spacing: 8) {
                        Text("설정…")
                        Text("⌘,").foregroundStyle(Color.textSecondary)
                    }
                }
                .buttonStyle(FooterButtonStyle())
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("설정")
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    HStack(spacing: 8) {
                        Text("EdgeLink 종료")
                        Text("⌘Q").foregroundStyle(Color.textSecondary)
                    }
                }
                .buttonStyle(FooterButtonStyle())
                .keyboardShortcut("q", modifiers: .command)
                .accessibilityLabel("EdgeLink 종료")
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }
}

struct FooterButtonStyle: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body)
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed || hover ? Color.segmentBg : .clear))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
    }
}

/// 마우스를 올리면 옅은 바탕이 생기는 버튼 (톱니, 메뉴 항목)
struct HoverFillStyle: ButtonStyle {
    var radius: CGFloat = 6
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: radius).fill(configuration.isPressed || hover ? Color.segmentBg : .clear))
            .onHover { hover = $0 }
    }
}

/// 크기를 정할 수 있는 글자 링크 버튼
struct LinkButtonStyle: ButtonStyle {
    var size: CGFloat = 12
    var color: Color = .brandText
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(size, .semibold))
            .foregroundStyle(isEnabled ? color : .textDecor)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .contentShape(Rectangle())
    }
}

/// 팝오버의 너비를 채우는 알약 버튼 (높이 38~40, 13pt)
struct WidePillStyle: ButtonStyle {
    var kind: PillKind = .primary
    var height: CGFloat = 38
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(13, kind == .primary ? .bold : .semibold))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: height / 2, style: .circular).fill(background))
            .overlay(RoundedRectangle(cornerRadius: height / 2, style: .circular).strokeBorder(border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(RoundedRectangle(cornerRadius: height / 2, style: .circular))
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
        return kind == .primary ? .brandFill : .clear
    }

    private var border: Color {
        guard isEnabled else { return .clear }
        switch kind {
        case .primary: return .clear
        case .secondary: return .brand
        case .plain: return .pillBorder
        case .danger: return .danger
        }
    }
}

/// 켜기/끄기 스위치 (40×24). 줄 전체를 눌러도 바뀐다.
struct PillSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        } label: {
            HStack(spacing: 12) {
                configuration.label.frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(configuration.isOn ? Color.brand : .switchOff)
                    .frame(width: 40, height: 24)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle().fill(Color.white)
                            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
                            .frame(width: 20, height: 20)
                            .padding(2)
                    }
                    .opacity(isEnabled ? 1 : 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "켬" : "끔")
    }
}

// MARK: - 2-2 설정 중

struct SetupCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissions: Permissions

    var body: some View {
        let next = model.resumeStep()
        let total = OnboardingStep.allCases.count
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("설정이 조금 남았어요").font(Typo.screenTitle)
                Text("멈춘 곳부터 이어서 하면 돼요.").font(Typo.body).foregroundStyle(Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("다음: \(next.title)").font(Typo.font(12, .bold)).foregroundStyle(Color.brandStrong)
                    Spacer()
                    Text("\(next.rawValue) / \(total)단계").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                ProgressBar(value: Double(next.rawValue) / Double(total))
                Button { model.openOnboarding() } label: { Text("설정 이어하기") }
                    .buttonStyle(WidePillStyle(height: 38))
                    .padding(.top, 2)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.infoBg))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.brand, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                checkRow(permissions.allGranted, "Mac 권한 3가지")
                checkRow(settings.onboardingStep >= OnboardingStep.test.rawValue, "아이폰 연결")
                checkRow(settings.onboardingStep >= OnboardingStep.practice.rawValue, "배치 · 연습")
            }
            .font(Typo.secondary).foregroundStyle(Color.textSecondary)
        }
    }

    private func checkRow(_ done: Bool, _ text: String) -> some View {
        HStack(spacing: 8) {
            if done {
                Text("✓").font(Typo.font(12, .bold)).foregroundStyle(Color.successText)
            } else {
                Circle().strokeBorder(Color.textDecor, lineWidth: 1.5).frame(width: 8, height: 8).padding(.horizontal, 3)
            }
            Text(text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), \(done ? "끝남" : "남음")")
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.brand.opacity(0.15))
                Capsule().fill(Color.brand).frame(width: max(6, g.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("진행 \(Int(value * 100))%")
    }
}

// MARK: - 2-4 문제 있음

struct ProblemCard: View {
    @EnvironmentObject var permissions: Permissions
    @EnvironmentObject var settings: AppSettings
    let problem: PopoverProblem
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.top, 1)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.title).font(Typo.font(14, .bold))
                        Text(copy.body).font(Typo.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(Color.warningText)
                .accessibilityElement(children: .combine)
                Button { action() } label: { Text(copied ? "복사했어요" : copy.cta) }
                    .buttonStyle(WidePillStyle(height: 38))
                Text(copy.hint).font(Typo.caption).foregroundStyle(Color.warningText).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.warningBg))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.warningLine, lineWidth: 1))

            VStack(alignment: .leading, spacing: 8) {
                Text("지금 쓸 수 없는 기능").font(Typo.font(12, .semibold)).foregroundStyle(Color.textSecondary)
                VStack(spacing: 0) {
                    let items = ["아이폰으로 전환", "모서리 전환", "클립보드 보내기"]
                    ForEach(Array(items.enumerated()), id: \.offset) { i, name in
                        HStack {
                            Text(name).font(Typo.body)
                            Spacer()
                            Text("멈춤").font(Typo.secondary)
                        }
                        .frame(minHeight: 44)
                        .accessibilityElement(children: .combine)
                        if i < items.count - 1 { Rectangle().fill(Color.lineSoft).frame(height: 1) }
                    }
                }
                .foregroundStyle(Color.textDecor)
                .padding(.horizontal, 12)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
                Text("해결되면 자동으로 다시 동작해요. 앱을 다시 켤 필요는 없어요.")
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var copy: (title: String, body: String, cta: String, hint: String) {
        switch problem {
        case .policy:
            return ("회사 정책으로 막혀 있을 수 있어요",
                    "1분이 지나도 권한이 켜지지 않았어요. 회사에서 관리하는 Mac이라면 관리자가 막아둔 걸 수 있어요.",
                    "관리자에게 보낼 내용 복사",
                    "복사되는 내용: 앱 이름, 번들 ID, 필요한 권한 3가지와 이유.")
        case let .permission(kind):
            return ("\(kind.title) 권한이 꺼졌어요",
                    "이 권한이 없으면 아이폰 조작 중에도 입력이 Mac으로 가요. 그래서 전환을 멈췄어요.",
                    "시스템 설정에서 다시 켜기",
                    "목록에서 EdgeLink를 켜주세요. 켜면 1초 안에 다시 동작해요.")
        case .bluetoothDenied:
            return ("블루투스 권한이 없어요",
                    "블루투스 권한이 있어야 아이폰에 키보드·마우스로 연결할 수 있어요.",
                    "시스템 설정에서 켜기",
                    "시스템 설정 › 개인정보 보호 및 보안 › 블루투스에서 EdgeLink를 켜주세요.")
        case .bluetoothOff:
            let name = settings.lastDeviceName.map { "기본 기기(\($0))" } ?? "기본 기기"
            return ("Mac 블루투스가 꺼져 있어요",
                    "블루투스가 켜져야 아이폰에 키보드·마우스로 연결할 수 있어요. 다시 연결 시도도 멈췄어요.",
                    "블루투스 설정 열기",
                    "켜면 \(name)에 자동으로 다시 연결해요.")
        }
    }

    private func action() {
        switch problem {
        case .policy:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Permissions.adminRequestText, forType: .string)
            copied = true
        case let .permission(kind): permissions.request(kind)
        case .bluetoothDenied: permissions.open(.bluetooth)
        case .bluetoothOff: NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        }
    }
}

// MARK: - 2-3 연결 끊김

struct DisconnectedCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissions: Permissions
    @ObservedObject var devices: DeviceDirectory
    var previewNoDevice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if settings.lastDeviceAddress == nil || previewNoDevice {
                emptyState
            } else {
                defaultDeviceCard
            }
            VStack(alignment: .leading, spacing: 8) {
                if !others.isEmpty {
                    Text("다른 기기").font(Typo.font(12, .semibold)).foregroundStyle(Color.textSecondary)
                    ForEach(others) { item in
                        Button { model.connect(address: item.address) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.kind == .pad ? "ipad" : "iphone")
                                    .font(.system(size: 14)).foregroundStyle(Color.textSecondary)
                                    .frame(width: 18)
                                Text(item.name).font(Typo.body).lineLimit(1).truncationMode(.middle)
                                Spacer()
                                Text("연결").font(Typo.font(12, .semibold)).foregroundStyle(busy ? Color.textDecor : .brandText)
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 44)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgPopover))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                        .accessibilityLabel("\(item.name) 연결")
                    }
                }
                if settings.lastDeviceAddress != nil && !previewNoDevice {
                    Button("+ 새 기기 페어링") { model.openOnboarding(at: .pairing) }
                        .buttonStyle(LinkButtonStyle(size: 12))
                        .padding(.vertical, 4)
                }
            }
        }
        .onAppear { if permissions.bluetooth == .granted { devices.reloadPaired() } }
    }

    private var busy: Bool {
        switch model.connection {
        case .connecting, .pairing: return true
        default: return false
        }
    }

    /// 페어링한 아이폰·아이패드 중 기본 기기가 아닌 것
    private var others: [DeviceDirectory.Item] {
        let mine = settings.lastDeviceAddress?.lowercased()
        return devices.items.filter { $0.paired && $0.kind != .other && $0.address.lowercased() != mine }
    }

    private var defaultDeviceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                PhoneGlyph(kind: .plain)
                    .stroke(Color.textPrimary, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(settings.lastDeviceName ?? "기본 기기").font(Typo.font(14, .bold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(subtitle).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            Button {
                if let a = settings.lastDeviceAddress { model.connect(address: a) }
            } label: {
                HStack(spacing: 8) {
                    if busy { Spinner(size: 12) }
                    Text(buttonTitle)
                }
            }
            .buttonStyle(WidePillStyle(height: 38))
            .disabled(busy)
            VStack(alignment: .leading, spacing: 6) {
                Text(reason).font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if case let .failed(message) = model.connection {
                    Text("오류: \(message)").font(Typo.caption).foregroundStyle(Color.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line, lineWidth: 1))
    }

    /// 캔버스 4-3: 페어링한 기기가 없을 때
    private var emptyState: some View {
        VStack(spacing: 12) {
            Circle().fill(Color.segmentBg).frame(width: 56, height: 56)
                .overlay(PhoneGlyph(kind: .plus)
                    .stroke(Color.textSecondary, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                    .frame(width: 26, height: 26))
                .accessibilityHidden(true)
            Text("아직 페어링한 기기가 없어요").font(Typo.font(15, .bold))
            Text("아이폰에서 설정 › Bluetooth 화면을 열어두고 아래 버튼을 누르세요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("새 기기 페어링") { model.openOnboarding(at: .pairing) }
                .buttonStyle(PillButtonStyle(height: 36))
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line, lineWidth: 1))
    }

    private var subtitle: String {
        switch model.connection {
        case .connecting: return "기본 기기 · 연결하는 중"
        case .pairing: return "기본 기기 · 페어링하는 중"
        case .failed: return "기본 기기 · 연결 실패"
        default: return "기본 기기 · 연결 끊김"
        }
    }

    private var buttonTitle: String {
        switch model.connection {
        case .connecting: return "연결하는 중…"
        case let .pairing(code): return code.map { String(format: "번호 %06d 확인 중…", $0) } ?? "페어링하는 중…"
        default: return "다시 연결"
        }
    }

    private var reason: String {
        let retry = settings.autoReconnect
            ? "자동으로 다시 시도해요."
            : "자동 다시 연결이 꺼져 있어요. 설정 › 연결에서 켤 수 있어요."
        switch model.connection {
        case .connecting, .pairing:
            return "아이폰 화면이 켜져 있고 블루투스가 켜져 있는지 확인하세요."
        case .failed:
            return "아이폰 블루투스가 꺼져 있거나 멀리 있을 수 있어요. 회사 Mac이라면 보안 정책이 블루투스 키보드를 막았을 수도 있어요. \(retry)"
        default:
            return "아이폰 블루투스가 꺼져 있거나 멀리 있을 수 있어요. \(retry)"
        }
    }
}

// MARK: - 2-1 연결됨

struct ConnectedPanel: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissions: Permissions
    @ObservedObject var devices: DeviceDirectory
    @State private var menuOpen: Bool

    init(devices: DeviceDirectory, menuOpen: Bool = false) {
        self.devices = devices
        _menuOpen = State(initialValue: menuOpen)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            controlSection
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 16, trailing: 16))
            divider
            LayoutSummary()
                .padding(16)
            divider
            toggles
                .padding(.horizontal, 16).padding(.vertical, 8)
            actions
                .padding(EdgeInsets(top: 8, leading: 16, bottom: 20, trailing: 16))
        }
        .overlay {
            if menuOpen {
                ZStack(alignment: .bottomTrailing) {
                    // 바깥을 누르면 닫는다
                    Color.clear.contentShape(Rectangle()).onTapGesture { menuOpen = false }
                    deviceMenu
                        .padding(.trailing, 16)
                        .padding(.bottom, 20 + 40 + 6)
                }
            }
        }
        .onAppear { if permissions.bluetooth == .granted { devices.reloadPaired() } }
        .onDisappear { menuOpen = false }
    }

    private var divider: some View {
        Rectangle().fill(Color.line).frame(height: 1).padding(.horizontal, 16)
    }

    private var deviceWord: String { settings.profile.model.isPad ? "iPad" : "iPhone" }
    private var toggleKey: String { (settings.hotkeys[.toggleRemote] ?? Hotkey.defaults[.toggleRemote]!).display }

    // 조작 기기 전환

    private var controlSection: some View {
        let calibrating = model.controlMode == .calibrating
        return VStack(alignment: .leading, spacing: 8) {
            Text("지금 조작 중").font(Typo.font(12, .semibold)).foregroundStyle(Color.textSecondary)
            HStack(spacing: 4) {
                segment(title: "Mac", symbol: "laptopcomputer", on: model.controlMode == .mac) {
                    model.router.returnToMac(.menu)
                }
                segment(title: deviceWord, symbol: settings.profile.model.isPad ? "ipad" : "iphone", on: model.controlMode != .mac) {
                    model.router.enterPhone(.menu)
                }
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.segmentTrack))
            .disabled(calibrating)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("조작할 기기")
            Group {
                if calibrating {
                    Text("보정 중에는 바꿀 수 없어요. 보정 도우미를 끝내면 다시 쓸 수 있어요.")
                } else if settings.edgeEnabled {
                    Text("모서리로 밀거나 ") + Text(toggleKey).font(Typo.font(12, .semibold)).foregroundColor(.textPrimary) + Text("로 전환해요.")
                } else {
                    Text("모서리 전환이 꺼져 있어요. ") + Text(toggleKey).font(Typo.font(12, .semibold)).foregroundColor(.textPrimary) + Text("로 전환해요.")
                }
            }
            .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func segment(title: String, symbol: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { if !on { action() } }) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13))
                Text(title).font(Typo.font(13, .semibold))
            }
            .foregroundStyle(on ? Color.textPrimary : .textSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(on ? Color.segmentOn : .clear)
                    .shadow(color: .black.opacity(on ? 0.14 : 0), radius: 4, y: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) 조작")
        .accessibilityAddTraits(on ? .isSelected : [])
        .help(on ? "\(title) 조작 중이에요" : "\(title) 조작으로 바꿔요 (\(toggleKey))")
    }

    // 스위치 3개

    private var toggles: some View {
        VStack(spacing: 0) {
            Toggle(isOn: $settings.edgeEnabled) { switchLabel("모서리 전환", "끄면 단축키로만 넘어가요") }
            Toggle(isOn: $settings.glassEnabled) { switchLabel("모서리 유리 효과", "밀 때 가장자리가 볼록해져요") }
            Toggle(isOn: $settings.mediaKeysToPhone) { switchLabel("미디어 키를 아이폰으로", "볼륨·재생 키를 아이폰에 보내요") }
        }
        .toggleStyle(PillSwitchStyle())
    }

    private func switchLabel(_ title: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Typo.font(13, .semibold))
            Text(hint).font(Typo.secondary).foregroundStyle(Color.textSecondary)
        }
        .frame(minHeight: 52)
        .accessibilityElement(children: .combine)
    }

    // 클립보드 보내기, 기기 선택

    private var actions: some View {
        HStack(spacing: 8) {
            if settings.clipboardTypingAllowed {
                Button { model.requestClipboardSend() } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.on.clipboard").font(.system(size: 13))
                        Text("클립보드 보내기")
                    }
                }
                .buttonStyle(WidePillStyle(kind: .secondary, height: 40))
                .accessibilityLabel("클립보드 보내기")
                .help("클립보드의 영문·숫자·기호를 아이폰에 타이핑해요 (\((settings.hotkeys[.sendClipboard] ?? Hotkey.defaults[.sendClipboard]!).display))")
            }
            Button { menuOpen.toggle() } label: {
                HStack(spacing: 6) {
                    Text(model.connectedName ?? deviceWord).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold))
                        .rotationEffect(.degrees(menuOpen ? 180 : 0))
                }
            }
            .buttonStyle(WidePillStyle(kind: .plain, height: 40))
            .accessibilityLabel("기기 선택, \(model.connectedName ?? deviceWord) 연결됨")
        }
    }

    private var others: [DeviceDirectory.Item] {
        let mine = settings.lastDeviceAddress?.lowercased()
        return devices.items.filter { $0.paired && $0.kind != .other && $0.address.lowercased() != mine }
    }

    private var deviceMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuRow(check: true, title: model.connectedName ?? deviceWord, trailing: "연결됨", selected: true) {
                menuOpen = false
            }
            .accessibilityLabel("\(model.connectedName ?? deviceWord), 연결됨")
            ForEach(others) { item in
                MenuRow(check: false, title: item.name, trailing: "연결") {
                    menuOpen = false
                    model.disconnect()
                    model.connect(address: item.address)
                }
                .accessibilityLabel("\(item.name)에 연결")
            }
            Rectangle().fill(Color.lineSoft).frame(height: 1).padding(.vertical, 4)
            MenuRow(title: "새 기기 페어링…") {
                menuOpen = false
                model.openOnboarding(at: .pairing)
            }
            MenuRow(title: "연결 끊기") {
                menuOpen = false
                model.disconnect()
            }
        }
        .padding(6)
        .frame(width: 220)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgPopover))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line, lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 15, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("기기 선택")
    }
}

struct MenuRow: View {
    var check: Bool? = nil
    var title: String
    var trailing: String? = nil
    var selected = false
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let check {
                    Text(check ? "✓" : "").font(Typo.font(13, .semibold)).frame(width: 14)
                }
                Text(title).font(Typo.font(13, selected ? .semibold : .regular))
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let trailing {
                    Text(trailing).font(Typo.caption).foregroundStyle(selected ? Color.brandStrong : .textSecondary)
                }
            }
            .foregroundStyle(selected ? Color.brandStrong : .textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Color.brandTint : hover ? Color.segmentBg : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: 배치 미리보기

struct LayoutSummary: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        let placement = model.currentPlacement
        HStack(spacing: 16) {
            MiniArrangement(screens: model.screens, placement: placement, landscape: settings.profile.landscape)
                .frame(width: 112, height: 64)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title(placement)).font(Typo.font(13, .semibold)).lineLimit(1).truncationMode(.middle)
                Text(subtitle(placement)).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(placement == nil ? "배치 정하기 >" : "배치 변경 >") { model.openSettings(.layout) }
                    .buttonStyle(LinkButtonStyle(size: 12))
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func title(_ p: Placement?) -> String {
        if let p { return p.label }
        return settings.phoneLayout == nil ? "아이폰 자리를 정하지 않았어요" : "저장한 모니터가 없어요"
    }

    private func subtitle(_ p: Placement?) -> String {
        let count = "모니터 \(model.screens.count)대"
        guard p != nil else { return "\(count) · 지금은 단축키로만 넘어가요" }
        return settings.edgeEnabled ? "\(count) · 파란 구간에서 넘어가요" : "\(count) · 모서리 전환이 꺼져 있어요"
    }
}

/// 팝오버용 작은 배치도 (112×64). 모니터, 파란 구간, 아이폰.
struct MiniArrangement: View {
    let screens: [ScreenInfo]
    let placement: Placement?
    var landscape = false

    var body: some View {
        GeometryReader { geo in
            let box = bounds
            let pw: CGFloat = landscape ? 26 : 12, ph: CGFloat = landscape ? 12 : 26
            let edge = placement?.edge
            let extraX: CGFloat = edge == .left || edge == .right ? pw + 4 : 0
            let extraY: CGFloat = edge == .top || edge == .bottom ? ph + 4 : 0
            let scale = min((geo.size.width - extraX) / max(box.width, 1), (geo.size.height - extraY) / max(box.height, 1))
            let groupW = box.width * scale + extraX, groupH = box.height * scale + extraY
            let ox = (geo.size.width - groupW) / 2 + (edge == .left ? extraX : 0)
            let oy = (geo.size.height - groupH) / 2 + (edge == .top ? extraY : 0)
            let map: (Double, Double) -> CGPoint = { x, y in
                CGPoint(x: ox + (x - box.minX) * scale, y: oy + (box.maxY - y) * scale)
            }
            ZStack(alignment: .topLeading) {
                ForEach(screens) { s in
                    let tl = map(s.frame.x, s.frame.maxY)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.screenFill)
                        .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Color.textDecor, lineWidth: 1))
                        .frame(width: s.frame.width * scale, height: s.frame.height * scale)
                        .offset(x: tl.x, y: tl.y)
                }
                if let p = placement {
                    let (gate, phone) = rects(p, map: map, pw: pw, ph: ph)
                    Capsule().fill(Color.brand)
                        .frame(width: gate.width, height: gate.height)
                        .offset(x: gate.minX, y: gate.minY)
                    RoundedRectangle(cornerRadius: 3).fill(Color.textPrimary)
                        .frame(width: phone.width, height: phone.height)
                        .offset(x: phone.minX, y: phone.minY)
                }
            }
        }
    }

    private var bounds: (minX: Double, maxY: Double, width: Double, height: Double) {
        guard !screens.isEmpty else { return (0, 1, 1, 1) }
        let minX = screens.map(\.frame.x).min()!, maxX = screens.map(\.frame.maxX).max()!
        let minY = screens.map(\.frame.y).min()!, maxY = screens.map(\.frame.maxY).max()!
        return (minX, maxY, maxX - minX, maxY - minY)
    }

    private func rects(_ p: Placement, map: (Double, Double) -> CGPoint, pw: CGFloat, ph: CGFloat) -> (CGRect, CGRect) {
        let f = p.screen.frame
        let mid = (p.passage.start + p.passage.end) / 2
        switch p.edge {
        case .right, .left:
            let x = p.edge == .right ? f.maxX : f.x
            let a = map(x, p.passage.end), b = map(x, p.passage.start), c = map(x, mid)
            let gate = CGRect(x: a.x - 2, y: a.y, width: 4, height: max(b.y - a.y, 4))
            let px = p.edge == .right ? c.x + 4 : c.x - 4 - pw
            return (gate, CGRect(x: px, y: c.y - ph / 2, width: pw, height: ph))
        case .top, .bottom:
            let y = p.edge == .top ? f.maxY : f.y
            let a = map(p.passage.start, y), b = map(p.passage.end, y), c = map(mid, y)
            let gate = CGRect(x: a.x, y: a.y - 2, width: max(b.x - a.x, 4), height: 4)
            let py = p.edge == .bottom ? c.y + 4 : c.y - 4 - ph
            return (gate, CGRect(x: c.x - pw / 2, y: py, width: pw, height: ph))
        }
    }
}
