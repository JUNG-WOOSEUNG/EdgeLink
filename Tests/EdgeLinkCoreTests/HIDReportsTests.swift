@testable import EdgeLinkCore
import Foundation
import Testing

@Suite("HID 리포트")
struct HIDReportsTests {
    @Test func keyboardReportLayout() {
        let r = KeyboardReport(modifiers: 0x02, keys: [0x04, 0x05])
        #expect(r.bytes == [0xA1, 0x01, 0x02, 0x00, 0x04, 0x05, 0x00, 0x00, 0x00, 0x00])
        #expect(KeyboardReport().bytes.count == 10)
    }

    @Test func keyboardReportKeepsSixKeys() {
        let r = KeyboardReport(keys: [1, 2, 3, 4, 5, 6, 7])
        #expect(r.keys == [1, 2, 3, 4, 5, 6])
    }

    @Test func mouseReportLayout() {
        let r = MouseReport(buttons: 0x01, dx: -1, dy: 127, wheel: -127, pan: 3)
        #expect(r.bytes == [0xA1, 0x02, 0x01, 0xFF, 0x7F, 0x81, 0x03])
    }

    @Test func mouseMotionSplitsOver127() {
        let parts = MouseReport.split(dx: 300, dy: -130)
        #expect(parts.map(\.dx) == [127, 127, 46])
        #expect(parts.map(\.dy) == [-127, -3, 0])
        #expect(parts.reduce(0) { $0 + Int($1.dx) } == 300)
        #expect(MouseReport.split(dx: 0, dy: 0).count == 1)
    }

    @Test func mouseSplitKeepsButtons() {
        #expect(MouseReport.split(dx: 200, dy: 0, buttons: 0x01).allSatisfy { $0.buttons == 0x01 })
    }

    @Test func consumerReportLittleEndian() {
        #expect(ConsumerReport(usage: ConsumerReport.volumeUp).bytes == [0xA1, 0x03, 0xE9, 0x00])
    }
}

@Suite("HID 디스크립터")
struct HIDDescriptorTests {
    @Test func reportIDsPresent() {
        let d = HIDDescriptor.bytes
        for id: UInt8 in [1, 2, 3] {
            #expect(zip(d, d.dropFirst()).contains { $0 == 0x85 && $1 == id })
        }
    }

    @Test func collectionsBalanced() {
        // 짧은 항목을 순서대로 읽어서 Collection(0xA1)과 End Collection(0xC0) 짝을 센다
        var depth = 0, i = 0
        let d = HIDDescriptor.bytes
        while i < d.count {
            let prefix = d[i]
            let size = [0, 1, 2, 4][Int(prefix & 0x03)]
            if prefix & 0xFC == 0xA0 { depth += 1 }
            if prefix == 0xC0 { depth -= 1 }
            #expect(depth >= 0)
            i += 1 + size
        }
        #expect(i == d.count)
        #expect(depth == 0)
    }

    @Test func sdpRecordHasHIDDescriptor() throws {
        let dict = HIDServiceRecord.dictionary()
        let list = try #require(dict["0206 - HIDDescriptorList"] as? [[[String: Any]]])
        let value = try #require(list.first?.last?["DataElementValue"] as? Data)
        #expect([UInt8](value) == HIDDescriptor.bytes)
        #expect(dict.keys.contains("0004 - ProtocolDescriptorList"))
        #expect(dict.keys.contains("000D - AdditionalProtocolDescriptorLists"))
    }
}

@Suite("HIDP 제어 메시지")
struct HIDPTests {
    @Test func setProtocolAndIdleSucceed() {
        #expect(HIDP.handleControl([0x71]) == .reply([0x00]))
        #expect(HIDP.handleControl([0x90, 0x00]) == .reply([0x00]))
    }

    @Test func getProtocolIsReport() {
        #expect(HIDP.handleControl([0x60]) == .reply([0xA0, 0x01]))
    }

    @Test func getReportReturnsEmptyInput() {
        #expect(HIDP.handleControl([0x41, 0x01]) == .reply(KeyboardReport().bytes))
        #expect(HIDP.handleControl([0x41, 0x02]) == .reply(MouseReport().bytes))
        #expect(HIDP.handleControl([0x41, 0x09]) == .reply([HIDP.Handshake.invalidReportID.rawValue]))
    }

    @Test func setReportPassesLEDs() {
        var received: [UInt8] = []
        let r = HIDP.handleControl([0x52, 0x01, 0x02]) { received = $0 }
        #expect(r == .reply([0x00]))
        #expect(KeyboardLEDs(outputReport: received) == .capsLock)
    }

    @Test func virtualCableUnplug() {
        #expect(HIDP.handleControl([0x15]) == .virtualCableUnplug)
        #expect(HIDP.handleControl([0x13]) == .ignore)
    }

    @Test func unknownRequestUnsupported() {
        #expect(HIDP.handleControl([0x20]) == .reply([HIDP.Handshake.unsupportedRequest.rawValue]))
        #expect(HIDP.handleControl([]) == .ignore)
    }
}

@Suite("키 매핑")
struct KeyMappingTests {
    @Test func lettersAndControls() {
        #expect(HIDUsage.fromMacKeyCode(0x00) == 0x04) // A
        #expect(HIDUsage.fromMacKeyCode(0x06) == 0x1D) // Z
        #expect(HIDUsage.fromMacKeyCode(0x24) == 0x28) // Return
        #expect(HIDUsage.fromMacKeyCode(0x31) == 0x2C) // Space
        #expect(HIDUsage.fromMacKeyCode(0x7E) == 0x52) // ↑
        #expect(HIDUsage.fromMacKeyCode(0x7A) == 0x3A) // F1
    }

    @Test func rightModifiersMapLeft() {
        #expect(HIDUsage.fromMacKeyCode(0x36) == HIDUsage.leftGUI)
        #expect(HIDUsage.fromMacKeyCode(0x3C) == HIDUsage.leftShift)
        #expect(HIDUsage.fromMacKeyCode(0x3D) == HIDUsage.leftAlt)
        #expect(HIDUsage.fromMacKeyCode(0x3E) == HIDUsage.leftControl)
    }

    @Test func fnIsNotSent() {
        #expect(HIDUsage.fromMacKeyCode(0x3F) == nil)
    }

    @Test func jisKeys() {
        #expect(HIDUsage.fromMacKeyCode(0x66) == 0x91) // 英数
        #expect(HIDUsage.fromMacKeyCode(0x68) == 0x90) // かな
    }

    @Test func noDuplicateTargetsExceptModifiers() {
        let values = HIDUsage.macKeyCodeTable.values.filter { HIDUsage.modifierBit($0) == nil }
        #expect(Set(values).count == values.count)
    }

    @Test func asciiTyping() {
        #expect(HIDUsage.fromASCII("h")! == (0x0B, false))
        #expect(HIDUsage.fromASCII("H")! == (0x0B, true))
        #expect(HIDUsage.fromASCII("0")! == (0x27, false))
        #expect(HIDUsage.fromASCII("@")! == (0x1F, true))
        #expect(HIDUsage.fromASCII("?")! == (0x38, true))
        #expect(HIDUsage.fromASCII("한") == nil)
        #expect(HIDUsage.fromASCII("é") == nil)
    }

    @Test func everyPrintableASCIIMaps() {
        for a in UInt8(0x20)...UInt8(0x7E) {
            #expect(HIDUsage.fromASCII(Character(Unicode.Scalar(a))) != nil, "\(a)")
        }
    }

    @Test func typingReportsPressThenRelease() {
        let r = HIDUsage.typingReports(for: "A")!
        #expect(r == [KeyboardReport(modifiers: 0x02, keys: [0x04]), KeyboardReport()])
    }
}

@Suite("키 상태")
struct KeyboardStateTests {
    @Test func pressAndRelease() {
        var s = KeyboardState()
        #expect(s.press(HIDUsage.leftGUI)?.modifiers == 0x08)
        #expect(s.press(0x04) == KeyboardReport(modifiers: 0x08, keys: [0x04]))
        #expect(s.press(0x04) == nil) // 반복은 보내지 않음
        #expect(s.release(0x04) == KeyboardReport(modifiers: 0x08))
        #expect(s.release(0x05) == nil)
        #expect(s.releaseAll() == KeyboardReport())
    }

    @Test func rolloverLimit() {
        var s = KeyboardState()
        for k: UInt8 in 4...9 { _ = s.press(k) }
        #expect(s.press(10) == nil)
        #expect(s.pressed.count == 6)
    }
}

@Suite("기타")
struct MiscTests {
    @Test func reconnectBackoff() {
        var p = ReconnectPolicy()
        #expect([p.nextDelay(), p.nextDelay(), p.nextDelay(), p.nextDelay()] == [15, 60, 300, 300])
        p.reset()
        #expect(p.nextDelay() == 15)
    }

    @Test func addressMasking() {
        #expect(HIDLog.maskAddress("기기 a4-83-e7-12-34-56 연결") == "기기 a4-83-e7:**:**:** 연결")
        #expect(HIDLog.maskAddress("A4:83:E7:12:34:56") == "A4:83:E7:**:**:**")
    }
}

@Suite("리뷰 반영")
struct ReviewFixTests {
    @Test func setReportOnlyOutputTypeUpdatesLEDs() {
        var called = false
        #expect(HIDP.handleControl([0x51, 0x01, 0x02]) { _ in called = true } == .reply([0x00]))
        #expect(!called)
        #expect(HIDP.handleControl([0x53, 0x01, 0x02]) { _ in called = true } == .reply([0x00]))
        #expect(!called)
    }

    @Test func getOutputReportReturnsLEDs() {
        #expect(HIDP.handleControl([0x42, 0x01]) == .reply([0xA2, 0x01, 0x00]))
        #expect(HIDP.handleControl([0x43, 0x01]) == .reply([HIDP.Handshake.invalidParameter.rawValue]))
    }

    @Test func leftShiftHeldWhileRightShiftReleased() {
        var s = KeyboardState()
        _ = s.press(HIDUsage.leftShift)      // 왼쪽 ⇧
        #expect(s.press(HIDUsage.leftShift) == nil) // 오른쪽 ⇧ (왼쪽 비트로 옴)
        #expect(s.release(HIDUsage.leftShift) == nil)
        #expect(s.modifiers == 0x02)
        #expect(s.release(HIDUsage.leftShift)?.modifiers == 0)
    }
}
