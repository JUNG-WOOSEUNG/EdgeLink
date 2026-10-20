import AppKit
import EdgeLinkCore
import SwiftUI

/// 첫 실행 8단계 (캔버스 1-1 ~ 1-8). 2~5단계는 필수.
enum OnboardingStep: Int, CaseIterable {
    case welcome = 1, permissions, pairing, assistiveTouch, test, layout, practice, done

    var title: String {
        switch self {
        case .welcome: return "시작"
        case .permissions: return "Mac 권한"
        case .pairing: return "아이폰 연결"
        case .assistiveTouch: return "AssistiveTouch"
        case .test: return "연결 확인"
        case .layout: return "배치"
        case .practice: return "연습"
        case .done: return "완료"
        }
    }

    /// 위쪽 진행 표시의 묶음 (Mac 권한 · 아이폰 연결 · 배치 · 연습)
    var group: Int? {
        switch self {
        case .welcome, .done: return nil
        case .permissions: return 0
        case .pairing, .assistiveTouch, .test: return 1
        case .layout: return 2
        case .practice: return 3
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: 44) // 신호등 버튼 자리
            if let group = model.onboardingPage.group {
                StepIndicator(current: group).padding(.bottom, 16)
            }
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        // 높이를 고정하지 않고 창을 채운다. 고정하면 SwiftUI가 제목 표시줄 높이를 더해 창을 키운다.
        .frame(width: 720)
        .frame(maxHeight: .infinity)
        .background(Color.bgWindow)
        .foregroundStyle(Color.textPrimary)
        .ignoresSafeArea()
    }

    @ViewBuilder private var page: some View {
        switch model.onboardingPage {
        case .welcome: WelcomeStep()
        case .permissions: PermissionsStep()
        case .pairing: PairingStep()
        case .assistiveTouch: AssistiveTouchStep()
        case .test: TestStep()
        case .layout: LayoutStep()
        case .practice: PracticeStep()
        case .done: DoneStep()
        }
    }
}

// MARK: - 공용

struct StepIndicator: View {
    let current: Int
    /// 팝오버 "설정 중" 카드도 이 묶음으로 센다
    static let labels = ["Mac 권한", "아이폰 연결", "배치", "연습"]
    private var labels: [String] { Self.labels }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(labels.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    NumberDot(text: "\(i + 1)", state: i < current ? .done : i == current ? .current : .todo)
                    Text(labels[i])
                        .font(Typo.font(12, .semibold))
                        .foregroundStyle(i == current ? Color.textPrimary : .textSecondary)
                    if i < labels.count - 1 {
                        Rectangle().fill(Color.control).frame(width: 28, height: 1).padding(.leading, 4)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(current + 1)/4단계 \(labels[current])")
    }
}

/// 창 아래 72pt 줄
struct Footer<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.line).frame(height: 1)
            HStack {
                leading
                Spacer()
                trailing
            }
            .padding(.horizontal, 24)
            .frame(height: 71)
        }
    }
}

struct BackButton: View {
    @EnvironmentObject var model: AppModel
    let to: OnboardingStep
    var body: some View {
        Button("이전") { model.onboardingPage = to }.buttonStyle(TextLinkStyle())
    }
}

struct StepHeader: View {
    let title: String
    let message: String
    /// 부제 오른쪽 ⓘ에 접어 둘 보충 설명 (왜 그런지, 예외)
    var info: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(Typo.onboardingTitle)
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(message).font(Typo.body).foregroundStyle(Color.textSecondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let info { InfoTip(info, size: 13) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 1 시작

struct WelcomeStep: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: Space.xxl) {
                WelcomeArt()
                VStack(spacing: Space.m) {
                    Text("Mac 키보드·트랙패드로 아이폰까지").font(Typo.font(28, .heavy))
                    Text("커서를 화면 끝으로 밀면 아이폰으로 넘어가요.\n아이폰엔 아무것도 설치하지 않아요.")
                        .font(Typo.font(15, .regular)).foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center).lineSpacing(4)
                }
                // 카드마다 설명은 한 줄 (두 줄로 넘어가 마지막 줄에 한 단어만 남지 않게)
                HStack(spacing: Space.l) {
                    feature("블루투스·입력 권한 3가지", "아이폰 조작에 필요해요")
                    feature("아이폰 연결", "블루투스 페어링 한 번이면 돼요")
                    feature("배치와 연습", "위치를 정하고 넘어가 봐요")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 64)
            .frame(maxHeight: .infinity)

            Footer {
                Text("약 3분 걸려요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
            } trailing: {
                Button("시작하기") { model.complete(.welcome) }
                    .buttonStyle(PillButtonStyle(height: 40))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func feature(_ title: String, _ text: String) -> some View {
        GrayCard(stretch: true) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(Typo.bodyBold).lineLimit(1)
                Text(text).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// 노트북 + 파란 구간 + 아이폰
struct WelcomeArt: View {
    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10).fill(Color(hex: 0x1A1A1A))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.deviceOutline, lineWidth: 1))
                .overlay(MacScreenArt().clipShape(RoundedRectangle(cornerRadius: 5)).padding(6))
                .frame(width: 200, height: 126).offset(x: 20, y: 10)
            RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xB3B3B3))
                .frame(width: 240, height: 8).offset(x: 0, y: 136)
            Capsule().fill(Color.brand.opacity(0.28))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                .shadow(color: Color.brand.opacity(0.5), radius: 8)
                .frame(width: 20, height: 64).offset(x: 206, y: 40)
            PhoneArt(width: 52, height: 104, bezel: 3) {
                ZStack {
                    PhoneScreenArt()
                    // AssistiveTouch 커서
                    Circle().fill(Color.white.opacity(0.35)).overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .frame(width: 10, height: 10).offset(x: -6, y: 8)
                }
            }
            .offset(x: 246, y: 26)
        }
        .frame(width: 300, height: 150, alignment: .topLeading)
        .accessibilityHidden(true)
    }
}

extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

// MARK: - 2 Mac 권한

struct PermissionsStep: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var permissions: Permissions
    @State private var copied = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                StepHeader(title: "Mac 권한 3가지를 허용해 주세요",
                           message: "허용하면 자동으로 확인돼요.",
                           info: "시스템 설정에서 켜면 1초 안에 알아채요. 앱을 다시 켤 필요는 없어요.")
                VStack(spacing: 0) {
                    ForEach(Permissions.Kind.allCases) { kind in
                        row(kind)
                        if kind != .inputMonitoring { Rectangle().fill(Color.lineSoft).frame(height: 1) }
                    }
                }
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))

                HStack(alignment: .center, spacing: Space.xs) {
                    Image(systemName: "lock").font(.system(size: 12, weight: .medium))
                        .padding(.trailing, Space.xs)
                    Text("입력 내용은 저장하거나 인터넷으로 보내지 않아요.")
                    InfoTip("아이폰을 조작하는 동안에만 키 입력과 커서 움직임을 블루투스로 아이폰에 전달해요.")
                }
                .font(Typo.secondary).foregroundStyle(Color.textSecondary)
            }
            .padding(.horizontal, 48).padding(.top, Space.s).padding(.bottom, Space.xl)
            .frame(maxHeight: .infinity, alignment: .top)

            Footer {
                BackButton(to: .welcome)
            } trailing: {
                Button(permissions.allGranted ? "다음" : "권한을 허용하면 넘어가요") { model.complete(.permissions) }
                    .buttonStyle(PillButtonStyle(height: 40))
                    .disabled(!permissions.allGranted)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onChange(of: permissions.allGranted) { all in
            // 마지막 권한이 허용되면 1초 안에 다음 단계로
            guard all, model.onboardingPage == .permissions else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if model.onboardingPage == .permissions { model.complete(.permissions) }
            }
        }
        .onAppear {
            // 입력 모니터링은 "종료 후 다시 열기"를 권해서, 다시 켰을 때 이미 다 허용돼 있을 수 있다
            if permissions.allGranted, model.settings.onboardingStep < OnboardingStep.permissions.rawValue {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if model.onboardingPage == .permissions { model.complete(.permissions) }
                }
            }
        }
    }

    @ViewBuilder private func row(_ kind: Permissions.Kind) -> some View {
        let granted = permissions.isGranted(kind)
        let isNext = permissions.firstMissing == kind
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                Image(systemName: kind.symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(Color.brandStrong)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.segmentBg))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(kind.title).font(Typo.font(14, .bold))
                    Text(kind.why).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if granted {
                    Label("허용됨", systemImage: "checkmark")
                        .font(Typo.bodyBold).foregroundStyle(Color.successText)
                } else {
                    Button(cta(kind)) { permissions.request(kind) }
                        .buttonStyle(PillButtonStyle(kind: isNext ? .primary : .plain, height: 34))
                        .accessibilityLabel("\(kind.title) \(cta(kind))")
                }
            }
            if !granted, kind == .bluetooth, permissions.bluetooth == .denied {
                deniedGuide
            } else if !granted, isNext, kind != .bluetooth, permissions.waiting?.kind == kind {
                settingsGuide(kind)
            }
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }

    private func cta(_ kind: Permissions.Kind) -> String {
        if kind == .bluetooth { return permissions.bluetooth == .denied ? "설정 열기" : "허용" }
        return "설정 열기"
    }

    /// 60초가 지나도 안 켜질 때 (회사 정책)
    private var adminHelp: some View {
        HStack(spacing: Space.xs) {
            Text("켜지지 않나요?")
            InfoTip("회사에서 관리하는 Mac이라면 관리자가 권한을 막아 두었을 수 있어요. 복사한 내용을 관리자에게 보내 허용을 요청하세요.")
            Button(copied ? "복사했어요" : "관리자에게 보낼 내용 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Permissions.adminRequestText, forType: .string)
                copied = true
            }
            .buttonStyle(TextLinkStyle(color: .brandText))
        }
        .font(Typo.caption).foregroundStyle(Color.textSecondary)
    }

    /// 캔버스 4-4 블루투스 권한 거부됨
    private var deniedGuide: some View {
        InfoBox {
            VStack(alignment: .leading, spacing: Space.xs) {
                HStack(spacing: Space.xs) {
                    Text("블루투스를 허용하지 않았어요").font(Typo.font(12, .bold)).foregroundStyle(Color.brandStrong)
                    InfoTip("켜면 자동으로 다음 권한으로 넘어가요.")
                }
                Text("시스템 설정 › \("개인정보 보호 및 보안".nonBreaking) › Bluetooth에서 EdgeLink를 켜 주세요.")
                    .font(Typo.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                if permissions.waitingTooLong { adminHelp }
            }
        }
        .padding(.leading, 46)
    }

    private func settingsGuide(_ kind: Permissions.Kind) -> some View {
        InfoBox {
            HStack(alignment: .center, spacing: Space.l) {
                SettingsMiniArt(title: kind.title)
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.xs) {
                        Text("시스템 설정이 열렸어요").font(Typo.font(12, .bold)).foregroundStyle(Color.brandStrong)
                        InfoTip("목록에 EdgeLink가 없으면 목록 아래 + 버튼으로 EdgeLink를 추가하세요.")
                    }
                    Text("목록에서 EdgeLink를 켜 주세요.")
                        .font(Typo.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    if kind == .inputMonitoring {
                        // macOS는 입력 모니터링을 켜면 다시 열기를 권하지만, EdgeLink는 1초 안에 알아챈다
                        Text("macOS가 ‘종료 후 다시 열기’를 물으면 ‘나중에’를 눌러도 돼요.")
                            .font(Typo.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 6) {
                        Spinner(size: 10)
                        Text("허용되길 기다리는 중")
                    }
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    if permissions.waitingTooLong { adminHelp }
                }
            }
        }
        .padding(.leading, 46)
    }
}

/// 시스템 설정 목록 모양 그림
struct SettingsMiniArt: View {
    let title: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Typo.font(10, .bold)).foregroundStyle(Color.textSecondary)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color.brand).frame(width: 14, height: 14)
                Text("EdgeLink").font(Typo.font(11, .regular))
                Spacer()
                Capsule().fill(Color.brand).frame(width: 24, height: 14)
                    .overlay(Circle().fill(.white).frame(width: 10, height: 10).padding(2), alignment: .trailing)
            }
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Color(hex: 0xD9D9D9)).frame(width: 14, height: 14)
                Text("다른 앱").font(Typo.font(11, .regular)).foregroundStyle(Color.textDecor)
                Spacer()
                Capsule().fill(Color(hex: 0xD9D9D9)).frame(width: 24, height: 14)
            }
        }
        .padding(8)
        .frame(width: 180)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.bgWindow))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.line, lineWidth: 1))
        .accessibilityHidden(true)
    }
}

// MARK: - 3 아이폰 페어링

struct PairingStep: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var devices: DeviceDirectory
    @State private var showHelp = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("아이폰과 블루투스로 연결해요").font(Typo.onboardingTitle).lineSpacing(2)
                        (Text("아이폰에서 ") + Text("설정 › Bluetooth".nonBreaking).bold().foregroundColor(.textPrimary)
                         + Text(" 화면을 열어 두면 오른쪽 목록에 나타나요."))
                            .font(Typo.body).foregroundStyle(Color.textSecondary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    PhoneBluetoothArt(code: pairingCode)
                        .frame(maxWidth: .infinity)
                }
                .frame(width: 260)

                VStack(alignment: .leading, spacing: Space.m) {
                    HStack(spacing: Space.s) {
                        if devices.searching { Spinner(size: 12) }
                        Text(devices.searching ? "근처 기기 찾는 중" : "기기 목록")
                    }
                    .font(Typo.font(12, .semibold)).foregroundStyle(Color.textSecondary)

                    deviceList

                    if let code = pairingCode {
                        InfoBox {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("두 화면의 번호가 같은지 확인하세요").font(Typo.bodyBold).foregroundStyle(Color.brandStrong)
                                (Text("Mac에 ") + Text(Self.format(code)).fontWeight(.heavy)
                                 + Text("이 보여요. 아이폰에도 같은 번호가 뜨면 아이폰에서 ‘페어링’을 누르세요."))
                                    .font(Typo.secondary).lineSpacing(3)
                            }
                        }
                    }
                    if case let .failed(message) = model.connection, model.connectingAddress != nil || !model.isConnected {
                        // 오류 원문은 연결 로그에만. 여기선 결과와 할 일만.
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text(ConnectionError(message).friendly).font(Typo.font(12, .semibold)).foregroundStyle(Color.dangerText)
                            HStack(spacing: Space.xs) {
                                Text("다시 ‘연결’을 눌러 보세요.")
                                    .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                                InfoTip("계속 안 되면 아이폰 설정 › Bluetooth에서 이 Mac을 ‘이 기기 지우기’ 한 뒤 다시 연결하세요.")
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.easeOut(duration: 0.15)) { showHelp.toggle() }
                        } label: {
                            HStack(spacing: 4) {
                                Text("목록에 아이폰이 없나요?")
                                Image(systemName: showHelp ? "chevron.up" : "chevron.down").font(.system(size: 9, weight: .bold))
                            }
                        }
                        .buttonStyle(TextLinkStyle(color: .brandText))
                        if showHelp {
                            VStack(alignment: .leading, spacing: 4) {
                                helpLine("아이폰 블루투스를 켜고 설정 › Bluetooth 화면을 열어 두세요.")
                                helpLine("예전에 연결했던 Mac이라면 아이폰에서 이 Mac을 ‘이 기기 지우기’ 한 뒤 다시 시도하세요.")
                                helpLine("다른 Mac에서 EdgeLink를 쓰고 있다면 그쪽 연결을 먼저 끊어 주세요.")
                                if devices.items.contains(where: { $0.kind == .pad }) {
                                    helpLine("아이패드는 유니버설 컨트롤·Sidecar와 같이 쓰면 겹칠 수 있어요.")
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 48).padding(.top, Space.s).padding(.bottom, Space.xl)
            .frame(maxHeight: .infinity, alignment: .top)

            Footer {
                BackButton(to: .permissions)
            } trailing: {
                Button(model.isConnected ? "다음" : "연결하면 넘어가요") { model.complete(.pairing) }
                    .buttonStyle(PillButtonStyle(height: 40))
                    .disabled(!model.isConnected)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            devices.start()
            model.acceptingNewDevice = true
        }
        .onDisappear {
            devices.stop()
            model.acceptingNewDevice = false
        }
    }

    private func helpLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("·")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(2)
    }

    private var pairingCode: Int? {
        if case let .pairing(code) = model.connection { return code }
        return nil
    }

    static func format(_ code: Int) -> String {
        let s = String(format: "%06d", code)
        return "\(s.prefix(3)) \(s.suffix(3))"
    }

    @ViewBuilder private var deviceList: some View {
        if devices.items.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("아직 찾은 기기가 없어요").font(Typo.itemTitle)
                    Text("아이폰에서 설정 › Bluetooth 화면을 열고 잠시 기다려 주세요.")
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
            }
        } else {
            VStack(spacing: 0) {
                ForEach(Array(devices.items.prefix(4).enumerated()), id: \.element.id) { i, item in
                    DeviceRow(item: item)
                    if i < min(devices.items.count, 4) - 1 { Rectangle().fill(Color.lineSoft).frame(height: 1) }
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
        }
    }
}

struct DeviceRow: View {
    @EnvironmentObject var model: AppModel
    let item: DeviceDirectory.Item

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.kind == .pad ? "ipad" : "iphone")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(isTarget ? Color.textPrimary : .textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(Typo.font(14, .bold)).lineLimit(1)
                Text(status.text).font(Typo.secondary).foregroundStyle(status.color)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 60)
    }

    private var isTarget: Bool { model.connectingAddress == item.address || connectedHere }
    private var connectedHere: Bool {
        model.isConnected && model.settings.lastDeviceAddress?.lowercased() == item.address.lowercased()
    }

    private var status: (text: String, color: Color) {
        if connectedHere { return ("연결됨 · 기본 기기로 저장했어요", .successText) }
        if model.connectingAddress == item.address {
            switch model.connection {
            case .pairing: return ("페어링 확인 중…", .brandText)
            case .connecting: return ("연결 중…", .brandText)
            case .failed: return ("연결 실패", .dangerText)
            default: break
            }
        }
        // 처음 연결하면 아이폰에 번호 확인 창이 뜬다 (누르기 전에 알려서 아이폰을 들고 있게)
        return (item.paired ? "페어링됨" : "처음 연결 · 아이폰에 확인 창이 떠요", .textSecondary)
    }

    @ViewBuilder private var trailing: some View {
        if connectedHere {
            Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(Color.successText)
                .accessibilityLabel("연결됨")
        } else if model.connectingAddress == item.address, model.connection == .connecting || isPairing {
            Spinner(size: 16)
        } else {
            Button("연결") { model.connect(address: item.address) }
                .buttonStyle(PillButtonStyle(kind: item.kind == .phone ? .primary : .plain, height: 34))
                .disabled(busy)
                .accessibilityLabel("\(item.name) 연결")
        }
    }

    private var isPairing: Bool { if case .pairing = model.connection { return true } else { return false } }
    private var busy: Bool { model.connection == .connecting || isPairing }
}

/// 아이폰 블루투스 설정 화면 그림 (페어링 요청 번호 포함)
struct PhoneBluetoothArt: View {
    let code: Int?
    var body: some View {
        RoundedRectangle(cornerRadius: 22).fill(Color(hex: 0x1A1A1A))
            .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.deviceOutline, lineWidth: 1))
            .frame(width: 132, height: 232)
            .overlay(
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bluetooth").font(Typo.font(13, .heavy))
                    HStack {
                        Text("Bluetooth").font(Typo.font(9, .semibold))
                        Spacer()
                        Capsule().fill(Color(hex: 0x34C759)).frame(width: 22, height: 13)
                            .overlay(Circle().fill(.white).frame(width: 9, height: 9).padding(2), alignment: .trailing)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 8).fill(.white))
                    if let code {
                        VStack(spacing: 4) {
                            Text("블루투스 페어링 요청").font(Typo.font(9, .bold))
                            Text(PairingStep.format(code)).font(Typo.font(12, .heavy))
                            Text("페어링").font(Typo.font(9, .bold)).foregroundStyle(Color(hex: 0x0077B6))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.white).shadow(color: .black.opacity(0.24), radius: 8, y: 4))
                        .padding(.top, 6)
                    }
                    Spacer()
                }
                .foregroundStyle(Color(hex: 0x1A1A1A))
                .padding(EdgeInsets(top: 22, leading: 10, bottom: 10, trailing: 10))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 17).fill(Color(hex: 0xF2F2F7)))
                .overlay(Capsule().fill(Color.black).frame(width: 40, height: 11).padding(.top, 6), alignment: .top)
                .padding(6)
            )
            .accessibilityHidden(true)
    }
}

// MARK: - 4 AssistiveTouch

struct AssistiveTouchStep: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @AppStorage("assistiveTouchConfirmed") private var checked = false

    private let path: [(title: String, parent: String, row: String, toggle: Bool)] = [
        ("설정 열기", "홈 화면", "설정", false),
        ("손쉬운 사용", "설정", "손쉬운 사용", false),
        ("터치", "손쉬운 사용", "터치", false),
        ("AssistiveTouch 켜기", "터치", "AssistiveTouch", true),
    ]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                StepHeader(title: "아이폰에서 마우스 커서를 켜 주세요",
                           message: "아이폰은 AssistiveTouch를 켜야 마우스 커서가 보여요.",
                           info: "키보드는 이 설정 없이도 돼요. AssistiveTouch는 화면에 회색 동그라미 버튼이 보이면 켜진 거예요.")
                if isPad {
                    InfoBox {
                        Text("아이패드는 마우스 커서가 기본으로 보여서 이 단계를 건너뛰어도 돼요.")
                            .font(Typo.secondary).foregroundStyle(Color.brandStrong)
                    }
                }
                HStack(spacing: Space.m) {
                    ForEach(path.indices, id: \.self) { i in pathCard(i) }
                }
                // 다음 배치 단계의 "아이폰 방향"과 맞게: 세워 쓸 때만 회전 잠금
                tip("lock.rotation", "아이폰을 세워 쓴다면 화면 회전 잠금을 켜 두세요.",
                    info: "화면이 돌아가면 커서가 Mac으로 돌아오는 위치가 어긋나요.")
                Toggle(isOn: $checked) {
                    Text("아이폰에서 AssistiveTouch를 켰어요").font(Typo.font(14, .semibold))
                }
                .toggleStyle(BoxCheckboxStyle())
            }
            .padding(.horizontal, 48).padding(.top, Space.s).padding(.bottom, Space.xl)
            .frame(maxHeight: .infinity, alignment: .top)

            Footer {
                BackButton(to: .pairing)
            } trailing: {
                // 꺼져 있을 땐 버튼 이름이 이유를 말한다
                Button(checked || isPad ? "다음" : "켰으면 체크해 주세요") { model.complete(.assistiveTouch) }
                    .buttonStyle(PillButtonStyle(height: 40))
                    .disabled(!(checked || isPad))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var isPad: Bool {
        settings.profile.model.isPad || (settings.lastDeviceName?.lowercased().contains("ipad") ?? false)
    }

    private func pathCard(_ i: Int) -> some View {
        let p = path[i]
        return VStack(alignment: .leading, spacing: 10) {
            NumberDot(text: "\(i + 1)", state: .current, size: 22)
            VStack(alignment: .leading, spacing: 6) {
                Text(p.parent).font(Typo.font(9, .regular)).foregroundStyle(Color(hex: 0x6E6E73))
                HStack {
                    Text(p.row).font(Typo.font(10, .bold)).lineLimit(1).minimumScaleFactor(0.7)
                    Spacer()
                    if p.toggle {
                        Capsule().fill(Color(hex: 0x34C759)).frame(width: 22, height: 13)
                    } else {
                        Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.textDecor)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.infoBg))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.infoLine, lineWidth: 1))
                RoundedRectangle(cornerRadius: 4).fill(Color(light: 0xF2F2F7, dark: 0x333336)).frame(height: 14)
            }
            .padding(10)
            .frame(height: 84, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgWindow))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.line, lineWidth: 1))
            .accessibilityHidden(true)
            Text(p.title).font(Typo.bodyBold).lineSpacing(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.bgSidebar))
    }

    private func tip(_ icon: String, _ text: String, info: String? = nil) -> some View {
        HStack(alignment: .center, spacing: Space.s) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.brand)
                .frame(width: 16)
            HStack(spacing: Space.xs) {
                Text(text).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let info { InfoTip(info) }
            }
        }
    }
}

// MARK: - 5 연결 확인

struct TestStep: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var trouble = false
    @State private var typed = false
    /// 키보드 시험 중엔 커서를 멈춘다 (움직이는 동안엔 입력 칸을 누르기 어렵고 입력이 섞인다)
    @State private var circlePaused = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: Space.xxl) {
                PhoneCircleArt()
                VStack(alignment: .leading, spacing: Space.l) {
                    StepHeader(title: "아이폰 화면을 보세요",
                               message: "EdgeLink가 아이폰 커서를 원 모양으로 움직이고 있어요. 커서가 보이나요?")
                    if !model.isConnected {
                        Notice(title: "아이폰 연결이 끊겼어요.", message: "연결되면 커서를 다시 움직여요.")
                        HStack(spacing: Space.m) {
                            Button("다시 연결") {
                                if let a = settings.lastDeviceAddress { model.connect(address: a) }
                            }
                            .buttonStyle(PillButtonStyle(height: 36))
                            .disabled(settings.lastDeviceAddress == nil || model.connection == .connecting)
                            // 다시 연결도 실패하면 페어링부터 다시
                            if case .failed = model.connection {
                                Button("아이폰 연결 단계로 돌아가기") { model.onboardingPage = .pairing }
                                    .buttonStyle(TextLinkStyle(color: .brandText))
                            }
                        }
                        if case .failed = model.connection {
                            Text("계속 안 되면 아이폰 설정 › Bluetooth에서 이 Mac을 지운 뒤 다시 페어링하세요.")
                                .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } else if trouble {
                        troubleCard
                    } else {
                        // "보여요"는 아래쪽 기본 버튼으로
                        Button("안 보여요") { trouble = true }
                            .buttonStyle(PillButtonStyle(kind: .plain, height: 40))
                    }
                    // 연결이 끊겼을 땐 할 일을 하나로 (다시 연결)
                    if model.isConnected {
                        GrayCard(padding: 0) {
                            VStack(alignment: .leading, spacing: Space.s) {
                                HStack(spacing: Space.xs) {
                                    Text("키보드도 시험해 볼까요? (선택)").font(Typo.font(12, .bold))
                                    InfoTip("아이폰 키보드가 한국어면 ‘EdgeLink’가 한글 자모로 들어가는데, 그래도 성공이에요.")
                                }
                                Text("아이폰 메모 앱의 입력 칸을 누른 뒤 아래 버튼을 누르면 ‘EdgeLink’가 입력돼요.")
                                    .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: Space.s) {
                                    Button(typed ? "다시 입력해 보기" : "아이폰에 입력해 보기") {
                                        model.stopCircle()
                                        circlePaused = true
                                        model.type("EdgeLink")
                                        typed = true
                                    }
                                    .buttonStyle(PillButtonStyle(kind: .secondary, height: 32))
                                    if circlePaused {
                                        Button("커서 다시 움직이기") {
                                            model.startCircle()
                                            circlePaused = false
                                        }
                                        .buttonStyle(PillButtonStyle(kind: .plain, height: 32))
                                    }
                                }
                                if circlePaused {
                                    Text("입력하는 동안 커서를 멈췄어요.").font(Typo.caption).foregroundStyle(Color.textSecondary)
                                }
                            }
                            .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                        }
                    }
                }
            }
            .padding(.horizontal, 48).padding(.top, Space.s).padding(.bottom, Space.xl)
            .frame(maxHeight: .infinity, alignment: .top)

            Footer {
                BackButton(to: .assistiveTouch)
            } trailing: {
                // 자동으로 넘어가지 않는다: 커서를 봤으면 직접 누른다
                Button(model.isConnected ? "네, 커서가 보여요" : "연결되면 넘어가요") { model.complete(.test) }
                    .buttonStyle(PillButtonStyle(height: 40))
                    .disabled(!model.isConnected)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { model.startCircle() }
        .onDisappear { model.stopCircle() }
    }

    private var troubleCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Space.s) {
                Text("이것부터 확인해 보세요").font(Typo.bodyBold)
                check(1, "아이폰 잠금을 풀고 홈 화면을 띄워 두세요.")
                check(2, "AssistiveTouch가 켜져 있는지 확인하세요. 화면에 회색 동그라미 버튼이 보이면 켜진 거예요.")
                check(3, "아이폰 설정 › Bluetooth에서 이 Mac이 ‘연결됨’인지 확인하세요.")
                HStack(spacing: Space.s) {
                    Button("다시 움직이기") {
                        model.startCircle()
                        circlePaused = false
                        trouble = false
                    }
                    .buttonStyle(PillButtonStyle(height: 36))
                    Button("AssistiveTouch 안내 다시 보기") { model.onboardingPage = .assistiveTouch }
                        .buttonStyle(PillButtonStyle(kind: .plain, height: 36))
                }
                .padding(.top, Space.xs)
            }
        }
    }

    private func check(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Space.s) {
            Text("\(n)").font(Typo.font(10, .heavy))
                .frame(width: 18, height: 18).background(Circle().fill(Color.segmentBg))
            Text(text).font(Typo.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PhoneCircleArt: View {
    @State private var angle = 0.0
    var body: some View {
        RoundedRectangle(cornerRadius: 26).fill(Color(hex: 0x1A1A1A))
            .overlay(RoundedRectangle(cornerRadius: 26).strokeBorder(Color.deviceOutline, lineWidth: 1))
            .frame(width: 150, height: 290)
            .overlay(
                ZStack {
                    PhoneScreenArt().clipShape(RoundedRectangle(cornerRadius: 20)).opacity(0.85)
                    Circle().strokeBorder(Color.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .frame(width: 70, height: 70)
                    Circle().fill(Color.white.opacity(0.85)).overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .frame(width: 16, height: 16)
                        .offset(x: 35 * cos(angle), y: 35 * sin(angle))
                    VStack {
                        Spacer()
                        Text("커서가 원을 그려요").font(Typo.font(10, .regular)).foregroundStyle(Color.white.opacity(0.8))
                            .padding(.bottom, 30)
                    }
                }
                .padding(7)
            )
            .onAppear {
                withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { angle = 2 * .pi }
            }
            .accessibilityHidden(true)
    }
}

// MARK: - 6 배치

struct LayoutStep: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @State private var placements: [Placement] = []
    @State private var selected: Placement?
    /// 기기 이름으로 크기를 알 수 없을 때만 묻는다 (바꾸기는 설정 › 배치)
    private var showModelPicker: Bool {
        DeviceProfile.Model.infer(from: settings.lastDeviceName) == nil
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.m) {
                StepHeader(title: "아이폰을 어디에 두셨나요?", message: "실제로 놓은 위치를 골라 주세요.")
                ArrangementView(screens: model.screens, placements: placements, selected: selected, landscape: settings.profile.landscape)
                    .frame(height: 196)

                if placements.isEmpty {
                    // 설정 › 배치와 같은 회복 방법: 디스플레이 설정 열기, 그동안은 단축키로 계속
                    Notice(title: "놓을 수 있는 가장자리가 없어요.",
                           message: "디스플레이 설정에서 모니터 배치를 바꿔 주세요. 그동안은 단축키로만 넘어가요.")
                    Button("디스플레이 설정 열기") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
                    }
                    .buttonStyle(PillButtonStyle(kind: .plain, height: 32))
                } else {
                    FlowRow(spacing: Space.s) {
                        ForEach(placements) { p in
                            Button(label(p)) { selected = p }
                                .buttonStyle(OptionChipStyle(on: p == selected))
                                .focusable(false)
                                .accessibilityAddTraits(p == selected ? .isSelected : [])
                        }
                    }
                }
                if let s = selected, let conflict = Layout.conflict(s) {
                    // 메뉴 막대 쪽이면 Dock 이야기는 맞지 않는다
                    Notice(title: conflict, message: s.edge == .top ? "조금 더 길게 밀어야 넘어가요." : "조금 더 길게 밀어야 넘어가요. Dock을 옆으로 옮기면 더 편해요.")
                }
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.m) {
                        // 돌아오는 위치 계산에 아이폰 화면 크기가 필요하다. 기기 이름으로 알면 묻지 않는다.
                        if showModelPicker {
                            Text("어떤 아이폰인가요?").font(Typo.body).foregroundStyle(Color.textSecondary)
                            Picker("어떤 아이폰인가요?", selection: Binding(get: { settings.profile.model }, set: { m in
                                settings.profile.model = m
                                settings.profile.manual = true
                            })) {
                                ForEach(DeviceProfile.Model.allCases) { Text($0.label).tag($0) }
                            }
                            .labelsHidden()
                            .frame(width: 200)
                            Spacer()
                        }
                        HStack(spacing: Space.xs) {
                            Text("아이폰 방향").font(Typo.body).foregroundStyle(Color.textSecondary)
                            InfoTip("실제로 놓은 방향을 고르면 Mac으로 돌아오는 위치가 맞아요.")
                        }
                        Picker("방향", selection: $settings.profile.landscape) {
                            Text("세로").tag(false)
                            Text("가로").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.large)
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 48).padding(.top, Space.s).padding(.bottom, Space.xl)
            .frame(maxHeight: .infinity, alignment: .top)

            Footer {
                BackButton(to: .test)
            } trailing: {
                // 놓을 자리가 없으면 막지 않고 단축키로 계속한다
                Button(placements.isEmpty ? "단축키로 계속하기" : "다음") {
                    if let s = selected {
                        settings.phoneLayout = PhoneLayout(screenID: s.screen.id, edge: s.edge, offset: s.passage.start)
                    }
                    model.complete(.layout)
                }
                .buttonStyle(PillButtonStyle(height: 40))
                .disabled(selected == nil && !placements.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear(perform: reload)
        .onReceive(model.$placements) { _ in
            placements = Layout.pickerOrder(model.placements)
            if let s = selected, !placements.contains(s) { selected = Layout.find(settings.phoneLayout, in: placements) ?? Layout.defaultPlacement(placements) }
        }
    }

    /// 모니터가 하나면 "화면 오른쪽"처럼 가장자리만
    private func label(_ p: Placement) -> String {
        Set(placements.map(\.screen.id)).count > 1 ? p.label : "화면 \(p.edge.label)"
    }

    private func reload() {
        model.reloadScreens()
        placements = Layout.pickerOrder(model.placements)
        selected = Layout.find(settings.phoneLayout, in: placements)
            ?? selected.flatMap { s in placements.first { $0.id == s.id } }
            ?? Layout.defaultPlacement(placements)
    }
}

struct OptionChipStyle: ButtonStyle {
    let on: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.font(13, .semibold))
            .foregroundStyle(on ? Color.brandStrong : .textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(on ? Color.brandTint : .bgWindow))
            .overlay(Capsule().strokeBorder(on ? Color.brand : .control, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}

/// 줄이 넘치면 다음 줄로 (macOS 13에서 쓸 수 있는 간단한 흐름 배치)
struct FlowRow: SwiftUI.Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}

/// 모니터 배치도 + 아이폰 + 파란 구간
struct ArrangementView: View {
    let screens: [ScreenInfo]
    let placements: [Placement]
    let selected: Placement?
    let landscape: Bool

    var body: some View {
        GeometryReader { geo in
            let screens = uniqueScreens
            let box = bounds(screens)
            // 아이폰 그림(고정 크기)이 들어갈 자리까지 포함해서 맞춘다
            let pw: CGFloat = landscape ? 90 : 44, ph: CGFloat = landscape ? 44 : 90
            let edge = selected?.edge
            let extraX: CGFloat = edge == .left || edge == .right ? pw + 4 : 0
            let extraY: CGFloat = edge == .top || edge == .bottom ? ph + 4 : 0
            let margin: CGFloat = 20
            let scale = min((geo.size.width - margin * 2 - extraX) / max(box.width, 1),
                            (geo.size.height - margin * 2 - extraY) / max(box.height, 1))
            let groupW = box.width * scale + extraX, groupH = box.height * scale + extraY
            let originX = (geo.size.width - groupW) / 2 + (edge == .left ? extraX : 0)
            let originY = (geo.size.height - groupH) / 2 + (edge == .top ? extraY : 0)
            // Cocoa(위로 갈수록 y 증가) → 화면(아래로 증가)
            let map: (Double, Double) -> CGPoint = { x, y in
                CGPoint(x: originX + (x - box.minX) * scale, y: originY + (box.maxY - y) * scale)
            }
            ZStack(alignment: .topLeading) {
                ForEach(screens) { s in
                    let tl = map(s.frame.x, s.frame.maxY)
                    let w = s.frame.width * scale, h = s.frame.height * scale
                    VStack(spacing: 0) {
                        if s.isMain { Rectangle().fill(Color(light: 0x4D4D4D, dark: 0x8C8C8C)).frame(height: 5) }
                        Text(s.name).font(Typo.font(12, .semibold)).foregroundStyle(Color.textPrimary)
                            .lineLimit(1).minimumScaleFactor(0.6).padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: w, height: h)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color(light: 0xE3F2FB, dark: 0x2B3A4A)))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.textDecor, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .offset(x: tl.x, y: tl.y)
                }
                if let p = selected { phoneAndGate(p, map: map, scale: scale) }
            }
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityElement()
        .accessibilityLabel(selected.map { "배치도: \($0.label)" } ?? "배치도")
    }

    private var uniqueScreens: [ScreenInfo] {
        var seen = Set<String>()
        let fromPlacements = placements.map(\.screen).filter { seen.insert($0.id).inserted }
        let all = screens.filter { seen.insert($0.id).inserted }
        return fromPlacements + all
    }

    private func bounds(_ screens: [ScreenInfo]) -> (minX: Double, maxY: Double, width: Double, height: Double) {
        guard !screens.isEmpty else { return (0, 1, 1, 1) }
        let minX = screens.map(\.frame.x).min()!, maxX = screens.map(\.frame.maxX).max()!
        let minY = screens.map(\.frame.y).min()!, maxY = screens.map(\.frame.maxY).max()!
        return (minX, maxY, maxX - minX, maxY - minY)
    }

    @ViewBuilder
    private func phoneAndGate(_ p: Placement, map: (Double, Double) -> CGPoint, scale: CGFloat) -> some View {
        let f = p.screen.frame
        let pw: CGFloat = landscape ? 90 : 44, ph: CGFloat = landscape ? 44 : 90
        let mid = (p.passage.start + p.passage.end) / 2
        let (gate, phone): (CGRect, CGRect) = {
            switch p.edge {
            case .right, .left:
                let x = p.edge == .right ? f.maxX : f.x
                let a = map(x, p.passage.end), b = map(x, p.passage.start)
                let c = map(x, mid)
                let px = p.edge == .right ? c.x + 6 : c.x - 6 - pw
                let top = max(a.y, c.y - ph / 2) + 4, bottom = min(b.y, c.y + ph / 2) - 4
                let gate = CGRect(x: a.x - 2, y: top, width: 4, height: max(0, bottom - top))
                return (gate, CGRect(x: px, y: c.y - ph / 2, width: pw, height: ph))
            case .top, .bottom:
                let y = p.edge == .top ? f.maxY : f.y
                let a = map(p.passage.start, y), b = map(p.passage.end, y)
                let c = map(mid, y)
                let left = max(a.x, c.x - pw / 2) + 4, right = min(b.x, c.x + pw / 2) - 4
                let gate = CGRect(x: left, y: a.y - 2, width: max(0, right - left), height: 4)
                let py = p.edge == .bottom ? c.y + 6 : c.y - 6 - ph
                return (gate, CGRect(x: c.x - pw / 2, y: py, width: pw, height: ph))
            }
        }()
        Capsule().fill(Color.brand).shadow(color: Color.brand, radius: 4)
            .frame(width: gate.width, height: gate.height)
            .offset(x: gate.minX, y: gate.minY)
        PhoneArt(width: min(phone.width, phone.height), height: max(phone.width, phone.height), bezel: 3) { PhoneScreenArt() }
            .rotationEffect(.degrees(landscape ? -90 : 0))
            .frame(width: phone.width, height: phone.height)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.brand, lineWidth: 1.5))
            .offset(x: phone.minX, y: phone.minY)
    }
}

// MARK: - 7 연습

struct PracticeStep: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    /// 해본 미션 (InputRouter가 알려주면 자동 체크)
    @State private var done: Set<PracticeMission> = []

    enum PracticeMission { case go, back, hotkey }

    var body: some View {
        VStack(spacing: 0) {
            // 그림은 화면 가운데에 떠 있지 않게 미션 목록 옆에 붙인다
            VStack(alignment: .leading, spacing: Space.l) {
                StepHeader(title: "직접 넘어가 볼까요?",
                           message: "하나씩 해 보면 자동으로 체크돼요. 이 창은 그대로 두고 해 보세요.")
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.l) {
                    VStack(spacing: 0) {
                        mission(1, .go, "아이폰으로 넘어가기", "\(placementLabel) 끝에서 커서를 꾹 밀어요")
                        Rectangle().fill(Color.lineSoft).frame(height: 1)
                        mission(2, .back, "Mac으로 돌아오기", "아이폰 화면 \(returnEdge) 끝으로 커서를 꾹 밀어요")
                        Rectangle().fill(Color.lineSoft).frame(height: 1)
                        mission(3, .hotkey, "단축키로 전환하기", "\(toggleKey)를 눌러요. 어디서든 바로 넘어가요")
                    }
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
                    // Mac으로 돌아와 본 뒤에만 한 줄로 (대부분은 필요 없다)
                    if done.contains(.back), model.isConnected {
                        HStack(spacing: Space.xs) {
                            Text("돌아온 위치가 커서와 다르면").foregroundStyle(Color.textSecondary)
                            Button("위치 맞추기") { model.present(.calibration) }
                                .buttonStyle(LinkButtonStyle(size: 12))
                        }
                        .font(Typo.secondary)
                        .transition(.opacity)
                    }
                }
                // 그림 위쪽 빈 칸(44)만큼 올려 모니터가 목록 첫 줄 높이에서 시작하게
                PushArt(mirrored: current?.edge == .left).frame(width: 200)
                    .padding(.top, -Space.xxl)
            }
            }
            .padding(.horizontal, 48).padding(.top, Space.s).padding(.bottom, Space.xl)
            .frame(maxHeight: .infinity, alignment: .top)

            Footer {
                BackButton(to: .layout)
            } trailing: {
                // 같은 일을 하는 버튼은 하나로: 남은 미션이 있으면 보조 "건너뛰기", 다 하면 기본 "다음"
                if done.count < 3 {
                    Button("건너뛰기") { model.complete(.practice) }
                        .buttonStyle(PillButtonStyle(kind: .plain, height: 40))
                } else {
                    Button("다음") { model.complete(.practice) }
                        .buttonStyle(PillButtonStyle(height: 40))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .onReceive(model.router.practice) { event in
            withAnimation(.easeOut(duration: 0.2)) {
                switch event {
                case .enteredByEdge: done.insert(.go)
                case .returnedByEdge: done.insert(.back)
                case .toggledByHotkey: done.insert(.hotkey)
                }
            }
        }
    }

    private var toggleKey: String { (settings.hotkeys[.toggleRemote] ?? Hotkey.defaults[.toggleRemote]!).display }

    private var current: Placement? { model.currentPlacement }
    private var placementLabel: String { current?.label ?? "모니터 오른쪽" }
    private var returnEdge: String { (current?.edge ?? .right).returnLabel }

    private func mission(_ n: Int, _ key: PracticeMission, _ title: String, _ hint: String) -> some View {
        // 권한 단계 줄과 같은 여백·간격
        HStack(spacing: Space.m) {
            NumberDot(text: "\(n)", state: done.contains(key) ? .done : .todo, size: 26)
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(title).font(Typo.font(14, .bold))
                Text(hint).font(Typo.secondary).foregroundStyle(Color.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.l).padding(.vertical, Space.m)
    }
}

struct PushArt: View {
    /// 아이폰이 왼쪽에 있으면 아이폰·파란 구간·화살표만 왼쪽으로 옮긴다 (맥 화면은 뒤집지 않음)
    var mirrored = false

    var body: some View {
        // 왼쪽 배치: 아이폰 0, 맥 80 / 오른쪽 배치: 맥 0, 아이폰 144
        let macX: CGFloat = mirrored ? 80 : 0
        let gateX: CGFloat = mirrored ? 68 : 108
        let phoneX: CGFloat = mirrored ? 0 : 144
        let lineX: CGFloat = mirrored ? 98 : 64
        let headX: CGFloat = mirrored ? 90 : 96
        VStack(spacing: 10) {
            ZStack(alignment: .topLeading) {
                // 아이패드로 보이지 않게 가로로 긴 모니터 + 받침대
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB3B3B3))
                    .frame(width: 18, height: 16).offset(x: macX + 51, y: 140)
                RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB3B3B3))
                    .frame(width: 52, height: 4).offset(x: macX + 34, y: 155)
                RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x1A1A1A))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.deviceOutline, lineWidth: 1))
                    .overlay(MacScreenArt(notch: false).clipShape(RoundedRectangle(cornerRadius: 3)).padding(4))
                    .frame(width: 120, height: 84).offset(x: macX, y: 56)
                Capsule().fill(Color.brand.opacity(0.25))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
                    .shadow(color: Color.brand.opacity(0.55), radius: 7)
                    .frame(width: 24, height: 80).offset(x: gateX, y: 60)
                Rectangle().fill(Color.brand).frame(width: 38, height: 2).offset(x: lineX, y: 96)
                Image(systemName: mirrored ? "arrowtriangle.left.fill" : "arrowtriangle.right.fill")
                    .font(.system(size: 10)).foregroundStyle(Color.brand)
                    .offset(x: headX, y: 90)
                PhoneArt(width: 56, height: 112, bezel: 3) { PhoneScreenArt() }
                    .offset(x: phoneX, y: 44)
            }
            .frame(width: 200, height: 200, alignment: .topLeading)
            Text("파란 구간에서 바깥쪽으로\n꾹 밀어 보세요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center).lineSpacing(3)
                // 그림 아래 빈 칸(40)을 줄여 설명이 그림에 붙게
                .padding(.top, -Space.xl)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 8 완료

struct DoneStep: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissions: Permissions
    @State private var loginOn = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Space.l) {
                HStack(spacing: Space.l) {
                    Circle().fill(Color.success).frame(width: 48, height: 48)
                        .overlay(Image(systemName: "checkmark").font(.system(size: 20, weight: .heavy)).foregroundStyle(.white))
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("준비 끝났어요").font(Typo.font(24, .heavy))
                        Text("이제 커서를 밀기만 하면 아이폰으로 넘어가요.").font(Typo.body).foregroundStyle(Color.textSecondary)
                    }
                }
                HStack(spacing: Space.m) {
                    summary("권한", permissions.allGranted ? "3가지 모두 허용" : "꺼진 권한이 있어요")
                    summary("기기", settings.lastDeviceName ?? "연결된 기기 없음")
                    summary("위치", model.currentPlacement?.label ?? "정하지 않음")
                }
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("기억해 두면 좋은 단축키").font(Typo.font(12, .semibold)).foregroundStyle(Color.textSecondary)
                    VStack(spacing: 0) {
                        shortcut("Mac ↔ 아이폰 전환", keys(.toggleRemote))
                        Rectangle().fill(Color.lineSoft).frame(height: 1)
                        shortcut("클립보드 보내기", keys(.sendClipboard))
                        Rectangle().fill(Color.lineSoft).frame(height: 1)
                        shortcut("가장자리 전환 켜기/끄기", keys(.toggleEdge))
                    }
                    .padding(.horizontal, Space.l)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.line, lineWidth: 1))
                }
                // 선택 기능: 아래쪽 "이전" 옆에 두면 내비게이션처럼 보여서 본문 카드로
                GrayCard(padding: 0) {
                    HStack(spacing: Space.m) {
                        Text("트랙패드 제스처로 아이폰 홈·앱 전환 열기 (선택)").font(Typo.body).lineLimit(1)
                        Spacer()
                        Button("설정하기") { model.settingsWindow.showGestureSetup() }
                            .buttonStyle(PillButtonStyle(kind: .secondary, height: 30))
                    }
                    .padding(.horizontal, Space.l).padding(.vertical, Space.s)
                }
                HStack(spacing: Space.l) {
                    HStack(spacing: Space.s) {
                        MenuBarMiniArt()
                        Text("설정은 메뉴 막대 아이콘에서 바꿀 수 있어요.")
                            .font(Typo.secondary).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Toggle(isOn: Binding(get: { loginOn }, set: { on in
                        model.setLoginItem(on)
                        loginOn = model.loginItemEnabled
                    })) {
                        Text("로그인할 때 자동 실행").font(Typo.font(13, .semibold))
                    }
                    .toggleStyle(.switch)
                    .tint(Color.brand)
                }
            }
            // 다른 단계와 같은 왼쪽 시작선(48)
            .padding(.horizontal, 48).padding(.top, Space.s).padding(.bottom, Space.xl)
            .frame(maxHeight: .infinity, alignment: .top)

            Footer {
                BackButton(to: .practice)
            } trailing: {
                Button("EdgeLink 사용하기") { model.finishOnboarding() }
                    .buttonStyle(PillButtonStyle(height: 40))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear { loginOn = model.loginItemEnabled }
    }

    private func summary(_ label: String, _ value: String) -> some View {
        Card(padding: Space.m) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(label).font(Typo.font(11, .regular)).foregroundStyle(Color.textSecondary)
                Text(value).font(Typo.bodyBold).lineLimit(1)
            }
        }
    }

    /// 사용자가 바꾼 단축키를 따른다
    private func keys(_ action: HotkeyAction) -> String {
        (settings.hotkeys[action] ?? Hotkey.defaults[action]!).display
    }

    private func shortcut(_ name: String, _ keys: String) -> some View {
        HStack {
            Text(name).font(Typo.body)
            Spacer()
            KeyCap(text: keys)
        }
        .frame(minHeight: 40)
    }
}

/// 완료 화면의 작은 메뉴 막대 그림 (메뉴 막대 아이콘을 가리킨다)
struct MenuBarMiniArt: View {
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB3B3B3)).frame(width: 14, height: 8)
            RoundedRectangle(cornerRadius: 4).fill(Color.brand).frame(width: 18, height: 18)
                .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(.white, lineWidth: 1.5).frame(width: 6, height: 11))
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: 0xB3B3B3)).frame(width: 14, height: 8)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.segmentBg))
        .accessibilityHidden(true)
    }
}
