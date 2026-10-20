import Foundation
import Testing
@testable import EdgeLinkCore

@Suite struct UpdateFeedTests {
    private func json(_ tag: String = "v0.3.0", draft: Bool = false, pre: Bool = false,
                      assets: [String] = ["EdgeLink.dmg"]) -> Data {
        let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://example.com/\#($0)"}"# }
        return Data(#"""
        {"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(pre),"body":"고친 것","html_url":"https://example.com/r",
         "assets":[\#(list.joined(separator: ","))]}
        """#.utf8)
    }

    @Test func parsesRelease() throws {
        let r = try #require(UpdateFeed.parse(json()))
        #expect(r.version == "0.3.0")
        #expect(r.notes == "고친 것")
        #expect(r.dmgURL.absoluteString == "https://example.com/EdgeLink.dmg")
        #expect(r.pageURL?.absoluteString == "https://example.com/r")
    }

    @Test func prefersExactDMGName() throws {
        let r = try #require(UpdateFeed.parse(json(assets: ["Other.dmg", "EdgeLink.dmg"])))
        #expect(r.dmgURL.lastPathComponent == "EdgeLink.dmg")
    }

    @Test func skipsDraftPrereleaseAndMissingDMG() {
        #expect(UpdateFeed.parse(json(draft: true)) == nil)
        #expect(UpdateFeed.parse(json(pre: true)) == nil)
        #expect(UpdateFeed.parse(json(assets: ["notes.txt"])) == nil)
        #expect(UpdateFeed.parse(Data("not json".utf8)) == nil)
    }

    @Test func comparesVersions() {
        #expect(UpdateFeed.isNewer("0.3.0", than: "0.2.0"))
        #expect(UpdateFeed.isNewer("v0.10.0", than: "0.9.9"))
        #expect(UpdateFeed.isNewer("1.0", than: "0.99.1"))
        #expect(!UpdateFeed.isNewer("0.2", than: "0.2.0"))
        #expect(!UpdateFeed.isNewer("0.2.0", than: "0.2.1"))
        #expect(!UpdateFeed.isNewer("0.3.0-beta", than: "0.3.0"))
    }
}
