import Foundation

// 여러 파일이 같이 쓰는 약속. 전환(InputRouter), 확인 창(DialogPresenter), 설정 창(SettingsWindowController)이
// 서로 직접 부르지 않고 AppModel을 거쳐 이 타입들로 주고받는다.

/// 조작 모드 (설계 문서 › 상태와 예외 처리: 조작 모드 3개)
enum ControlMode: Equatable {
    case mac
    case phone
    /// 보정 도우미가 아이폰 포인터 이동량을 재는 중 (아이폰 조작과 같지만 위치 추정·복귀를 하지 않음)
    case calibrating
}

/// 아이폰 조작으로 넘어간 이유
enum EnterReason: Equatable {
    case edge       // 파란 구간을 밀어서
    case hotkey     // ⌃⌥⌘Space
    case menu       // 팝오버의 조작 기기 전환
}

/// Mac 조작으로 돌아온 이유. 알림 문구와 로그에 쓴다.
enum ReturnReason: Equatable {
    case edge                // 아이폰 화면 끝에서 반대로 밀어서
    case hotkey
    case menu
    case secureInput         // 비밀번호 입력이 시작됨
    case tapDisabled         // 이벤트 탭이 시간 초과로 꺼짐
    case disconnected        // 블루투스 끊김
    case permissionLost      // 손쉬운 사용·입력 모니터링 꺼짐
    case screenLocked        // 화면 잠금, 화면 보호기, 사용자 전환
    case screensChanged      // 모니터 구성·해상도 변경
    case transportStalled    // 블루투스 쓰기가 3번 연속 50ms 넘음
    case sleep

    /// 사용자에게 보여줄 알림 (nil이면 알리지 않음)
    var toast: String? {
        switch self {
        case .secureInput: return "Mac에서 비밀번호 입력이 시작돼서 Mac으로 돌아왔어요"
        case .screenLocked: return "화면이 잠겨서 Mac으로 돌아왔어요"
        case .tapDisabled, .transportStalled: return "연결이 잠깐 멈춰서 Mac으로 돌아왔어요"
        case .disconnected: return "아이폰 연결이 끊겨서 돌아왔어요"
        case .permissionLost: return "권한이 꺼져서 돌아왔어요"
        default: return nil
        }
    }
}

/// 온보딩 7단계(연습) 자동 체크용
enum PracticeEvent: Equatable {
    case enteredByEdge, returnedByEdge, toggledByHotkey
}

/// 보정 도우미 진행 (설계 문서 › 보정)
enum CalibrationEvent: Equatable {
    /// 아이폰 포인터를 왼쪽 위로 보냈어요. 이제 오른쪽 아래까지 옮기고 클릭하세요.
    case ready
    /// 지금까지 움직인 HID 단위 (이용자에게는 숫자를 보여주지 않는다)
    case moved(dx: Int, dy: Int)
    /// 결과: 보정값(HID 단위/pt). 0.2보다 작으면 실패로 보고 저장하지 않는다.
    case finished(unitsPerPoint: Double)
    case failed(reason: String)
    case cancelled
}

/// 앱 어디서든 띄우는 확인 창 (캔버스 4-1, 4-4)
enum AppDialog: Equatable, Identifiable {
    /// 기본 기기가 아닌 기기가 연결해 옴. 30초 안에 답이 없으면 거절.
    case connectionRequest(name: String, address: String)
    /// 클립보드 보내기 첫 사용, 또는 영문 외 글자가 섞였을 때
    case clipboardConfirm(sendable: Int, skipped: Int)
    /// 기록한 단축키가 macOS 시스템 단축키와 겹침
    case shortcutConflict(action: HotkeyAction, hotkey: Hotkey, conflictsWith: String)
    /// 설정 › 연결 › 페어링 초기화
    case resetPairing
    /// 설정 › 연결 › 연결 로그 보기
    case connectionLog
    /// 돌아오는 위치 맞추기 (설정 › 배치, 처음 설정 연습)
    case calibration
    /// 트랙패드 제스처 설정 (설정 › 입력, 처음 설정 뒤 선택 단계)
    case gestureSetup
    /// 새 버전 알림 (자동 확인, 설정 › 정보 › 지금 확인)
    case update(version: String)

    var id: String {
        switch self {
        case .connectionRequest(_, let a): return "connectionRequest-\(a)"
        case .clipboardConfirm: return "clipboardConfirm"
        case .shortcutConflict(let a, _, _): return "shortcutConflict-\(a.rawValue)"
        case .resetPairing: return "resetPairing"
        case .connectionLog: return "connectionLog"
        case .calibration: return "calibration"
        case .gestureSetup: return "gestureSetup"
        case .update: return "update"
        }
    }
}

/// 설정 창 탭 (캔버스 3-1)
enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layout, input, connection, about
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "일반"
        case .layout: return "배치"
        case .input: return "입력"
        case .connection: return "연결"
        case .about: return "정보"
        }
    }
}
