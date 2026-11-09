import Foundation
import Testing
@testable import InkyUpdates

struct SemanticVersionTests {
    @Test func parsing() {
        #expect(SemanticVersion("v0.2.0")?.description == "0.2.0")
        #expect(SemanticVersion("1.4")?.description == "1.4.0")
        #expect(SemanticVersion("0.3.0-beta")?.description == "0.3.0")
        #expect(SemanticVersion("abc") == nil)
    }

    @Test func numericComparison() {
        #expect(SemanticVersion("0.10.0")! > SemanticVersion("0.9.0")!)
        #expect(SemanticVersion("1.0.0")! > SemanticVersion("0.99.99")!)
        #expect(!(SemanticVersion("0.2.0")! > SemanticVersion("0.2.0")!))
    }
}

struct UpdateClientTests {
    func release(_ tag: String, assets: [String], prerelease: Bool = false) throws -> GitHubRelease {
        let json: [String: Any] = [
            "tag_name": tag, "body": "notes", "html_url": "https://github.com/x/y",
            "draft": false, "prerelease": prerelease,
            "assets": assets.map { ["name": $0, "browser_download_url": "https://example.com/\($0)"] },
        ]
        return try JSONDecoder().decode(GitHubRelease.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func newerReleaseIsOffered() throws {
        let r = try release("v0.2.0", assets: ["Inky-0.2.0.zip", "Inky-0.2.0.zip.sha256"])
        let update = try UpdateClient.update(from: r, currentVersion: SemanticVersion("0.1.0")!)
        #expect(update?.version.description == "0.2.0")
        #expect(update?.checksumURL.lastPathComponent == "Inky-0.2.0.zip.sha256")
    }

    @Test func sameOrOlderOrPrereleaseIgnored() throws {
        let current = SemanticVersion("0.2.0")!
        #expect(try UpdateClient.update(from: release("v0.2.0", assets: []), currentVersion: current) == nil)
        #expect(try UpdateClient.update(from: release("v0.1.0", assets: []), currentVersion: current) == nil)
        #expect(try UpdateClient.update(from: release("v0.3.0", assets: [], prerelease: true), currentVersion: current) == nil)
    }

    @Test func missingChecksumIsAnError() throws {
        let r = try release("v0.3.0", assets: ["Inky-0.3.0.zip"])
        #expect(throws: UpdateError.missingAssets) {
            try UpdateClient.update(from: r, currentVersion: SemanticVersion("0.2.0")!)
        }
    }
}
