import AppKit
import EdgeLinkCore
import SwiftUI

/// 보정 도우미 진행 (캔버스 4-2, 실패는 4-3)
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
        phase = .preparing
        model.router.startCalibration { [weak self] event in
            DispatchQueue.main.async { self?.handle(event) }
        }
    }

    func cancel() {
        guard running else { return }
        model.router.cancelCalibration()
        phase = .intro(note: "보정을 취소했어요. 보정값은 그대로예요.")
    }

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
            let old = model.settings.unitsPerPoint
            if value < 0.2 {
                phase = .failed(title: "움직인 양이 너무 적어요",
                                reason: "아이폰 포인터를 오른쪽 아래 끝까지 옮기기 전에 클릭한 것 같아요.")
            } else {
                // 설계 문서 › 보정: 범위 0.6~4.0
                let v = min(max(value, 0.6), 4.0)
                model.settings.unitsPerPointValue = v
                phase = .done(old: old, new: v)
            }
        case let .failed(reason):
            phase = .failed(title: "보정하지 못했어요", reason: reason)
        case .cancelled:
            phase = .intro(note: "보정을 취소했어요. 보정값은 그대로예요.")
        }
    }
}

/// 포인터 보정 도우미 (시트 420)
struct CalibrationView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: AppSettings
    @ObservedObject var session: CalibrationSession
    let handle: DialogHandle

    var body: some View {
        DialogFrame(spacing: 16) {
            Text("포인터 보정 도우미").font(Typo.font(17, .bold))
            switch session.phase {
            case let .intro(note): intro(note)
            case .preparing, .measuring: measuring
            case let .done(old, new): done(old: old, new: new)
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

    private func format(_ v: Double) -> String { String(format: "%.2f", v) }

    // 안내

    private func intro(_ note: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("시작하면 아이폰 포인터가 화면 왼쪽 위 끝으로 가요. 트랙패드로 천천히 오른쪽 아래 끝까지 옮긴 뒤 클릭하세요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            CalibrationPhoneArt(progress: nil)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            VStack(alignment: .leading, spacing: 6) {
                if let note {
                    Text(note).font(Typo.secondary).foregroundStyle(Color.textPrimary)
                }
                Text("지금 보정값 \(format(settings.unitsPerPoint)) · 기본 2.00")
                    .font(Typo.secondary).foregroundStyle(Color.textSecondary)
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("닫기") { handle.close() }
                        .buttonStyle(DialogButtonStyle(kind: .plain))
                    Button("시작") { session.start() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
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

    // 진행

    private var measuring: some View {
        let moved: (Int, Int)? = { if case let .measuring(dx, dy) = session.phase { return (dx, dy) } else { return nil } }()
        return VStack(alignment: .leading, spacing: 16) {
            Text("시작하면 아이폰 포인터가 화면 왼쪽 위 끝으로 가요. 트랙패드로 천천히 오른쪽 아래 끝까지 옮긴 뒤 클릭하세요.")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            CalibrationPhoneArt(progress: moved.map { _ in 1 })
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            HStack(spacing: 10) {
                Spinner(size: 14)
                Text(moved == nil ? "아이폰 포인터를 왼쪽 위로 보내는 중…" : "오른쪽 아래 끝까지 옮기고 클릭하세요")
                    .font(Typo.font(13, .semibold))
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "움직인 양  가로 \(moved?.0 ?? 0) · 세로 \(moved?.1 ?? 0)")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.textSecondary)
                    .accessibilityLabel("움직인 양 가로 \(moved?.0 ?? 0), 세로 \(moved?.1 ?? 0)")
                Text("Esc를 누르면 취소돼요.").font(Typo.secondary).foregroundStyle(Color.textSecondary)
            }
            HStack {
                Spacer()
                Button("취소") { session.cancel() }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
            }
        }
    }

    // 결과

    private func done(old: Double, new: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.successText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("보정 완료 (\(format(new)))").font(Typo.font(13, .semibold))
                    Text("이제 돌아오는 위치가 포인터와 맞아요.").font(Typo.secondary).foregroundStyle(Color.textSecondary)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.bgSidebar))
            Text("이전 보정값 \(format(old)) → 새 보정값 \(format(new))")
                .font(Typo.secondary).foregroundStyle(Color.textSecondary)
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
                    Text("\(reason) 이전 보정값(\(format(settings.unitsPerPoint)))은 그대로 두었어요.")
                        .font(Typo.secondary).foregroundStyle(Color.textSecondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Button("기본값으로") {
                        session.resetToDefault()
                        model.showToast("보정값을 기본값(2.00)으로 바꿨어요")
                        handle.close()
                    }
                    .buttonStyle(DialogButtonStyle(kind: .plain))
                    Button("다시 하기") { session.start() }
                        .buttonStyle(DialogButtonStyle(kind: .primary))
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
            RoundedRectangle(cornerRadius: 11).fill(Color(hex: 0x2B2B2B)).padding(6)
            Path { p in
                p.move(to: CGPoint(x: 22, y: 24))
                p.addLine(to: CGPoint(x: 74, y: 156))
            }
            .stroke(Color.brand, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: progress == nil ? [4, 4] : []))
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
