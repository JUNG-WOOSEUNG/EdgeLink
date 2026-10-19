import AppKit
import SwiftUI

// 뼈대 (설정 창 담당 에이전트가 채운다).

/// 설정 창 860×640, 탭 5개 (캔버스 3-1, 3-2)
final class SettingsWindowController {
    unowned let model: AppModel
    init(model: AppModel) { self.model = model }

    func show(tab: SettingsTab = .general) {}

    /// 아이폰 버튼 등록 도우미 창 (720×560, 캔버스 1-9). AppDialog.gestureSetup이 이걸 부른다.
    func showGestureSetup() {}
}
