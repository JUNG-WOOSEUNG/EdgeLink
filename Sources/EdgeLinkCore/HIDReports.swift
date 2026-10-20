import Foundation
import os

// MARK: - HID 디스크립터

/// 키보드(Report 1) + 마우스(Report 2) + Consumer Control(Report 3) 콤보 장치.
public enum HIDDescriptor {
    public static let keyboardReportID: UInt8 = 1
    public static let mouseReportID: UInt8 = 2
    public static let consumerReportID: UInt8 = 3

    public static let bytes: [UInt8] = keyboard + mouse + consumer

    /// 수정키 1 + 예약 1 + 키 6. LED 출력 리포트 1바이트.
    static let keyboard: [UInt8] = [
        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x06,       // Usage (Keyboard)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x01,       //   Report ID 1
        0x05, 0x07,       //   Usage Page (Keyboard/Keypad)
        0x19, 0xE0,       //   Usage Minimum (Left Control)
        0x29, 0xE7,       //   Usage Maximum (Right GUI)
        0x15, 0x00,       //   Logical Minimum 0
        0x25, 0x01,       //   Logical Maximum 1
        0x75, 0x01,       //   Report Size 1
        0x95, 0x08,       //   Report Count 8
        0x81, 0x02,       //   Input (Data, Var, Abs) — 수정키
        0x95, 0x01,       //   Report Count 1
        0x75, 0x08,       //   Report Size 8
        0x81, 0x01,       //   Input (Const) — 예약
        0x95, 0x05,       //   Report Count 5
        0x75, 0x01,       //   Report Size 1
        0x05, 0x08,       //   Usage Page (LEDs)
        0x19, 0x01,       //   Usage Minimum (Num Lock)
        0x29, 0x05,       //   Usage Maximum (Kana)
        0x91, 0x02,       //   Output (Data, Var, Abs)
        0x95, 0x01,       //   Report Count 1
        0x75, 0x03,       //   Report Size 3
        0x91, 0x01,       //   Output (Const)
        0x95, 0x06,       //   Report Count 6
        0x75, 0x08,       //   Report Size 8
        0x15, 0x00,       //   Logical Minimum 0
        0x26, 0xFF, 0x00, //   Logical Maximum 255
        0x05, 0x07,       //   Usage Page (Keyboard/Keypad)
        0x19, 0x00,       //   Usage Minimum 0
        0x2A, 0xFF, 0x00, //   Usage Maximum 255
        0x81, 0x00,       //   Input (Data, Array) — 키 6개
        0xC0,             // End Collection
    ]

    /// 버튼 8개 + X·Y·휠·가로 스크롤 각 1바이트(−127~127).
    static let mouse: [UInt8] = [
        0x05, 0x01,       // Usage Page (Generic Desktop)
        0x09, 0x02,       // Usage (Mouse)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x02,       //   Report ID 2
        0x09, 0x01,       //   Usage (Pointer)
        0xA1, 0x00,       //   Collection (Physical)
        0x05, 0x09,       //     Usage Page (Button)
        0x19, 0x01,       //     Usage Minimum (Button 1)
        0x29, 0x08,       //     Usage Maximum (Button 8)
        0x15, 0x00,       //     Logical Minimum 0
        0x25, 0x01,       //     Logical Maximum 1
        0x95, 0x08,       //     Report Count 8
        0x75, 0x01,       //     Report Size 1
        0x81, 0x02,       //     Input (Data, Var, Abs)
        0x05, 0x01,       //     Usage Page (Generic Desktop)
        0x09, 0x30,       //     Usage (X)
        0x09, 0x31,       //     Usage (Y)
        0x09, 0x38,       //     Usage (Wheel)
        0x15, 0x81,       //     Logical Minimum −127
        0x25, 0x7F,       //     Logical Maximum 127
        0x75, 0x08,       //     Report Size 8
        0x95, 0x03,       //     Report Count 3
        0x81, 0x06,       //     Input (Data, Var, Rel)
        0x05, 0x0C,       //     Usage Page (Consumer)
        0x0A, 0x38, 0x02, //     Usage (AC Pan)
        0x15, 0x81,       //     Logical Minimum −127
        0x25, 0x7F,       //     Logical Maximum 127
        0x75, 0x08,       //     Report Size 8
        0x95, 0x01,       //     Report Count 1
        0x81, 0x06,       //     Input (Data, Var, Rel)
        0xC0,             //   End Collection
        0xC0,             // End Collection
    ]

    /// 16비트 Consumer 용도 하나 (볼륨, 재생 등).
    static let consumer: [UInt8] = [
        0x05, 0x0C,       // Usage Page (Consumer)
        0x09, 0x01,       // Usage (Consumer Control)
        0xA1, 0x01,       // Collection (Application)
        0x85, 0x03,       //   Report ID 3
        0x15, 0x00,       //   Logical Minimum 0
        0x26, 0xFF, 0x03, //   Logical Maximum 0x3FF
        0x19, 0x00,       //   Usage Minimum 0
        0x2A, 0xFF, 0x03, //   Usage Maximum 0x3FF
        0x75, 0x10,       //   Report Size 16
        0x95, 0x01,       //   Report Count 1
        0x81, 0x00,       //   Input (Data, Array)
        0xC0,             // End Collection
    ]
}

// MARK: - HIDP 메시지

/// Bluetooth HID Profile 전송 헤더 (상위 4비트 = 종류, 하위 4비트 = 인자).
public enum HIDP {
    public static let dataInput: UInt8 = 0xA1
    public static let dataOutput: UInt8 = 0xA2
    public static let dataOther: UInt8 = 0xA0

    public enum Handshake: UInt8 {
        case successful = 0x00
        case notReady = 0x01
        case invalidReportID = 0x02
        case unsupportedRequest = 0x03
        case invalidParameter = 0x04
        case unknown = 0x0E
        case fatal = 0x0F
    }

    public enum MessageType: UInt8 {
        case handshake = 0x0
        case control = 0x1
        case getReport = 0x4
        case setReport = 0x5
        case getProtocol = 0x6
        case setProtocol = 0x7
        case getIdle = 0x8
        case setIdle = 0x9
        case data = 0xA
    }

    public static let controlVirtualCableUnplug: UInt8 = 0x05

    /// 제어 채널로 받은 요청에 대한 응답. 응답이 필요 없으면 nil.
    public enum ControlResult: Equatable {
        case reply([UInt8])
        case virtualCableUnplug
        case ignore
    }

    /// 아이폰(호스트)이 제어 채널로 보낸 메시지를 해석한다.
    /// - Parameter outputReport: SET_REPORT로 받은 출력 리포트(LED)를 넘길 곳
    public static func handleControl(_ bytes: [UInt8], outputReport: (([UInt8]) -> Void)? = nil) -> ControlResult {
        guard let header = bytes.first else { return .ignore }
        let param = header & 0x0F
        switch MessageType(rawValue: header >> 4) {
        case .control:
            return param == controlVirtualCableUnplug ? .virtualCableUnplug : .ignore
        case .getReport:
            let reportType = param & 0x03
            guard bytes.count >= 2 else { return .reply([Handshake.invalidParameter.rawValue]) }
            if reportType == 2, bytes[1] == HIDDescriptor.keyboardReportID {
                return .reply([dataOutput, HIDDescriptor.keyboardReportID, 0x00])
            }
            guard reportType == 1 else { return .reply([Handshake.invalidParameter.rawValue]) }
            switch bytes[1] {
            case HIDDescriptor.keyboardReportID: return .reply(KeyboardReport().bytes)
            case HIDDescriptor.mouseReportID: return .reply(MouseReport().bytes)
            case HIDDescriptor.consumerReportID: return .reply(ConsumerReport(usage: 0).bytes)
            default: return .reply([Handshake.invalidReportID.rawValue])
            }
        case .setReport:
            // 출력 리포트(LED)만 반영하고, 입력·기능 리포트는 받기만 한다
            if param & 0x03 == 2, bytes.count >= 2 { outputReport?(Array(bytes.dropFirst())) }
            return .reply([Handshake.successful.rawValue])
        case .getProtocol:
            return .reply([dataOther, 0x01]) // 1 = Report 프로토콜
        case .setProtocol, .setIdle:
            return .reply([Handshake.successful.rawValue])
        case .getIdle:
            return .reply([dataOther, 0x00])
        case .handshake, .data:
            return .ignore
        case .none:
            return .reply([Handshake.unsupportedRequest.rawValue])
        }
    }
}

// MARK: - 리포트

public struct KeyboardReport: Equatable {
    public var modifiers: UInt8 = 0
    public var keys: [UInt8] = []

    public init(modifiers: UInt8 = 0, keys: [UInt8] = []) {
        self.modifiers = modifiers
        self.keys = Array(keys.prefix(6))
    }

    /// 인터럽트 채널로 보내는 바이트 (헤더 포함 10바이트).
    public var bytes: [UInt8] {
        var out: [UInt8] = [HIDP.dataInput, HIDDescriptor.keyboardReportID, modifiers, 0]
        out += keys.prefix(6)
        out += [UInt8](repeating: 0, count: 6 - min(keys.count, 6))
        return out
    }
}

public struct MouseReport: Equatable {
    public var buttons: UInt8 = 0
    public var dx: Int8 = 0
    public var dy: Int8 = 0
    public var wheel: Int8 = 0
    public var pan: Int8 = 0

    public init(buttons: UInt8 = 0, dx: Int8 = 0, dy: Int8 = 0, wheel: Int8 = 0, pan: Int8 = 0) {
        self.buttons = buttons
        self.dx = dx
        self.dy = dy
        self.wheel = wheel
        self.pan = pan
    }

    /// 인터럽트 채널로 보내는 바이트 (헤더 포함 7바이트).
    public var bytes: [UInt8] {
        [HIDP.dataInput, HIDDescriptor.mouseReportID, buttons,
         UInt8(bitPattern: dx), UInt8(bitPattern: dy), UInt8(bitPattern: wheel), UInt8(bitPattern: pan)]
    }

    /// 127을 넘는 움직임을 여러 리포트로 나눈다. 각 리포트는 −127~127.
    public static func split(dx: Int, dy: Int, wheel: Int = 0, pan: Int = 0, buttons: UInt8 = 0) -> [MouseReport] {
        var rx = dx, ry = dy, rw = wheel, rp = pan
        var out: [MouseReport] = []
        repeat {
            let cx = clamp127(rx), cy = clamp127(ry), cw = clamp127(rw), cp = clamp127(rp)
            out.append(MouseReport(buttons: buttons, dx: Int8(cx), dy: Int8(cy), wheel: Int8(cw), pan: Int8(cp)))
            rx -= cx; ry -= cy; rw -= cw; rp -= cp
        } while rx != 0 || ry != 0 || rw != 0 || rp != 0
        return out
    }

    private static func clamp127(_ v: Int) -> Int { max(-127, min(127, v)) }
}

public struct ConsumerReport: Equatable {
    public var usage: UInt16

    public init(usage: UInt16) { self.usage = usage }

    public var bytes: [UInt8] {
        [HIDP.dataInput, HIDDescriptor.consumerReportID, UInt8(usage & 0xFF), UInt8(usage >> 8)]
    }

    public static let volumeUp: UInt16 = 0x00E9
    public static let volumeDown: UInt16 = 0x00EA
    public static let mute: UInt16 = 0x00E2
    public static let playPause: UInt16 = 0x00CD
    public static let nextTrack: UInt16 = 0x00B5
    public static let previousTrack: UInt16 = 0x00B6
}

/// 출력 리포트(아이폰 → Mac)의 LED 상태.
public struct KeyboardLEDs: OptionSet, Equatable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let numLock = KeyboardLEDs(rawValue: 0x01)
    public static let capsLock = KeyboardLEDs(rawValue: 0x02)
    public static let scrollLock = KeyboardLEDs(rawValue: 0x04)

    /// SET_REPORT 또는 인터럽트 채널 DATA(0xA2) 본문에서 LED를 읽는다. 본문 = [보고서 ID, LED].
    public init?(outputReport body: [UInt8]) {
        guard body.count >= 2, body[0] == HIDDescriptor.keyboardReportID else { return nil }
        self.init(rawValue: body[1])
    }
}

// MARK: - 키 상태

/// 눌린 키를 기억해서 키보드 리포트를 만든다. 최대 6키, 넘치면 새 키는 무시.
/// 오른쪽 수정키도 왼쪽 비트로 보내므로, 수정키는 누른 개수를 센다 (왼쪽 ⇧을 누른 채 오른쪽 ⇧을 떼도 ⇧ 유지).
public struct KeyboardState {
    public private(set) var modifiers: UInt8 = 0
    public private(set) var pressed: [UInt8] = []
    private var modifierCounts = [Int](repeating: 0, count: 8)

    public init() {}

    /// 상태가 바뀌었으면 보낼 리포트를 돌려준다.
    public mutating func press(_ usage: UInt8) -> KeyboardReport? {
        if let bit = HIDUsage.modifierBit(usage) {
            modifierCounts[Int(usage - 0xE0)] += 1
            guard modifiers & bit == 0 else { return nil }
            modifiers |= bit
        } else {
            guard !pressed.contains(usage), pressed.count < 6 else { return nil }
            pressed.append(usage)
        }
        return report
    }

    public mutating func release(_ usage: UInt8) -> KeyboardReport? {
        if let bit = HIDUsage.modifierBit(usage) {
            let i = Int(usage - 0xE0)
            guard modifierCounts[i] > 0 else { return nil }
            modifierCounts[i] -= 1
            guard modifierCounts[i] == 0 else { return nil }
            modifiers &= ~bit
        } else {
            guard let i = pressed.firstIndex(of: usage) else { return nil }
            pressed.remove(at: i)
        }
        return report
    }

    public mutating func releaseAll() -> KeyboardReport {
        modifiers = 0
        pressed = []
        modifierCounts = [Int](repeating: 0, count: 8)
        return report
    }

    public var report: KeyboardReport { KeyboardReport(modifiers: modifiers, keys: pressed) }
}

// MARK: - 키 매핑

public enum HIDUsage {
    public static let leftControl: UInt8 = 0xE0
    public static let leftShift: UInt8 = 0xE1
    public static let leftAlt: UInt8 = 0xE2
    public static let leftGUI: UInt8 = 0xE3
    public static let capsLock: UInt8 = 0x39
    public static let space: UInt8 = 0x2C
    public static let returnKey: UInt8 = 0x28

    public static func modifierBit(_ usage: UInt8) -> UInt8? {
        (0xE0...0xE7).contains(usage) ? UInt8(1) << (usage - 0xE0) : nil
    }

    /// macOS 가상 키코드(kVK_*) → HID Usage. 오른쪽 수정키는 왼쪽으로 보낸다.
    /// Fn·Globe(0x3F)와 미디어 키는 없다.
    public static func fromMacKeyCode(_ code: UInt16) -> UInt8? { macKeyCodeTable[code] }

    static let macKeyCodeTable: [UInt16: UInt8] = [
        0x00: 0x04, 0x01: 0x16, 0x02: 0x07, 0x03: 0x09, 0x04: 0x0B, 0x05: 0x0A, 0x06: 0x1D, 0x07: 0x1B,
        0x08: 0x06, 0x09: 0x19, 0x0A: 0x64, 0x0B: 0x05, 0x0C: 0x14, 0x0D: 0x1A, 0x0E: 0x08, 0x0F: 0x15,
        0x10: 0x1C, 0x11: 0x17, 0x12: 0x1E, 0x13: 0x1F, 0x14: 0x20, 0x15: 0x21, 0x16: 0x23, 0x17: 0x22,
        0x18: 0x2E, 0x19: 0x26, 0x1A: 0x24, 0x1B: 0x2D, 0x1C: 0x25, 0x1D: 0x27, 0x1E: 0x30, 0x1F: 0x12,
        0x20: 0x18, 0x21: 0x2F, 0x22: 0x0C, 0x23: 0x13, 0x24: 0x28, 0x25: 0x0F, 0x26: 0x0D, 0x27: 0x34,
        0x28: 0x0E, 0x29: 0x33, 0x2A: 0x31, 0x2B: 0x36, 0x2C: 0x38, 0x2D: 0x11, 0x2E: 0x10, 0x2F: 0x37,
        0x30: 0x2B, 0x31: 0x2C, 0x32: 0x35, 0x33: 0x2A, 0x35: 0x29,
        // 수정키: ⌘ ⇧ ⌥ ⌃ (오른쪽도 왼쪽으로)
        0x37: 0xE3, 0x36: 0xE3, 0x38: 0xE1, 0x3C: 0xE1, 0x3A: 0xE2, 0x3D: 0xE2, 0x3B: 0xE0, 0x3E: 0xE0,
        0x39: 0x39,
        // 키패드
        0x41: 0x63, 0x43: 0x55, 0x45: 0x57, 0x47: 0x53, 0x4B: 0x54, 0x4C: 0x58, 0x4E: 0x56, 0x51: 0x67,
        0x52: 0x62, 0x53: 0x59, 0x54: 0x5A, 0x55: 0x5B, 0x56: 0x5C, 0x57: 0x5D, 0x58: 0x5E, 0x59: 0x5F,
        0x5B: 0x60, 0x5C: 0x61,
        // JIS: ¥ _ 키패드 , 英数 かな
        0x5D: 0x89, 0x5E: 0x87, 0x5F: 0x85, 0x66: 0x91, 0x68: 0x90,
        // F1~F20
        0x7A: 0x3A, 0x78: 0x3B, 0x63: 0x3C, 0x76: 0x3D, 0x60: 0x3E, 0x61: 0x3F, 0x62: 0x40, 0x64: 0x41,
        0x65: 0x42, 0x6D: 0x43, 0x67: 0x44, 0x6F: 0x45, 0x69: 0x68, 0x6B: 0x69, 0x71: 0x6A, 0x6A: 0x6B,
        0x40: 0x6C, 0x4F: 0x6D, 0x50: 0x6E, 0x5A: 0x6F,
        // 탐색
        0x6E: 0x65, 0x72: 0x49, 0x73: 0x4A, 0x74: 0x4B, 0x75: 0x4C, 0x77: 0x4D, 0x79: 0x4E,
        0x7B: 0x50, 0x7C: 0x4F, 0x7D: 0x51, 0x7E: 0x52,
    ]

    /// 클립보드 보내기용: 영문·숫자·기호(US 배열) → (Usage, Shift 필요).
    /// 그 외 글자는 nil — 호출한 쪽이 빼고 알린다.
    public static func fromASCII(_ ch: Character) -> (usage: UInt8, shift: Bool)? {
        guard let a = ch.asciiValue else { return nil }
        switch a {
        case 0x61...0x7A: return (0x04 + (a - 0x61), false)        // a–z
        case 0x41...0x5A: return (0x04 + (a - 0x41), true)         // A–Z
        case 0x31...0x39: return (0x1E + (a - 0x31), false)        // 1–9
        case 0x30: return (0x27, false)                            // 0
        case 0x0A, 0x0D: return (0x28, false)                      // 줄바꿈 → Return
        case 0x09: return (0x2B, false)                            // Tab
        default: return asciiSymbols[a]
        }
    }

    static let asciiSymbols: [UInt8: (usage: UInt8, shift: Bool)] = [
        0x20: (0x2C, false), // space
        0x21: (0x1E, true),  // !
        0x40: (0x1F, true),  // @
        0x23: (0x20, true),  // #
        0x24: (0x21, true),  // $
        0x25: (0x22, true),  // %
        0x5E: (0x23, true),  // ^
        0x26: (0x24, true),  // &
        0x2A: (0x25, true),  // *
        0x28: (0x26, true),  // (
        0x29: (0x27, true),  // )
        0x2D: (0x2D, false), // -
        0x5F: (0x2D, true),  // _
        0x3D: (0x2E, false), // =
        0x2B: (0x2E, true),  // +
        0x5B: (0x2F, false), // [
        0x7B: (0x2F, true),  // {
        0x5D: (0x30, false), // ]
        0x7D: (0x30, true),  // }
        0x5C: (0x31, false), // \
        0x7C: (0x31, true),  // |
        0x3B: (0x33, false), // ;
        0x3A: (0x33, true),  // :
        0x27: (0x34, false), // '
        0x22: (0x34, true),  // "
        0x60: (0x35, false), // `
        0x7E: (0x35, true),  // ~
        0x2C: (0x36, false), // ,
        0x3C: (0x36, true),  // <
        0x2E: (0x37, false), // .
        0x3E: (0x37, true),  // >
        0x2F: (0x38, false), // /
        0x3F: (0x38, true),  // ?
    ]

    /// 글자 하나를 누름·뗌 리포트 두 개로 만든다.
    public static func typingReports(for ch: Character) -> [KeyboardReport]? {
        guard let (usage, shift) = fromASCII(ch) else { return nil }
        let mods: UInt8 = shift ? modifierBit(leftShift)! : 0
        return [KeyboardReport(modifiers: mods, keys: [usage]), KeyboardReport()]
    }
}

// MARK: - SDP 레코드

/// IOBluetoothSDPServiceRecord.publishedServiceRecord(with:)에 넘기는 사전.
/// 값은 모두 DataElementType/Size/Value로 명시해서 타입 추측에 기대지 않는다.
public enum HIDServiceRecord {
    public static func dictionary(serviceName: String = "EdgeLink",
                                  descriptor: [UInt8] = HIDDescriptor.bytes) -> [String: Any] {
        [
            "0001 - ServiceClassIDList": [uuid16(0x1124)],
            "0004 - ProtocolDescriptorList": [
                [uuid16(0x0100), uint(16, 0x0011)],   // L2CAP, PSM 제어 채널
                [uuid16(0x0011)],                     // HIDP
            ],
            "0005 - BrowseGroupList": [uuid16(0x1002)],
            "0006 - LanguageBaseAttributeIDList": [uint(16, 0x656E), uint(16, 0x006A), uint(16, 0x0100)],
            "0009 - BluetoothProfileDescriptorList": [[uuid16(0x1124), uint(16, 0x0101)]],
            "000D - AdditionalProtocolDescriptorLists": [[
                [uuid16(0x0100), uint(16, 0x0013)],   // L2CAP, PSM 인터럽트 채널
                [uuid16(0x0011)],
            ]],
            "0100 - ServiceName": string(serviceName),
            "0101 - ServiceDescription": string("Keyboard and Trackpad"),
            "0102 - ProviderName": string("EdgeLink"),
            "0200 - DeviceReleaseNumber": uint(16, 0x0100),
            "0201 - HIDParserVersion": uint(16, 0x0111),
            "0202 - HIDDeviceSubclass": uint(8, 0xC0),   // 키보드 + 포인팅 콤보
            "0203 - HIDCountryCode": uint(8, 0x00),
            "0204 - HIDVirtualCable": bool(true),
            "0205 - HIDReconnectInitiate": bool(true),
            "0206 - HIDDescriptorList": [[uint(8, 0x22), dataString(descriptor)]],
            "0207 - HIDLANGIDBaseList": [[uint(16, 0x0409), uint(16, 0x0100)]],
            "0209 - HIDBatteryPower": bool(true),
            "020A - HIDRemoteWake": bool(true),
            "020B - HIDProfileVersion": uint(16, 0x0101),
            "020C - HIDSupervisionTimeout": uint(16, 0x0C80),
            "020D - HIDNormallyConnectable": bool(true),
            "020E - HIDBootDevice": bool(false),
        ]
    }

    static func element(type: Int, size: Int, value: Any) -> [String: Any] {
        ["DataElementType": type, "DataElementSize": size, "DataElementValue": value]
    }
    static func uint(_ bits: Int, _ v: Int) -> [String: Any] { element(type: 1, size: bits / 8, value: v) }
    static func uuid16(_ v: UInt16) -> [String: Any] {
        element(type: 3, size: 2, value: Data([UInt8(v >> 8), UInt8(v & 0xFF)]))
    }
    static func string(_ s: String) -> [String: Any] { element(type: 4, size: s.utf8.count, value: s) }
    static func dataString(_ bytes: [UInt8]) -> [String: Any] { element(type: 4, size: bytes.count, value: Data(bytes)) }
    static func bool(_ b: Bool) -> [String: Any] { element(type: 5, size: 1, value: b ? 1 : 0) }
}

// MARK: - 로그

/// 동작만 남긴다. 키 입력·클립보드 내용은 절대 넘기지 않는다.
public enum HIDLog {
    public enum Level: String { case info = "INFO", warn = "WARN", error = "ERROR", debug = "DEBUG" }

    private static let logger = Logger(subsystem: "com.edgelink", category: "hid")
    private static let lock = NSLock()
    private static var buffer: [String] = []
    public static var echo: ((String) -> Void)? = { FileHandle.standardError.write(($0 + "\n").data(using: .utf8)!) }
    public static var verbose = false
    public static let capacity = 500

    public static func info(_ message: String) { write(.info, message) }
    public static func warn(_ message: String) { write(.warn, message) }
    public static func error(_ message: String) { write(.error, message) }
    public static func debug(_ message: String) { if verbose { write(.debug, message) } }

    public static func write(_ level: Level, _ message: String) {
        let line = "\(timestamp()) [\(level.rawValue)] \(message)"
        // 시스템 로그에는 블루투스 주소 뒷자리를 가려서 남긴다
        let masked = maskAddress(message)
        switch level {
        case .error: logger.error("\(masked, privacy: .public)")
        case .warn: logger.warning("\(masked, privacy: .public)")
        default: logger.info("\(masked, privacy: .public)")
        }
        lock.lock()
        appendToFile(maskAddress(line))
        buffer.append(line)
        if buffer.count > capacity { buffer.removeFirst(buffer.count - capacity) }
        lock.unlock()
        echo?(line)
    }

    /// 로그 파일 (앱이 정함). 2MB를 넘으면 .1로 넘기고 새로 쓴다. 키 입력·클립보드 내용은 원래 로그에 없다.
    public static var fileURL: URL?
    private static var fileHandle: FileHandle?

    // lock 안에서만
    private static func appendToFile(_ line: String) {
        guard let url = fileURL else { return }
        if fileHandle == nil {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
            fileHandle = try? FileHandle(forWritingTo: url)
            _ = try? fileHandle?.seekToEnd()
        }
        guard let h = fileHandle, let data = (line + "\n").data(using: .utf8) else { return }
        h.write(data)
        if let size = try? h.offset(), size > 2_000_000 {
            try? h.close()
            fileHandle = nil
            let old = url.appendingPathExtension("1")
            try? FileManager.default.removeItem(at: old)
            try? FileManager.default.moveItem(at: url, to: old)
        }
    }

    /// 최근 로그. 복사용이면 블루투스 주소 뒷자리를 가린다.
    public static func recent(maskAddresses: Bool = false) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return maskAddresses ? buffer.map(maskAddress) : buffer
    }

    /// "aa:bb:cc:dd:ee:ff" → "aa:bb:cc:**:**:**"
    public static func maskAddress(_ text: String) -> String {
        let pattern = #"([0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2})[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}[:-][0-9A-Fa-f]{2}"#
        var out = text
        // 구분자(: 또는 -)를 그대로 쓴다
        for sep in [":", "-"] {
            let p = pattern.replacingOccurrences(of: "[:-]", with: sep)
            out = out.replacingOccurrences(of: p, with: "$1\(sep)**\(sep)**\(sep)**", options: .regularExpression)
        }
        return out
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    private static func timestamp() -> String { formatter.string(from: Date()) }
}

public func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
