import AppKit
import EdgeLinkCore
import SwiftUI

/// AppDialog를 작은 창(시트처럼 보이는 창)으로 띄운다 (캔버스 4-1, 4-2, 4-4).
/// - 앱을 앞으로 가져오고 화면 가운데에 띄운다.
/// - 같은 종류는 하나만. 이미 떠 있으면 앞으로 가져온다(내용이 다르면 바꾼다).
///   연결 요청은 같은 요청이 다시 와도 포커스를 뺏지 않고 그대로 둔다.
/// - Esc로 닫는다. 연결 요청은 Esc가 거절이다.
final class DialogPresenter: NSObject, NSWindowDelegate {
    unowned let model: AppModel
    private var windows: [String: DialogWindow] = [:]
    private var shown: [String: AppDialog] = [:]

    init(model: AppModel) {
        self.model = model
        super.init()
    }

    func present(_ dialog: AppDialog) {
        if case .gestureSetup = dialog {
            model.settingsWindow.showGestureSetup()
            return
        }
        let key = dialog.kind
        if let w = windows[key] {
            if shown[key] == dialog {
                // 아이폰이 같은 요청을 되풀이해 보내도 하던 일을 끊지 않는다
                if case .connectionRequest = dialog { return }
                bringFront(w)
                return
            }
            // 같은 종류의 다른 내용 (예: 다른 기기의 연결 요청): 앞의 것은 취소 처리하고 새로 띄운다
            w.handle.cancel()
            w.close()
        }
        let handle = DialogHandle()
        let w = DialogWindow(handle: handle)
        w.delegate = self
        w.level = dialog.floats ? .floating : .normal
        w.title = dialog.title
        handle.window = w
        let host = NSHostingController(rootView: content(dialog, handle: handle)
            .environmentObject(model)
            .environmentObject(model.settings)
            .environmentObject(model.permissions))
        host.sizingOptions = [.preferredContentSize]
        w.contentViewController = host
        w.layoutIfNeeded()
        w.center()
        windows[key] = w
        shown[key] = dialog
        bringFront(w)
    }

    func dismiss(_ dialog: AppDialog) {
        if case .gestureSetup = dialog { return }
        windows[dialog.kind]?.close()
    }

    private func bringFront(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    @ViewBuilder
    private func content(_ dialog: AppDialog, handle: DialogHandle) -> some View {
        switch dialog {
        case let .connectionRequest(name, address):
            ConnectionRequestView(name: name, address: address, handle: handle)
        case let .clipboardConfirm(sendable, skipped):
            ClipboardConfirmView(sendable: sendable, skipped: skipped, handle: handle)
        case let .shortcutConflict(action, hotkey, conflictsWith):
            ShortcutConflictView(action: action, hotkey: hotkey, conflictsWith: conflictsWith, handle: handle)
        case .resetPairing:
            ResetPairingView(handle: handle)
        case .connectionLog:
            ConnectionLogView(handle: handle)
        case .calibration:
            CalibrationView(session: CalibrationSession(model: model), handle: handle)
        case .gestureSetup:
            EmptyView()
        case .update:
            UpdateView(updater: model.updater, handle: handle)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let w = notification.object as? DialogWindow,
              let key = windows.first(where: { $0.value === w })?.key else { return }
        w.handle.closed()
        windows[key] = nil
        shown[key] = nil
    }
}

/// 창과 내용 사이의 연결. 내용 쪽에서 닫거나, Esc·창 닫힘 때 할 일을 정한다.
final class DialogHandle {
    weak var window: NSWindow?
    /// Esc를 눌렀을 때 (없으면 그냥 닫는다)
    var onCancel: (() -> Void)?
    /// 어떤 이유로든 창이 닫힐 때 한 번
    var onClose: (() -> Void)?
    private var didClose = false

    func close() { window?.close() }

    /// 여러 번 불려도 된다 (보정 도우미는 Esc마다 취소·닫기를 고른다). 한 번만 처리할 일은 내용 쪽에서 막는다.
    func cancel() {
        if let onCancel { onCancel() } else { close() }
    }

    /// 창이 닫힐 때 한 번. 내용 쪽 클로저가 이 핸들을 붙잡고 있으므로 여기서 끊는다 (순환 참조).
    fileprivate func closed() {
        guard !didClose else { return }
        didClose = true
        let close = onClose
        onCancel = nil
        onClose = nil
        close?()
    }
}

final class DialogWindow: NSWindow {
    let handle: DialogHandle

    init(handle: DialogHandle) {
        self.handle = handle
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                   styleMask: [.titled, .closable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(b)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc
    override func cancelOperation(_ sender: Any?) { handle.cancel() }
}

extension AppDialog {
    /// 같은 종류는 하나만 띄우기 위한 이름
    var kind: String {
        switch self {
        case .connectionRequest: return "connectionRequest"
        case .clipboardConfirm: return "clipboardConfirm"
        case .shortcutConflict: return "shortcutConflict"
        case .resetPairing: return "resetPairing"
        case .connectionLog: return "connectionLog"
        case .calibration: return "calibration"
        case .gestureSetup: return "gestureSetup"
        case .update: return "update"
        }
    }

    /// 다른 창 위에 띄울지 (팝오버·단축키에서 바로 뜨는 확인 창)
    var floats: Bool {
        switch self {
        case .connectionRequest, .clipboardConfirm: return true
        default: return false
        }
    }

    /// 창 제목 (보이지 않지만 창 목록과 VoiceOver에서 읽는다)
    var title: String {
        switch self {
        case .connectionRequest: return "연결 요청"
        case .clipboardConfirm: return "클립보드 보내기"
        case .shortcutConflict: return "단축키 겹침"
        case .resetPairing: return "페어링 초기화"
        case .connectionLog: return "연결 로그"
        case .calibration: return "포인터 보정 도우미"
        case .gestureSetup: return "아이폰 버튼 등록 도우미"
        case .update: return "업데이트"
        }
    }
}
