import Foundation

/// GitHub 릴리스 하나에서 업데이트에 필요한 것만 뽑은 것.
/// 주소: https://api.github.com/repos/<소유자>/<저장소>/releases/latest
public struct ReleaseInfo: Equatable {
    /// 태그에서 앞의 v를 뗀 버전 (예: "0.3.0")
    public let version: String
    /// 릴리스 설명 (마크다운 그대로)
    public let notes: String
    /// 내려받을 DMG
    public let dmgURL: URL
    /// 브라우저로 열 릴리스 페이지
    public let pageURL: URL?

    public init(version: String, notes: String, dmgURL: URL, pageURL: URL?) {
        self.version = version
        self.notes = notes
        self.dmgURL = dmgURL
        self.pageURL = pageURL
    }
}

public enum UpdateFeed {
    /// 릴리스에 올리는 DMG 파일 이름
    public static let dmgName = "EdgeLink.dmg"

    /// GitHub API의 릴리스 JSON을 읽는다. 초안·사전 릴리스이거나 DMG가 없으면 nil.
    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = obj["tag_name"] as? String else { return nil }
        if obj["draft"] as? Bool == true || obj["prerelease"] as? Bool == true { return nil }
        let assets = obj["assets"] as? [[String: Any]] ?? []
        // 이름이 정확히 같은 것을 먼저, 없으면 .dmg 아무거나
        let asset = assets.first { $0["name"] as? String == dmgName }
            ?? assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }
        guard let link = asset?["browser_download_url"] as? String, let url = URL(string: link) else { return nil }
        let page = (obj["html_url"] as? String).flatMap(URL.init(string:))
        return ReleaseInfo(version: normalize(tag), notes: obj["body"] as? String ?? "", dmgURL: url, pageURL: page)
    }

    /// "v0.3.0" → "0.3.0"
    public static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespaces)
        if s.first == "v" || s.first == "V" { s.removeFirst() }
        return s
    }

    /// a가 b보다 새 버전인지. 숫자 마디끼리 비교하고, 모자란 마디는 0으로 본다 (1.2 == 1.2.0).
    /// 숫자가 아닌 꼬리(-beta 등)는 무시한다.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    private static func parts(_ v: String) -> [Int] {
        normalize(v).split(separator: ".").map { piece in
            Int(piece.prefix { $0.isNumber }) ?? 0
        }
    }
}
