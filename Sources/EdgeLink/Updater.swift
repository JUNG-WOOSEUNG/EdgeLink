import AppKit
import Combine
import EdgeLinkCore
import Security

/// GitHub 릴리스로 업데이트한다.
/// - 확인: Info.plist의 EdgeLinkUpdateFeed(릴리스 API 주소) 한 곳만 본다. 개발용으로 EDGELINK_UPDATE_FEED로 바꿀 수 있다(file:// 가능),
///   EDGELINK_UPDATE_AUTOINSTALL이 있으면 묻지 않고 설치한다.
/// - 설치: DMG를 받아 열고, 새 앱이 지금 앱과 같은 인증서로 서명됐는지 확인한 뒤, 앱이 끝나면 바꿔 끼우고 다시 띄운다.
///   서명이 다르면 설치하지 않는다 (권한도 서명 기준이라, 같은 인증서여야 손쉬운 사용 허용이 그대로 남는다).
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(ReleaseInfo)
        case downloading(Double)
        case installing
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var lastChecked: Date?

    unowned let model: AppModel
    private var timer: Timer?
    private var waitForMac: AnyCancellable?
    private var download: URLSessionDownloadTask?
    private var progressWatch: NSKeyValueObservation?
    private static let lastCheckKey = "lastUpdateCheck"
    private static let interval: TimeInterval = 24 * 3600

    init(model: AppModel) {
        self.model = model
        let t = UserDefaults.standard.double(forKey: Self.lastCheckKey)
        lastChecked = t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var feedURL: URL? {
        let s = ProcessInfo.processInfo.environment["EDGELINK_UPDATE_FEED"]
            ?? Bundle.main.infoDictionary?["EdgeLinkUpdateFeed"] as? String
        return s.flatMap(URL.init(string:))
    }

    /// 켤 때마다 한 번 확인하고(새 버전이면 업데이트 창), 켜 둔 동안은 하루 한 번.
    func startAutomaticChecks() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
        // 블루투스 연결이 먼저 자리 잡게 몇 초 뒤에
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.model.settings.autoUpdateAllowed, self.model.settings.autoUpdateCheck else { return }
            self.check(userInitiated: false)
        }
    }

    /// 캡처용: 새 버전이 있는 상태로
    func debugSetAvailable(_ release: ReleaseInfo) {
        guard Snapshot.directory != nil else { return }
        state = .available(release)
    }

    func debugSetIdle() {
        guard Snapshot.directory != nil else { return }
        state = .idle
    }

    private func checkIfDue() {
        guard model.settings.autoUpdateAllowed, model.settings.autoUpdateCheck else { return }
        if let last = lastChecked, Date().timeIntervalSince(last) < Self.interval { return }
        check(userInitiated: false)
    }

    /// userInitiated: 설정의 "지금 확인". 새 버전이 없어도 결과를 보여준다.
    func check(userInitiated: Bool) {
        switch state {
        case .checking, .downloading, .installing: return
        default: break
        }
        guard let url = Self.feedURL else {
            if userInitiated { state = .failed("업데이트 주소가 정해지지 않은 개발판이에요") }
            return
        }
        state = .checking
        fetch(url) { [weak self] result in
            guard let self else { return }
            self.lastChecked = Date()
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
            switch result {
            case let .failure(message):
                HIDLog.warn("업데이트 확인 실패: \(message)")
                self.state = userInitiated ? .failed(message) : .idle
            case let .success(data):
                guard let release = UpdateFeed.parse(data) else {
                    self.state = userInitiated ? .failed("릴리스 정보를 읽지 못했어요") : .idle
                    return
                }
                guard UpdateFeed.isNewer(release.version, than: Self.currentVersion) else {
                    HIDLog.info("업데이트 확인: 최신 (\(Self.currentVersion), 릴리스 \(release.version))")
                    self.state = .upToDate
                    return
                }
                HIDLog.info("새 버전 \(release.version) 있음")
                self.state = .available(release)
                self.offer(release, now: userInitiated)
            }
        }
    }

    /// 확인 창은 Mac 조작 중일 때만 띄운다. 아이폰 조작 중이면 돌아올 때까지 기다린다.
    private func offer(_ release: ReleaseInfo, now: Bool) {
        // 개발용: 묻지 않고 바로 설치 (업데이트 과정 시험)
        if ProcessInfo.processInfo.environment["EDGELINK_UPDATE_AUTOINSTALL"] != nil { return install() }
        if now || model.controlMode == .mac {
            model.dialogs.present(.update(version: release.version))
            return
        }
        waitForMac = model.$controlMode.filter { $0 == .mac }.first().sink { [weak self] _ in
            DispatchQueue.main.async { self?.model.dialogs.present(.update(version: release.version)) }
        }
    }

    private enum Fetch { case success(Data), failure(String) }

    private func fetch(_ url: URL, done: @escaping (Fetch) -> Void) {
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("EdgeLink/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            let result: Fetch
            if let error {
                result = .failure("인터넷 연결을 확인해 주세요 (\(error.localizedDescription))")
            } else if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                // 비공개 저장소는 로그인 없이 404를 준다
                result = .failure(http.statusCode == 404 ? "릴리스를 찾지 못했어요 (404)" : "서버 응답 \(http.statusCode)")
            } else {
                result = .success(data ?? Data())
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }

    // MARK: 설치

    func install() {
        guard case let .available(release) = state else { return }
        state = .downloading(0)
        HIDLog.info("업데이트 내려받기 \(release.version)")
        let task = URLSession.shared.downloadTask(with: release.dmgURL) { [weak self] file, response, error in
            // 임시 파일은 이 클로저가 끝나면 지워지므로 바로 옮긴다
            var moved: URL?
            if let file, (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("EdgeLink-update-\(UUID().uuidString).dmg")
                if (try? FileManager.default.moveItem(at: file, to: dest)) != nil { moved = dest }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.progressWatch = nil
                guard let dmg = moved else {
                    return self.fail("내려받지 못했어요\(error.map { " (\($0.localizedDescription))" } ?? "")", release)
                }
                self.state = .installing
                DispatchQueue.global(qos: .userInitiated).async {
                    let result = Self.prepare(dmg: dmg, version: release.version)
                    DispatchQueue.main.async {
                        switch result {
                        case let .failure(message): self.fail(message, release)
                        case let .success(staged): self.relaunch(into: staged)
                        }
                    }
                }
            }
        }
        progressWatch = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async {
                if case .downloading = self?.state { self?.state = .downloading(p.fractionCompleted) }
            }
        }
        download = task
        task.resume()
    }

    func cancelDownload() {
        download?.cancel()
    }

    private func fail(_ message: String, _ release: ReleaseInfo) {
        HIDLog.error("업데이트 실패: \(message)")
        state = .failed(message)
    }

    private enum Prepared { case success(URL), failure(String) }

    /// DMG를 열어 앱을 임시 폴더로 꺼내고 서명을 확인한다. 백그라운드에서.
    private static func prepare(dmg: URL, version: String) -> Prepared {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("EdgeLink-update-\(UUID().uuidString)")
        let mount = work.appendingPathComponent("mnt")
        let staged = work.appendingPathComponent("EdgeLink.app")
        defer { try? fm.removeItem(at: dmg) }
        do { try fm.createDirectory(at: mount, withIntermediateDirectories: true) } catch {
            return .failure("임시 폴더를 만들지 못했어요")
        }
        guard run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path]) else {
            return .failure("DMG를 열지 못했어요")
        }
        defer { _ = run("/usr/bin/hdiutil", ["detach", "-force", mount.path]) }
        let source = mount.appendingPathComponent("EdgeLink.app")
        guard fm.fileExists(atPath: source.path) else { return .failure("DMG 안에 EdgeLink.app이 없어요") }
        guard run("/usr/bin/ditto", [source.path, staged.path]) else { return .failure("새 앱을 복사하지 못했어요") }

        let info = NSDictionary(contentsOf: staged.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            return .failure("다른 앱이 들어 있어요")
        }
        guard let newVersion = info?["CFBundleShortVersionString"] as? String,
              UpdateFeed.isNewer(newVersion, than: currentVersion) else {
            return .failure("DMG 속 앱이 지금 버전보다 새것이 아니에요")
        }
        if let problem = signatureProblem(staged) { return .failure(problem) }
        return .success(staged)
    }

    /// 새 앱이 지금 앱의 지정 요구사항(같은 인증서·같은 번들 ID)을 만족하는지. 문제가 없으면 nil.
    private static func signatureProblem(_ app: URL) -> String? {
        var me: SecCode?
        var mine: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me,
              SecCodeCopyStaticCode(me, [], &mine) == errSecSuccess, let mine,
              SecCodeCopyDesignatedRequirement(mine, [], &requirement) == errSecSuccess, let requirement else {
            return "지금 앱의 서명을 읽지 못했어요"
        }
        var text: CFString?
        SecRequirementCopyString(requirement, [], &text)
        // 임시 서명(cdhash 요구사항)은 빌드마다 달라서 비교할 수 없다
        if let text, (text as String).hasPrefix("cdhash") {
            return "지금 앱이 임시 서명이라 자동 설치를 할 수 없어요. 릴리스 페이지에서 받아 주세요"
        }
        var new: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &new) == errSecSuccess, let new else {
            return "새 앱의 서명을 읽지 못했어요"
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        let status = SecStaticCodeCheckValidity(new, flags, requirement)
        guard status == errSecSuccess else {
            HIDLog.error("새 앱 서명 확인 실패 \(status)")
            return "새 앱의 서명이 지금 앱과 달라서 설치하지 않았어요"
        }
        return nil
    }

    @discardableResult
    private static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// 앱이 끝나면 바꿔 끼우고 다시 띄우는 작은 셸을 남기고 종료한다.
    /// 바꾸다 실패하면 예전 앱을 되돌려 놓고 그것을 띄운다.
    private func relaunch(into staged: URL) {
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            state = .failed("\(parent.path)에 쓸 수 없어요. 릴리스 페이지에서 받아 옮겨 주세요")
            return
        }
        let backup = staged.deletingLastPathComponent().appendingPathComponent("EdgeLink-old.app")
        let script = """
        while kill -0 "$0" 2>/dev/null; do sleep 0.2; done
        if mv "$1" "$3" && /usr/bin/ditto "$2" "$1"; then
          /usr/bin/xattr -dr com.apple.quarantine "$1" 2>/dev/null
          rm -rf "$3"
        else
          rm -rf "$1"; mv "$3" "$1"
        fi
        /usr/bin/open "$1"
        rm -rf "$(dirname "$2")"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "\(ProcessInfo.processInfo.processIdentifier)", target.path, staged.path, backup.path]
        do { try p.run() } catch {
            state = .failed("설치를 시작하지 못했어요")
            return
        }
        HIDLog.info("업데이트 설치: 앱을 끝내고 바꿔 끼워요")
        model.router.returnToMac(.disconnected)
        NSApp.terminate(nil)
    }
}
