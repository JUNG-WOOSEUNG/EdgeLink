import EdgeLinkCore
import Foundation
import IOBluetooth

/// 온보딩 3단계 · 새 기기 페어링: 근처 기기 찾기와 페어링.
final class DeviceDirectory: NSObject, ObservableObject {
    struct Item: Identifiable, Equatable {
        enum Kind { case phone, pad, other }
        let address: String
        var name: String
        var paired: Bool
        var kind: Kind
        var id: String { address }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var searching = false

    private var inquiry: IOBluetoothDeviceInquiry?
    private var wantSearch = false

    func start() {
        wantSearch = true
        reloadPaired()
        startInquiry()
    }

    func stop() {
        wantSearch = false
        let q = inquiry
        inquiry = nil
        q?.stop()
        DispatchQueue.main.async { _ = q }
        searching = false
    }

    private func startInquiry() {
        guard wantSearch, inquiry == nil, Snapshot.directory == nil else { return }
        let q = IOBluetoothDeviceInquiry(delegate: self)
        q?.inquiryLength = 8
        q?.updateNewDeviceNames = true
        inquiry = q
        searching = q?.start() == kIOReturnSuccess
    }

    func reloadPaired() {
        // 캡처에는 이 Mac의 실제 페어링 기기 대신 예시 기기를 쓴다
        if Snapshot.directory != nil {
            if !items.contains(Snapshot.sampleDevice) { items.append(Snapshot.sampleDevice) }
            return
        }
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        for d in paired { upsert(d) }
    }

    private func upsert(_ d: IOBluetoothDevice) {
        guard let address = d.addressString, let item = Self.item(for: d) else { return }
        if let i = items.firstIndex(where: { $0.address == address }) {
            items[i].name = item.name
            items[i].paired = item.paired
        } else {
            items.append(item)
        }
        items.sort { ($0.kind == .other ? 1 : 0, $0.name) < ($1.kind == .other ? 1 : 0, $1.name) }
    }

    /// 오디오·키보드·웨어러블처럼 아이폰이 아닌 게 확실한 기기는 뺀다.
    /// 최근 macOS는 아이폰의 기기 종류를 0으로 알려줘서 이름도 같이 본다.
    static func item(for d: IOBluetoothDevice) -> Item? {
        let cod = d.classOfDevice
        let major = (cod >> 8) & 0x1F
        let name = d.name ?? d.addressString ?? "이름 없는 기기"
        let lower = name.lowercased()
        let kind: Item.Kind
        if lower.contains("ipad") || major == 1 && ((cod >> 2) & 0x3F) == 7 {
            kind = .pad
        } else if lower.contains("iphone") || major == 2 {
            kind = .phone
        } else if [4, 5, 7].contains(major) || lower.contains("watch") || lower.contains("airpods") || lower.hasSuffix(".local") {
            return nil
        } else {
            kind = .other
        }
        return Item(address: d.addressString ?? "", name: name, paired: d.isPaired(), kind: kind)
    }
}

extension DeviceDirectory: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!) {
        if let d = device { upsert(d) }
    }

    func deviceInquiryDeviceNameUpdated(_ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!, devicesRemaining: UInt32) {
        if let d = device { upsert(d) }
    }

    func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool) {
        guard sender === inquiry else { return }
        let finished = inquiry
        DispatchQueue.main.async { _ = finished } // 콜백 안에서 바로 해제하지 않는다
        inquiry = nil
        searching = false
        guard wantSearch, !aborted else { return }
        // 화면이 열려 있는 동안 계속 찾는다
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.startInquiry() }
    }
}

/// 처음 한 번 하는 블루투스 등록. 두 기기에 같은 번호가 뜨면 아이폰에서 "페어링"을 누른다.
final class Pairer: NSObject, IOBluetoothDevicePairDelegate {
    private var pair: IOBluetoothDevicePair?
    var onCode: ((Int) -> Void)?
    var onFinish: ((IOReturn) -> Void)?

    func start(address: String) -> IOReturn {
        guard let d = IOBluetoothDevice(addressString: address) else { return kIOReturnBadArgument }
        let p = IOBluetoothDevicePair(device: d)
        p?.delegate = self
        pair = p
        HIDLog.info("페어링 시작")
        return p?.start() ?? kIOReturnError
    }

    func cancel() {
        onCode = nil
        onFinish = nil
        let p = pair
        pair = nil
        p?.delegate = nil
        p?.stop()
        DispatchQueue.main.async { _ = p }
    }

    func devicePairingUserConfirmationRequest(_ sender: Any!, numericValue: BluetoothNumericValue) {
        onCode?(Int(numericValue))
        // 번호 확인은 아이폰 쪽에서 한다
        pair?.replyUserConfirmation(true)
    }

    func devicePairingUserPasskeyNotification(_ sender: Any!, passkey: BluetoothPasskey) {
        onCode?(Int(passkey))
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        HIDLog.info("페어링 끝: \(BluetoothHID.describe(error))")
        let p = pair
        pair = nil
        DispatchQueue.main.async { _ = p }
        onFinish?(error)
    }
}
