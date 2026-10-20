import AppKit
import EdgeLinkCore
import SwiftUI

/// 돌아오는 위치 맞추기 진행 (캔버스 4-2, 실패는 4-3)
final class CalibrationSession: ObservableObject {
    enum Phase: Equatable {
        case intro(note: String?)
        /// 포인터를 왼쪽 위로 보내는 중
        case preparing
        case measuring(dx: Int, dy: Int)
        case done(old: Double, new: Double)
        case failed(title: String, reason: String)
    }

    @Published var phase: Phase
    /// 시작할 때의 보정값. 라우터가 끝나자마자 새 값을 저장하므로 미리 잡아 둔다.
    @Published private(set) var previous: Double?
    unowned let model: AppModel

    init(model: AppModel, phase: Phase = .intro(note: nil)) {
        self.model = model
        self.phase = phase
    }

    var running: Bool {
        switch phase {
        case .preparing, .measuring: return true
        default: return false
        }
    }

    func start() {
        guard model.isConnected, !running else { return }
        previous = model.settings.unitsPerPoint
        phase = .preparing
        model.router.startCalibration { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
    }

    func cancel() {
        guard running else { return }
        model.router.cancelCalibration()
        phase = .intro(note: Self.cancelledNote)
    }

    static let cancelledNote = "취소했어요. 이전 설정을 그대로 두었어요."

    func resetToDefault() {
        model.settings.unitsPerPointValue = 2.0
    }

    private func handle(_ event: CalibrationEvent) {
        // 취소한 뒤 늦게 온 소식은 무시한다
        guard running else { return }
        switch event {
        case .ready:
            phase = .measuring(dx: 0, dy: 0)
        case let .moved(dx, dy):
            phase = .measuring(dx: dx, dy: dy)
        case let .finished(value):
            // 저장은 라우터가 한다. 여기서는 받은 값을 보여주기만 한다.
            let old = previous ?? model.settings.unitsPerPoint
            if value < 0.2 {
                // 라우터가 이미 저장했을 수 있으니 이전 값으로 되돌린다 ("그대로 두었어요"가 맞게)
                if model.settings.unitsPerPointValue != old { model.settings.unitsPerPointValue = old }
                phase = .failed(title: "움직인 양이 너무 적어요",
                                reason: "아이폰 포인터를 오른쪽 아래 끝까지 옮기기 전에 클릭한 것 같아요.")
            } else {
                // 설계 문서 › 보정: 범위 0.6~4.0 (표시만 맞춘다)
                phase = .done(old: old, new: min(max(value, 0.6), 4.0))
            }
        case let .failed(reason):
            phase = .failed(title: "위치를 맞추지 못했어요", reason: reason)
        case .cancelled:
            phase = .intro(note: Self.cancelledNote)
        }
    }
}

/// 돌아오는 위치 맞추기 (시트 420). 보정값·움직인 양 같은 숫자는 이용자에게 보이지 않는다.
struct CalibrationView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: CalibrationSession
    let handle: DialogHandle

    var body: some View {
        DialogFrame(spacing: 16) {
            Text("돌아오는 위치 맞추기").font(Typo.font(17, .bold))
            switch session.phase {
            case let .intro(note): intro(note)
            case .preparing, .measuring: measuring
            case .done: done
            case let .failed(title, reason): failed(title, reason)
            }
        }
        .onAppear {
            handle.onCancel = {
                if session.running { session.cancel() } else { handle.close() }
            }
            handle.onClose = { session.cancel() }
        }
    }

    // 안내

    private func intro(_ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mac으로 돌아올 때 커서가 엉뚱한 곳에 나타나면 한 번 맞춰 주세요.")
                    .font(Typo.body).foregroundStyle(Color.textPrimary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text("시작하면 아이폰 포인터가 화면 왼쪽 위 끝으로 가요. 트랙패드나 마우스로 천천히 오른쪽 아래 끝까지 옮긴 뒤 클릭하세요.")
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CalibrationPhoneArt(progress: nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            if let note {
                Text(note).font(Typo.secondary).foregroundStyle(Color.textPrimary)
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("닫기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .plain))
                    Button("시작") { session.start() }
                        .buttonStyle(DialogButtonStyle(kind: .primary, dimWhenDisabled: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.isConnected)
                }
                if !model.isConnected {
                    Text("아이폰을 연결하면 쓸 수 있어요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    // 진행. 할 일은 상태 줄에 한 번만 쓴다.

    private var measuring: some View {
        let ready: Bool = { if case .measuring = session.phase { return true } else { return false } }()
        return VStack(alignment: .leading, spacing: 16) {
            CalibrationPhoneArt(progress: ready ? 1 : nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            HStack(spacing: 10) {
                Spinner(size: 14)
                Text(ready ? "트랙패드나 마우스로 오른쪽 아래 끝까지 옮기고 클릭하세요" : "아이폰 포인터를 왼쪽 위로 보내는 중…")
                    .font(Typo.font(13, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Text("Esc를 누르면 취소돼요.").font(Typo.secondary).foregroundStyle(Color.textSecondary)
            HStack {
                Spacer()
                Button("취소") { session.cancel() }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
            }
        }
    }

    // 결과

    private var done: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.successText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("완료했어요").font(Typo.font(13, .semibold))
                    Text("이제 Mac으로 돌아올 때 커서가 아이폰에서 있던 자리에 나타나요.")
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
            HStack(spacing: 8) {
                Spacer()
                Button("다시 하기") { session.start() }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                    .disabled(!model.isConnected)
                Button("완료") { handle.close() }
                    .buttonStyle(DialogButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failed(_ title: String, _ reason: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.dangerText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(Typo.font(13, .bold))
                    Text("\(reason) 이전\u{00A0}설정을 그대로 두었어요.")
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("처음 설정으로 되돌리기") {
                        session.resetToDefault()
                        model.showToast("처음 설정으로 되돌렸어요")
                        handle.close()
                    }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                    Button("다시 하기") { session.start() }
                        .buttonStyle(DialogButtonStyle(kind: .primary, dimWhenDisabled: true))
                        .keyboardShortcut(.defaultAction)
                        .disabled(!model.isConnected)
                }
                if !model.isConnected {
                    Text("아이폰을 연결하면 다시 할 수 있어요").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.top, 8)
        }
    }
}

/// 보정 안내 그림: 아이폰 화면, 왼쪽 위 시작점, 오른쪽 아래 끝점
struct CalibrationPhoneArt: View {
    /// nil이면 안내만, 값이 있으면 움직이는 중
    var progress: Double?

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x1A1A1A))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.deviceOutline, lineWidth: 1))
            RoundedRectangle(cornerRadius: 11).fill(Color(hex: 0x2B2B2B)).padding(6)
            Path { p in
                p.move(to: CGPoint(x: 22, y: 24))
                p.addLine(to: CGPoint(x: 74, y: 156))
            }
            .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            Circle().strokeBorder(Color.white, lineWidth: 2)
                .frame(width: 12, height: 12)
                .offset(x: 12, y: 14)
            Circle().fill(Color.brand)
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .frame(width: 14, height: 14)
                .offset(x: 96 - 12 - 14, y: 180 - 14 - 14)
        }
        .frame(width: 96, height: 180)
        .accessibilityHidden(true)
    }
}
