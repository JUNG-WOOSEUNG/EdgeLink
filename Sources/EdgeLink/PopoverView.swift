import AppKit
import EdgeLinkCore
import SwiftUI

/// 메뉴바 팝오버 (캔버스 2-1 ~ 2-4). 너비 360, 높이는 내용에 맞춤.
struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var permissions: Permissions

    var body: some View {
        let mode = self.mode
        return VStack(alignment: .leading, spacing: 0) {
            header(mode)
            content(mode)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 16)
            footer
        }
        .frame(width: 360)
        .background(Color.bgPopover)
        .foregroundStyle(Color.textPrimary)
    }

    private enum Mode { case setup, problem(Problem), disconnected, connected }

    enum Problem {
        case permission(Permissions.Kind), bluetoothOff, bluetoothDenied
    }

    private var mode: Mode {
        if !settings.onboardingDone { return .setup }
        if permissions.bluetooth == .denied { return .problem(.bluetoothDenied) }
        if let k = permissions.revoked ?? permissions.firstMissing { return .problem(.permission(k)) }
        if !model.bluetoothPoweredOn { return .problem(.bluetoothOff) }
        return model.isConnected ? .connected : .disconnected
    }

    // MARK: 머리

    private func header(_ mode: Mode) -> some View {
        HStack(spacing: 12) {
            Image(systemName: model.isConnected ? "iphone" : "iphone.slash")
                .font(.system(size: 17))
                .foregroundStyle(model.isConnected ? Color.brandStrong : .textSecondary)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(model.isConnected ? Color.brandTint : .disabledFill))
            VStack(alignment: .leading, spacing: 2) {
                Text("EdgeLink").font(Typo.font(15, .bold))
                HStack(spacing: 6) {
                    Circle().fill(statusColor(mode)).frame(width: 8, height: 8)
                    Text(statusText(mode)).font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
            }
            Spacer()
        }
        .padding(EdgeInsets(top: 16, leading: 16, bottom: 12, trailing: 16))
    }

    private func statusText(_ mode: Mode) -> String {
        switch mode {
        case .setup: return "설정 중 · 연결된 기기 없음"
        case .problem(.permission): return "권한이 꺼져 있어요"
        case .problem(.bluetoothOff): return "Mac 블루투스가 꺼져 있어요"
        case .problem(.bluetoothDenied): return "블루투스 권한이 없어요"
        case .disconnected:
            if model.connection == .connecting { return "연결 중…" }
            return "연결 끊김"
        case .connected: return "연결됨 · Mac 조작 중"
        }
    }

    private func statusColor(_ mode: Mode) -> Color {
        switch mode {
        case .connected: return .success
        case .problem: return Color(hex: 0xFF9500)
        default: return .textDecor
        }
    }

    // MARK: 본문

    @ViewBuilder private func content(_ mode: Mode) -> some View {
        switch mode {
        case .setup: SetupCard()
        case let .problem(p): ProblemCard(problem: p)
        case .disconnected: DisconnectedCard()
        case .connected: ConnectedCard()
        }
    }

    // MARK: 바닥

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color.line).frame(height: 1)
            HStack {
                Button {
                    model.openOnboarding(at: settings.onboardingDone ? .welcome : nil)
                } label: {
                    HStack(spacing: 8) {
                        Text(settings.onboardingDone ? "온보딩 다시 보기" : "설정…")
                    }
                }
                .buttonStyle(FooterButtonStyle())
                .help("설정 창은 다음 업데이트에서 열려요")
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack(spacing: 8) {
                        Text("EdgeLink 종료")
                        Text("⌘Q").foregroundStyle(Color.textSecondary)
                    }
                }
                .buttonStyle(FooterButtonStyle())
                .keyboardShortcut("q")
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
        }
    }
}

struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.body)
            .padding(.horizontal, 8)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 6).fill(configuration.isPressed ? Color.segmentBg : .clear))
            .contentShape(Rectangle())
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
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("다음: \(next.title)").font(Typo.font(12, .bold)).foregroundStyle(Color.brandStrong)
                    Spacer()
                    Text("\(next.rawValue) / \(total)단계").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                ProgressBar(value: Double(next.rawValue - 1) / Double(total))
                Button {
                    model.openOnboarding()
                } label: {
                    Text("설정 이어하기").frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(height: 38))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.infoBg))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.brand, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
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
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.brand.opacity(0.15))
                Capsule().fill(Color.brand).frame(width: max(6, g.size.width * value))
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
    let problem: PopoverView.Problem
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 15, weight: .semibold))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(copy.title).font(Typo.font(14, .bold))
                        Text(copy.body).font(Typo.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .foregroundStyle(Color.warningText)
                Button {
                    action()
                } label: {
                    Text(copied ? "복사했어요" : copy.cta).frame(maxWidth: .infinity)
                }
                .buttonStyle(PillButtonStyle(height: 38))
                Text(copy.hint).font(Typo.caption).foregroundStyle(Color.warningText).fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.warningBg))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.warningLine, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                Text("지금 쓸 수 없는 기능").font(Typo.font(12, .semibold)).foregroundStyle(Color.textSecondary)
                ForEach(["아이폰으로 전환 멈춤", "모서리 전환 멈춤", "클립보드 보내기 멈춤"], id: \.self) {
                    Text($0).font(Typo.secondary).foregroundStyle(Color.textDecor)
                }
                Text("해결되면 자동으로 다시 동작해요. 앱을 다시 켤 필요는 없어요.")
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary).padding(.top, 4)
            }
        }
    }

    private var isMDM: Bool {
        if case .permission = problem, permissions.waitingTooLong { return true }
        return false
    }

    private var copy: (title: String, body: String, cta: String, hint: String) {
        if isMDM {
            return ("회사 정책으로 막혀 있을 수 있어요",
                    "1분이 지나도 권한이 켜지지 않았어요. 회사에서 관리하는 Mac이라면 관리자가 막아둔 걸 수 있어요.",
                    "관리자에게 보낼 내용 복사",
                    "복사되는 내용: 앱 이름, 번들 ID, 필요한 권한 3가지와 이유.")
        }
        switch problem {
        case let .permission(kind):
            return ("\(kind.title) 권한이 꺼졌어요",
                    "이 권한이 없으면 아이폰 조작 중에도 입력이 Mac으로 가요. 그래서 전환을 멈췄어요.",
                    "시스템 설정에서 다시 켜기",
                    "목록에서 EdgeLink를 켜주세요. 켜면 1초 안에 다시 동작해요.")
        case .bluetoothDenied:
            return ("블루투스 권한이 없어요",
                    "블루투스 권한이 있어야 아이폰에 키보드·마우스로 연결할 수 있어요.",
                    "시스템 설정에서 켜기",
                    "목록에서 EdgeLink를 켜주세요.")
        case .bluetoothOff:
            return ("Mac 블루투스가 꺼져 있어요",
                    "블루투스가 켜져야 아이폰에 키보드·마우스로 연결할 수 있어요. 다시 연결 시도도 멈췄어요.",
                    "블루투스 설정 열기",
                    "켜면 기본 기기에 자동으로 다시 연결해요.")
        }
    }

    private func action() {
        if isMDM {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Permissions.adminRequestText, forType: .string)
            copied = true
            return
        }
        switch problem {
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "iphone").font(.system(size: 19))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.lastDeviceName ?? "기본 기기 없음").font(Typo.font(14, .bold))
                            Text("기본 기기").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                        }
                    }
                    Button {
                        if let a = settings.lastDeviceAddress { model.connect(address: a) }
                    } label: {
                        Text(model.connection == .connecting ? "연결 중…" : "다시 연결").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle(height: 38))
                    .disabled(settings.lastDeviceAddress == nil || model.connection == .connecting)
                    Text(reason).font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("+ 새 기기 페어링") { model.openOnboarding(at: .pairing) }
                .buttonStyle(TextLinkStyle(color: .brandText))
                .font(Typo.font(12, .semibold))
        }
    }

    private var reason: String {
        if case let .failed(message) = model.connection {
            return "\(message). 아이폰 블루투스가 꺼져 있거나 멀리 있을 수 있어요."
        }
        return "아이폰 블루투스가 꺼져 있거나 멀리 있을 수 있어요. 자동으로 다시 시도해요."
    }
}

// MARK: - 2-1 연결됨 (3단계에서 전환 스위치·배치 미리보기를 채운다)

struct ConnectedCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack(spacing: 10) {
                    Image(systemName: "iphone").font(.system(size: 19)).foregroundStyle(Color.brandStrong)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.connectedName ?? "").font(Typo.font(14, .bold))
                        Text("연결됨 · 기본 기기").font(Typo.secondary).foregroundStyle(Color.successText)
                    }
                    Spacer()
                    Button("연결 끊기") { model.disconnect() }
                        .buttonStyle(PillButtonStyle(kind: .plain, height: 32))
                }
            }
            Text("모서리 전환은 다음 업데이트에서 켜져요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary)
        }
    }
}
