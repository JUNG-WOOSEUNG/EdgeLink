import AppKit
import SwiftUI

// 뼈대 (팝오버·확인 창 담당 에이전트가 채운다).

/// AppDialog를 창(시트처럼 보이는 작은 창)으로 띄운다.
final class DialogPresenter {
    unowned let model: AppModel
    init(model: AppModel) { self.model = model }

    func present(_ dialog: AppDialog) {}
    func dismiss(_ dialog: AppDialog) {}
}
