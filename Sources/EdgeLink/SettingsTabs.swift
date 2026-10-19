import AppKit
import EdgeLinkCore
import SwiftUI

// 설정 창 탭: 일반 · 배치 · 연결 · 정보 (입력은 SettingsInputTab.swift). 캔버스 3-1, 3-2, 5-2.

// MARK: - 일반

struct GeneralTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var loginOn = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            SettingsGroup {
                ToggleRow(title: "로그인할 때 자동 실행", hint: "Mac을 켜면 바로 아이폰과 연결돼요",
                          isOn: Binding(get: { loginOn }, set: { on in
                              model.setLoginItem(on)
                              loginOn = model.loginItemEnabled
                          }))
                RowDivider()
                ToggleRow(title: "모서리 유리 효과", hint: "밀 때 가장자리가 볼록하게 부풀어요", isOn: $settings.glassEnabled)
                RowDivider()
                ToggleRow(title: "전환할 때 소리", hint: "넘어가고 돌아올 때 짧은 효과음을 내요", isOn: $settings.soundEnabled)
            }

            SettingsCard {
                RowText(title: "전환 감도", hint: "모서리를 얼마나 밀어야 아이폰으로 넘어갈지 정해요. 자꾸 실수로 넘어가면 오른쪽으로 옮기세요.")
                HStack(spacing: 12) {
                    Text("살짝").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    Slider(value: $settings.sensitivityValue, in: 0...1)
                        .tint(Color.brand)
                        .accessibilityLabel("전환 감도")
                        .accessibilityValue("\(Int((settings.sensitivityValue * 100).rounded()))퍼센트")
                    Text("꾹").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                .padding(.top, 2)
            }

            SettingsCard {
                RowText(title: "메뉴바 표시", hint: "기기 이름은 아이폰이 연결됐을 때만 보여요")
                SegmentedChoice(label: "메뉴바 표시",
                                options: [(false, "아이콘만"), (true, "아이콘 + 기기 이름")],
                                selection: $settings.showDeviceNameInMenuBar)
                    .padding(.top, 2)
            }
        }
        .onAppear { loginOn = model.loginItemEnabled }
    }
}

// MARK: - 배치

struct LayoutTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    /// 캡처용: 놓을 수 있는 자리를 바꿔 보여준다 (빈 상태 등)
    var previewPlacements: [Placement]?
    @State private var dismissedConflict: String?

    private var placements: [Placement] { previewPlacements ?? model.placements }
    /// 저장한 자리. 저장한 모니터가 없으면 nil.
    private var saved: Placement? { Layout.find(settings.phoneLayout, in: placements) }
    /// 배치도에 보여줄 자리 (저장한 자리가 없으면 임시로 쓰는 기본 위치)
    private var shown: Placement? { saved ?? Layout.defaultPlacement(placements) }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if placements.isEmpty {
                emptyState
            } else {
                arrangement
            }
            deviceCard
            calibrationCard
            Button("온보딩 다시 보기 ›") { model.openOnboarding(at: .welcome) }
                .buttonStyle(TextLinkStyle(color: .brandText))
                .accessibilityLabel("온보딩 다시 보기")
        }
        .onAppear { if previewPlacements == nil { model.reloadScreens() } }
    }

    // 배치도 + 자리 고르기 + 상태
    private var arrangement: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("아이폰을 실제로 놓은 쪽 모니터 가장자리를 고르세요. 파란 구간을 밀면 아이폰으로 넘어가요.")
                .font(Typo.body).foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            ArrangementView(screens: model.screens, placements: placements, selected: shown, landscape: settings.profile.landscape)
                .frame(height: 240)
            FlowRow(spacing: 8) {
                ForEach(placements) { p in
                    Button(label(p)) {
                        settings.phoneLayout = PhoneLayout(screenID: p.screen.id, edge: p.edge, offset: p.passage.start)
                    }
                    .buttonStyle(OptionChipStyle(on: p == shown))
                    .focusable(false)
                    .accessibilityLabel("아이폰 위치: \(p.label)")
                    .accessibilityAddTraits(p == shown ? .isSelected : [])
                }
            }
            if let p = shown { status(p) }
            if settings.phoneLayout != nil, saved == nil {
                Notice(title: "저장한 모니터가 연결돼 있지 않아요.", message: "그동안은 임시로 \(shown.map(label) ?? "다른 빈 모서리")를 써요. 모니터를 다시 연결하면 원래 자리로 돌아가요.")
            }
            if let p = shown, let conflict = Layout.conflict(p), dismissedConflict != p.id {
                conflictCard(p, title: conflict)
            }
        }
    }

    private func status(_ p: Placement) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                StatusDot(color: .success)
                (Text("모니터 \(model.screens.count)대 · 아이폰: ") + Text(p.label).fontWeight(.semibold))
                    .font(Typo.body)
            }
            Text("\(Self.direction(p.edge))으로 밀면 아이폰으로 넘어가고, 반대로 밀면 Mac으로 돌아와요. 꼭짓점 근처는 핫 코너와 겹치지 않게 비워둬요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16)
        }
        .accessibilityElement(children: .combine)
    }

    static func direction(_ e: ScreenEdge) -> String {
        switch e {
        case .left: return "왼쪽"
        case .right: return "오른쪽"
        case .top: return "위쪽"
        case .bottom: return "아래쪽"
        }
    }

    /// Dock · 메뉴 막대와 같은 쪽 (캔버스 3-2 모니터 아래)
    private func conflictCard(_ p: Placement, title: String) -> some View {
        let isDock = title.hasPrefix("Dock")
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 15, weight: .semibold))
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(title.replacingOccurrences(of: ".", with: "")).font(Typo.font(13, .semibold))
                Text(isDock
                     ? "밀 때 Dock이 먼저 나타날 수 있어서, 이 위치는 조금 더 길게 밀어야 넘어가요. 넘어가는 순간 Dock은 바로 닫혀요."
                     : "밀 때 메뉴 막대가 먼저 나타날 수 있어서, 이 위치는 조금 더 길게 밀어야 넘어가요.")
                    .font(Typo.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    if isDock {
                        Button("Dock 위치 설정 열기") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")!)
                        }
                        .buttonStyle(WarningButtonStyle(filled: true))
                    }
                    Button("이대로 쓸게요") { dismissedConflict = p.id }
                        .buttonStyle(WarningButtonStyle(filled: false))
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.warningText)
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.warningBg))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.warningLine, lineWidth: 1))
    }

    /// 놓을 모서리가 없을 때 (캔버스 4-3)
    private var emptyState: some View {
        SettingsCard(spacing: 16) {
            ArrangementView(screens: model.screens, placements: [], selected: nil, landscape: false)
                .frame(height: 140)
            HStack(alignment: .top, spacing: 10) {
                StatusDot(color: .danger).padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text("아이폰을 놓을 수 있는 모서리가 없어요").font(Typo.font(14, .bold))
                    Text("모든 모서리가 다른 모니터와 맞닿아 있거나 너무 짧아요. 시스템 설정에서 모니터 배치를 바꿔 바깥쪽 모서리를 만들어주세요. 그동안은 단축키로만 넘어갈 수 있어요.")
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Button("디스플레이 설정 열기") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
            }
            .buttonStyle(PillButtonStyle(kind: .secondary, height: 34))
        }
    }

    // 기기 모델 · 방향
    private var deviceCard: some View {
        SettingsCard(spacing: 12) {
            RowText(title: "기기", hint: "배치도의 아이폰 크기와 돌아오는 위치 계산에 쓰여요. 기기마다 따로 저장돼요. 아이폰 화면 회전 잠금을 켜두면 위치가 어긋나지 않아요.")
            HStack(spacing: 12) {
                Text("모델").font(Typo.body).foregroundStyle(Color.textSecondary)
                Picker("모델", selection: modelBinding) {
                    Text("자동 (\(inferred.label))").tag(DeviceProfile.Model?.none)
                    Divider()
                    ForEach(DeviceProfile.Model.allCases) { Text($0.label).tag(DeviceProfile.Model?.some($0)) }
                }
                .labelsHidden()
                .frame(width: 220)
                .accessibilityLabel("기기 모델")
                Spacer(minLength: 12)
                SegmentedChoice(label: "아이폰 방향", options: [(false, "세로"), (true, "가로")], selection: $settings.profile.landscape)
                    .frame(width: 160)
            }
            .padding(.top, 2)
        }
    }

    /// 이름으로 고른 모델 (모르면 지금 값)
    private var inferred: DeviceProfile.Model {
        DeviceProfile.Model.infer(from: settings.lastDeviceName) ?? (settings.profile.manual ? .iPhone : settings.profile.model)
    }

    /// nil = 자동 (이름으로 고름)
    private var modelBinding: Binding<DeviceProfile.Model?> {
        Binding(get: { settings.profile.manual ? settings.profile.model : nil }, set: { m in
            if let m {
                settings.profile.model = m
                settings.profile.manual = true
            } else {
                settings.profile.model = inferred
                settings.profile.manual = false
            }
        })
    }

    // 포인터 보정
    private var calibrationCard: some View {
        SettingsCard(spacing: 12) {
            RowText(title: "아이폰 포인터 이동 보정", hint: "Mac으로 돌아오는 위치가 어긋날 때 조절해요. 보정 도우미를 쓰면 자동으로 맞춰줘요.")
            HStack(spacing: 12) {
                Text("작게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                Slider(value: $settings.unitsPerPointValue, in: 0.6...4.0)
                    .tint(Color.brand)
                    .accessibilityLabel("포인터 이동 보정")
                    .accessibilityValue(String(format: "%.2f", settings.unitsPerPoint))
                Text("크게").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                Button("보정 도우미") { model.present(.calibration) }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .disabled(!model.isConnected)
                    .padding(.leading, 4)
            }
            HStack(spacing: 8) {
                Text("지금 값 \(String(format: "%.2f", settings.unitsPerPoint)) · 기본 2.00")
                    .font(Typo.caption).foregroundStyle(Color.textSecondary)
                if abs(settings.unitsPerPoint - 2.0) > 0.005 {
                    Button("기본값으로") { settings.unitsPerPointValue = 2.0 }
                        .buttonStyle(TextLinkStyle(color: .brandText))
                        .font(Typo.caption)
                }
                Spacer()
                if !model.isConnected { DisabledReason(text: "아이폰을 연결하면 쓸 수 있어요") }
            }
        }
    }

    /// 모니터가 하나면 "화면 오른쪽"처럼 모서리만
    private func label(_ p: Placement) -> String {
        Set(placements.map(\.screen.id)).count > 1 ? p.label : "화면 \(p.edge.label)"
    }
}

/// 안내 카드 안 버튼 (캔버스 3-2: 테두리 #7A4B00, 글자 warningText)
struct WarningButtonStyle: ButtonStyle {
    var filled: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(12, .semibold))
            .foregroundStyle(Color.warningText)
            .padding(.horizontal, filled ? 14 : 6)
            .frame(height: 32)
            .background(Capsule().fill(filled ? Color.bgWindow : .clear))
            .overlay(Capsule().strokeBorder(filled ? Color.warningText.opacity(0.7) : .clear, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

// MARK: - 연결

struct ConnectionTab: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var devices: DeviceDirectory
    /// 캡처용: 기기 목록과 기본 기기 주소를 바꿔 보여준다
    var preview: (items: [DeviceDirectory.Item], defaultAddress: String?)?

    private var defaultAddress: String? { preview?.defaultAddress ?? settings.lastDeviceAddress }

    /// 페어링된 아이폰·아이패드 (기본 기기는 이름으로 종류를 몰라도 보여준다)
    private var items: [DeviceDirectory.Item] {
        let all = preview?.items ?? devices.items
        return all.filter { $0.paired && ($0.kind != .other || same($0.address, defaultAddress)) }
            .sorted { (same($0.address, defaultAddress) ? 0 : 1, $0.name) < (same($1.address, defaultAddress) ? 0 : 1, $1.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "기기")
                if items.isEmpty {
                    emptyState
                } else {
                    SettingsGroup {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            if i > 0 { RowDivider() }
                            row(item)
                        }
                    }
                    HStack {
                        Button("+ 새 기기 페어링") { model.openOnboarding(at: .pairing) }
                            .buttonStyle(TextLinkStyle(color: .brandText))
                            .accessibilityLabel("새 기기 페어링")
                            .frame(height: 32)
                        Spacer()
                        if !model.bluetoothPoweredOn { DisabledReason(text: "Mac 블루투스를 켜면 연결할 수 있어요") }
                    }
                }
            }

            SettingsGroup {
                ToggleRow(title: "기본 기기만 연결 허용", hint: "다른 기기가 연결해 오면 허용할지 물어봐요", isOn: $settings.onlyDefaultDevice)
                if !settings.onlyDefaultDevice {
                    Notice(title: "확인 없이 연결돼요.", message: "페어링한 다른 기기가 연결해 오면 묻지 않고 받아서, 키보드와 트랙패드 입력이 그 기기로 갈 수 있어요. 꼭 필요할 때만 끄세요.")
                        .padding(.bottom, 14)
                }
                RowDivider()
                ToggleRow(title: "자동으로 다시 연결", hint: "앱을 켜거나 깨어날 때 기본 기기에 연결해요. 실패가 이어지면 간격을 늘려요",
                          isOn: Binding(get: { settings.autoReconnectValue }, set: { on in
                              settings.autoReconnectValue = on
                              model.hid.autoReconnect = on
                          }))
                RowDivider()
                ToggleRow(title: "잠자기 중엔 연결 끊기", hint: "배터리를 아끼기 위해 Mac이 잠들면 끊어요", isOn: $settings.disconnectOnSleep)
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "문제 해결")
                HStack(spacing: 8) {
                    Button("연결 로그 보기") { model.present(.connectionLog) }
                        .buttonStyle(PillButtonStyle(kind: .plain))
                    Button("페어링 초기화") { model.present(.resetPairing) }
                        .buttonStyle(PillButtonStyle(kind: .danger))
                }
            }
        }
        .onAppear { if preview == nil { devices.reloadPaired() } }
    }

    private func same(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b else { return false }
        return a.lowercased() == b.lowercased()
    }

    private enum RowState { case connected, connecting, failed, idle }

    private func state(_ item: DeviceDirectory.Item) -> RowState {
        let target = model.connectingAddress ?? defaultAddress
        switch model.connection {
        case .connected: return same(item.address, defaultAddress) ? .connected : .idle
        case .connecting, .pairing: return same(item.address, target) ? .connecting : .idle
        case .failed: return same(item.address, target) ? .failed : .idle
        case .idle: return .idle
        }
    }

    private func row(_ item: DeviceDirectory.Item) -> some View {
        let st = state(item)
        let isDefault = same(item.address, defaultAddress)
        let status: String = {
            switch st {
            case .connected: return isDefault ? "연결됨 · 기본 기기" : "연결됨"
            case .connecting: return "연결 중…"
            case .failed: return isDefault ? "연결하지 못했어요 · 기본 기기" : "연결하지 못했어요"
            case .idle: return isDefault ? "페어링됨 · 기본 기기" : "페어링됨"
            }
        }()
        return HStack(spacing: 12) {
            Image(systemName: item.kind == .pad ? "ipad" : "iphone")
                .font(.system(size: 18))
                .foregroundStyle(Color.textSecondary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(Typo.itemTitle)
                HStack(spacing: 6) {
                    if st == .connecting { Spinner(size: 11) }
                    Text(status).font(Typo.secondary)
                        .foregroundStyle(st == .connected ? Color.successText : st == .failed ? .dangerText : .textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            switch st {
            case .connected:
                Button("연결 끊기") { model.disconnect() }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 32))
                    .accessibilityLabel("\(item.name) 연결 끊기")
            case .connecting:
                Button("취소") { model.disconnect() }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 32))
                    .accessibilityLabel("\(item.name) 연결 취소")
            case .failed, .idle:
                Button("연결") { model.connect(address: item.address) }
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 32))
                    .disabled(!model.bluetoothPoweredOn)
                    .accessibilityLabel("\(item.name) 연결")
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 60)
    }

    /// 페어링된 기기가 없을 때 (캔버스 4-3)
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone")
                .font(.system(size: 24))
                .foregroundStyle(Color.textSecondary)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.textSecondary)
                        .background(Circle().fill(Color.segmentBg))
                        .offset(x: 6, y: 3)
                }
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.segmentBg))
                .accessibilityHidden(true)
            Text("아직 페어링한 기기가 없어요").font(Typo.sectionTitle)
            Text("아이폰에서 설정 › Bluetooth 화면을 열어두고 아래 버튼을 누르세요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)
            Button("새 기기 페어링") { model.openOnboarding(at: .pairing) }
                .buttonStyle(PillButtonStyle())
                .padding(.top, 4)
        }
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.settingsCard))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
    }
}

// MARK: - 정보

struct AboutTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissions: Permissions

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "개발판"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(short) (\($0))" } ?? short
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16).fill(Color.brandFill)
                    Image(systemName: "iphone")
                        .font(.system(size: 34, weight: .regular))
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .offset(x: -24)
                }
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
                Text("EdgeLink").font(Typo.font(20, .bold)).padding(.top, 4)
                Text("버전 \(version) · Mac 하나로 아이폰까지").font(Typo.body).foregroundStyle(Color.textSecondary)
            }
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "권한")
                SettingsGroup {
                    ForEach(Array(Permissions.Kind.allCases.enumerated()), id: \.element.id) { i, kind in
                        if i > 0 { RowDivider() }
                        permissionRow(kind)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "업데이트")
                SettingsGroup {
                    VStack(alignment: .leading, spacing: 0) {
                        ToggleRow(title: "자동으로 업데이트 확인",
                                  hint: settings.autoUpdateAllowed ? "하루 한 번 확인해요. 정해진 주소 한 곳만 써요" : "회사 정책으로 꺼져 있어요",
                                  isOn: $settings.autoUpdateCheck)
                            .disabled(!settings.autoUpdateAllowed)
                            .opacity(settings.autoUpdateAllowed ? 1 : 0.6)
                        RowDivider()
                        HStack(spacing: 12) {
                            RowText(title: "지금 확인", hint: "업데이트 확인은 다음 버전부터 쓸 수 있어요")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Button("지금 확인") {}
                                .buttonStyle(PillButtonStyle(kind: .plain, height: 32))
                                .disabled(true)
                                .accessibilityHint("업데이트 확인은 다음 버전부터 쓸 수 있어요")
                        }
                        .padding(.vertical, 12)
                        .frame(minHeight: 60)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("MIT 라이선스로 배포해요. 글꼴 SUIT는 SIL Open Font License를 따라요.")
                Text("iPhone, iPad, Mac, macOS, AssistiveTouch는 Apple Inc.의 상표예요. EdgeLink는 Apple과 관련이 없는 독립 프로젝트예요.")
            }
            .font(Typo.caption)
            .foregroundStyle(Color.textSecondary)
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func permissionRow(_ kind: Permissions.Kind) -> some View {
        let granted = permissions.isGranted(kind)
        return HStack(spacing: 12) {
            StatusDot(color: granted ? .success : .danger)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(Typo.itemTitle)
                Text(granted ? "허용됨 · \(kind.why)" : "꺼져 있어요 · \(kind.why)")
                    .font(Typo.secondary)
                    .foregroundStyle(granted ? Color.textSecondary : .dangerText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if granted {
                Button("설정 열기") { permissions.open(kind) }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 32))
                    .accessibilityLabel("\(kind.title) 시스템 설정 열기")
            } else {
                Button("허용하기") { permissions.request(kind) }
                    .buttonStyle(PillButtonStyle(kind: .primary, height: 32))
                    .accessibilityLabel("\(kind.title) 허용하기")
            }
        }
        .padding(.vertical, 12)
        .frame(minHeight: 60)
    }
}
