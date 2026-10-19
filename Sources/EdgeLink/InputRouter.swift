import AppKit
import Combine
import EdgeLinkCore

// 뼈대 (전환 담당 에이전트가 채운다). 공개 메서드 이름과 모양은 바꾸지 않는다.

/// 입력은 CGEventTap 하나로 받고, 모드에 따라 Mac에 그대로 보내거나 막고 HID 리포트로 바꿔 아이폰에 보낸다.
final class InputRouter {
    unowned let model: AppModel
    /// 온보딩 연습 단계 자동 체크용
    let practice = PassthroughSubject<PracticeEvent, Never>()

    init(model: AppModel) { self.model = model }

    /// 권한(손쉬운 사용·입력 모니터링)이 있을 때 이벤트 탭을 만든다. 여러 번 불러도 된다.
    func start() {}
    func stop() {}

    func enterPhone(_ reason: EnterReason) {}
    func returnToMac(_ reason: ReturnReason) {}
    func toggle() {}

    /// 클립보드의 영문·숫자·기호를 12ms 간격으로 타이핑. 확인 창은 AppModel.requestClipboardSend가 띄운다.
    func typeClipboard() {}

    /// 보정 도우미
    func startCalibration(_ update: @escaping (CalibrationEvent) -> Void) {}
    func cancelCalibration() {}

    /// 아이폰 버튼 등록 도우미: 추가 버튼 n(4~8)을 한 번 누른다
    func sendButton(_ n: Int) {}
}
