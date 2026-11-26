import Foundation
import Testing
@testable import EdgeLinkCore

@Suite struct UpdateFeedTests {
    private func json(_ tag: String = "v0.3.0", draft: Bool = false, pre: Bool = false,
                      assets: [String] = ["EdgeLink.dmg"]) -> Data {
        let list = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/o/r/releases/download/v1/\#($0)"}"# }
        return Data(#"""
        {"tag_name":"\#(tag)","draft":\#(draft),"prerelease":\#(pre),"body":"고친 것","html_url":"https://github.com/o/r",
         "assets":[\#(list.joined(separator: ","))]}
        """#.utf8)
    }

    @Test func parsesRelease() throws {
        let r = try #require(UpdateFeed.parse(json()))
        #expect(r.version == "0.3.0")
        #expect(r.notes == "고친 것")
        #expect(r.dmgURL.absoluteString == "https://github.com/o/r/releases/download/v1/EdgeLink.dmg")
        #expect(r.pageURL?.absoluteString == "https://github.com/o/r")
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

    @Test func rejectsUntrustedDownloadURL() {
        func feed(_ link: String) -> Data {
            Data(#"{"tag_name":"v1.0.0","assets":[{"name":"EdgeLink.dmg","browser_download_url":"\#(link)"}]}"#.utf8)
        }
        #expect(UpdateFeed.parse(feed("http://github.com/o/r/EdgeLink.dmg")) == nil)
        #expect(UpdateFeed.parse(feed("https://example.com/EdgeLink.dmg")) == nil)
        #expect(UpdateFeed.parse(feed("https://github.com.evil.example/EdgeLink.dmg")) == nil)
        #expect(UpdateFeed.parse(feed("https://github.com@evil.example/EdgeLink.dmg")) == nil)
        #expect(UpdateFeed.parse(feed("https://GitHub.com/o/r/EdgeLink.dmg")) != nil)
    }

    @Test func comparesVersions() {
        #expect(UpdateFeed.isNewer("0.3.0", than: "0.2.0"))
        #expect(UpdateFeed.isNewer("v0.10.0", than: "0.9.9"))
        #expect(UpdateFeed.isNewer("1.0", than: "0.99.1"))
        #expect(!UpdateFeed.isNewer("0.2", than: "0.2.0"))
        #expect(!UpdateFeed.isNewer("0.2.0", than: "0.2.1"))
        #expect(!UpdateFeed.isNewer("0.3.0-beta", than: "0.3.0"))
    }

    @Test func releaseNotesLines() {
        let l = ReleaseNotes.lines("## 고친 것\n- 하나\n* 둘\n\n그냥 줄\n")
        #expect(l == [.heading("고친 것"), .bullet("하나"), .bullet("둘"), .text("그냥 줄")])
    }
}
