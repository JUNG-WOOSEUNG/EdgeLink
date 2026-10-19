import AppKit
import SwiftUI

/// 설정 창 860×640, 탭 5개 (캔버스 3-1, 3-2)
final class SettingsWindowController: NSObject, NSWindowDelegate {
    unowned let model: AppModel
    /// 설정 창에서 보여줄 탭. 창이 열려 있을 때 show(tab:)로 바꾼다.
    let state = SettingsWindowState()
    private var window: NSWindow?
    private var gestureWindow: NSWindow?
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        super.init()
        installKeyMonitor()
    }

    deinit {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
    }

    func show(tab: SettingsTab = .general) {
        state.tab = tab
        if window == nil {
            let root = SettingsView(state: state)
                .environmentObject(model)
                .environmentObject(model.settings)
                .environmentObject(model.permissions)
                .environmentObject(model.devices)
            let w = makeWindow(root, size: NSSize(width: 860, height: 640), title: "EdgeLink 설정", toolbar: true)
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 아이폰 버튼 등록 도우미 창 (720×560, 캔버스 1-9). AppDialog.gestureSetup이 이걸 부른다.
    func showGestureSetup() {
        if gestureWindow == nil {
            let root = GestureSetupView(onClose: { [weak self] in self?.gestureWindow?.close() })
                .environmentObject(model)
                .environmentObject(model.settings)
            gestureWindow = makeWindow(root, size: NSSize(width: 720, height: 560), title: "아이폰 버튼 등록", toolbar: false)
        }
        NSApp.activate(ignoringOtherApps: true)
        gestureWindow?.makeKeyAndOrderFront(nil)
    }

    /// 제목 표시줄이 내용 위에 겹치는 고정 크기 창.
    /// 내용 크기가 아니라 창 전체 크기를 고정한다 (SwiftUI가 제목 표시줄 높이를 더해 아래에 빈 띠가 생겼었음).
    private func makeWindow<V: View>(_ root: V, size: NSSize, title: String, toolbar: Bool) -> NSWindow {
        let host = NSHostingController(rootView: root)
        host.sizingOptions = []
        let w = NSWindow(contentViewController: host)
        w.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.title = title
        if toolbar {
            // 빈 통합 도구 막대: 제목 표시줄이 52pt가 되어 신호등 버튼이 사이드바 머리 가운데에 온다 (캔버스 3-1)
            let bar = NSToolbar(identifier: "EdgeLinkSettings")
            bar.showsBaselineSeparator = false
            w.toolbar = bar
            w.toolbarStyle = .unified
            w.titlebarSeparatorStyle = .none
        }
        w.setFrame(NSRect(origin: .zero, size: size), display: false)
        w.minSize = size
        w.maxSize = size
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        return w
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? NSWindow else { return }
        // 단축키를 기록하던 중이면 끝낸다. 로컬 키 모니터가 남으면 앱 전체 keyDown을 삼키고,
        // isRecording이 남으면 InputRouter가 Mac 조작 단축키를 계속 무시한다.
        if w === window { HotkeyRecorderState.end() }
        // 다음에 열 때 새로 만들어서 각 화면의 onAppear가 다시 불리게 한다
        if w === window { DispatchQueue.main.async { self.window = nil } }
        if w === gestureWindow { DispatchQueue.main.async { self.gestureWindow = nil } }
    }

    /// 메뉴 막대가 없는 앱이라 ⌘, 와 ⌘W를 직접 받는다. 앱 창이 앞에 있을 때만 동작한다.
    private func installKeyMonitor() {
        guard Snapshot.directory == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !HotkeyRecorderState.isRecording else { return event }
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
            guard mods == .command else { return event }
            switch event.charactersIgnoringModifiers {
            case ",":
                self.show(tab: self.state.tab)
                return nil
            case "w":
                if let key = NSApp.keyWindow, key === self.window || key === self.gestureWindow {
                    key.performClose(nil)
                    return nil
                }
                return event
            default:
                return event
            }
        }
    }
}

final class SettingsWindowState: ObservableObject {
    @Published var tab: SettingsTab = .general
}

// MARK: - 창 내용

struct SettingsView: View {
    @ObservedObject var state: SettingsWindowState
    /// 캡처용: 탭 내용을 바꿔 보여준다 (빈 상태 등)
    var override: AnyView?

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(tab: $state.tab)
            VStack(spacing: 0) {
                Text(state.tab.title)
                    .font(Typo.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52, alignment: .leading)
                Rectangle().fill(Color.line).frame(height: 1)
                ScrollView {
                    tabContent
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .id(state.tab) // 탭을 바꾸면 맨 위부터
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.bgWindow)
        }
        // 높이를 고정하지 않고 창을 채운다
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.textPrimary)
        .ignoresSafeArea()
    }

    @ViewBuilder private var tabContent: some View {
        if let override {
            override
        } else {
            defaultContent
        }
    }

    @ViewBuilder private var defaultContent: some View {
        switch state.tab {
        case .general: GeneralTab()
        case .layout: LayoutTab()
        case .input: InputTab()
        case .connection: ConnectionTab()
        case .about: AboutTab()
        }
    }
}

struct SettingsSidebar: View {
    @Binding var tab: SettingsTab

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 52) // 신호등 버튼 자리
            ForEach(SettingsTab.allCases) { t in
                Button { tab = t } label: {
                    HStack(spacing: 10) {
                        Image(systemName: t.symbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5).fill(t == tab ? Color.brandFill : Color.textDecor))
                        Text(t.title).font(Typo.font(13, .semibold))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 36)
                    .foregroundStyle(t == tab ? Color.brandStrong : .textPrimary)
                    .background(RoundedRectangle(cornerRadius: 8).fill(t == tab ? Color.sidebarSelected : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("\(t.title) 설정")
                .accessibilityAddTraits(t == tab ? .isSelected : [])
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 200)
        .frame(maxHeight: .infinity)
        .background(Color.bgSidebar)
        .overlay(alignment: .trailing) { Rectangle().fill(Color.line).frame(width: 1) }
    }
}

extension SettingsTab {
    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .layout: return "rectangle.on.rectangle"
        case .input: return "keyboard"
        case .connection: return "antenna.radiowaves.left.and.right"
        case .about: return "info"
        }
    }
}

// MARK: - 설정 창 부품

extension Color {
    /// 설정 카드 바탕: 라이트는 흰색(테두리만), 다크는 사이드바 색 (캔버스 5-2)
    static let settingsCard = Color(light: 0xFFFFFF, dark: 0x252527)
    static let sidebarSelected = Color(light: 0xDCEFFA, darkRGBA: (46, 168, 240, 0.18))
    static let segmentSelected = Color(light: 0xFFFFFF, dark: 0x48484A)
    static let switchOff = Color(light: 0xCCCCCC, dark: 0x48484A)
    static let errorBg = Color(light: 0xFFF0F0, darkRGBA: (255, 107, 107, 0.14))
}

/// 카드 위 작은 제목 (12 / 600)
struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text)
            .font(Typo.font(12, .semibold))
            .foregroundStyle(Color.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 줄 여러 개를 담는 테두리 카드 (좌우 16, 줄 사이 구분선)
struct SettingsGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.settingsCard))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
    }
}

/// 안쪽 16 카드 (전환 감도, 기기 같은 단독 항목)
struct SettingsCard<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: spacing) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.settingsCard))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
    }
}

struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.lineSoft).frame(height: 1) }
}

/// 항목 이름(14/600) + 설명(12)
struct RowText: View {
    var title: String
    var hint: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Typo.itemTitle)
            if let hint {
                Text(hint).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 스위치 줄 (최소 높이 60)
struct ToggleRow<Trailing: View>: View {
    var title: String
    var hint: String?
    @Binding var isOn: Bool
    /// 스위치 왼쪽에 붙는 것 (제스처 버튼 번호 등)
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            RowText(title: title, hint: hint)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
            Toggle(title, isOn: $isOn)
                .toggleStyle(SettingsSwitchStyle())
                .labelsHidden()
                .accessibilityLabel(title)
                .accessibilityHint(hint ?? "")
        }
        .padding(.vertical, 12)
        .frame(minHeight: 60)
    }
}

extension ToggleRow where Trailing == EmptyView {
    init(title: String, hint: String? = nil, isOn: Binding<Bool>) {
        self.init(title: title, hint: hint, isOn: isOn) { EmptyView() }
    }
}

/// 40×24 스위치 (캔버스 3-1). 꺼짐은 회색, 켜짐은 brand.
struct SettingsSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let on = configuration.isOn
        ZStack(alignment: on ? .trailing : .leading) {
            Capsule().fill(on ? Color.brand : Color.switchOff)
            Circle().fill(Color.white)
                .shadow(color: Color(hex: 0x333333).opacity(0.16), radius: 4, y: 2)
                .frame(width: 20, height: 20)
                .padding(2)
        }
        .frame(width: 40, height: 24)
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(Capsule())
        .onTapGesture {
            guard isEnabled else { return }
            withAnimation(.easeOut(duration: 0.15)) { configuration.isOn.toggle() }
        }
        .accessibilityElement()
        .accessibilityValue(on ? "켜짐" : "꺼짐")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { if isEnabled { configuration.isOn.toggle() } }
    }
}

/// 세그먼트 (바탕 #F0F0F2, 선택은 흰색 + 작은 그림자, 높이 36)
struct SegmentedChoice<T: Hashable>: View {
    var label: String
    var options: [(value: T, title: String)]
    @Binding var selection: T
    var height: CGFloat = 36

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options.indices, id: \.self) { i in
                let o = options[i]
                let on = o.value == selection
                Button { selection = o.value } label: {
                    Text(o.title)
                        .font(Typo.font(13, .semibold))
                        .foregroundStyle(on ? Color.textPrimary : .textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: height - 8)
                        .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.segmentSelected : .clear)
                            .shadow(color: Color(hex: 0x333333).opacity(on ? 0.16 : 0), radius: 4, y: 2))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .accessibilityLabel("\(label): \(o.title)")
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.segmentBg))
    }
}

/// 설정 창 알약 버튼. 누를 수 없을 때도 원래 모양(테두리·색)을 그대로 두고 불투명도만 0.4로 낮춘다.
/// (PillButtonStyle은 회색 채움으로 바뀌어서 어떤 버튼인지 알아보기 어렵다)
struct DimmablePillStyle: ButtonStyle {
    var kind: PillKind = .primary
    var height: CGFloat = 36
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(height >= 40 ? 14 : 13, .bold))
            .padding(.horizontal, height >= 40 ? 28 : 16)
            .frame(height: height)
            .foregroundStyle(foreground)
            .background(Capsule().fill(kind == .primary ? Color.brandFill : .bgWindow))
            .overlay(Capsule().strokeBorder(border, lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4)
            .contentShape(Capsule())
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return .brandText
        case .plain: return .textPrimary
        case .danger: return .dangerText
        }
    }

    private var border: Color {
        switch kind {
        case .primary: return .clear
        case .secondary: return .brand
        case .plain: return .control
        case .danger: return .danger
        }
    }
}

/// 누를 수 없는 버튼 바로 아래에 쓰는 이유 한 줄
struct DisabledReason: View {
    var text: String
    var body: some View {
        Text(text).font(Typo.caption).foregroundStyle(Color.textSecondary)
    }
}

/// 상태 점 (색만으로 구분하지 않게 항상 글자와 같이 쓴다)
struct StatusDot: View {
    var color: Color
    var body: some View { Circle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true) }
}
