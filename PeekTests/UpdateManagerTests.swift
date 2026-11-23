import XCTest

@testable import Peek

final class UpdateManagerTests: XCTestCase {
    func testSemVerParsingAndComparison() {
        XCTAssertEqual(SemVer("v0.2.0"), SemVer("0.2.0"))
        XCTAssertEqual(SemVer("1.2"), SemVer("1.2.0"))
        XCTAssertTrue(SemVer("v0.2.0")! > SemVer("0.1.0")!)
        XCTAssertTrue(SemVer("0.10.0")! > SemVer("0.2.9")!)
        XCTAssertFalse(SemVer("0.1.0")! > SemVer("v0.1.0")!)
        XCTAssertNil(SemVer("invalid"))
    }

    func testEvaluateReleaseMatchesArchitectureAndSHA256() {
        let payload = UpdateManager.GitHubReleasePayload(
            tag_name: "v0.2.0",
            html_url: "https://github.com/athlan20/peek/releases/tag/v0.2.0",
            body: "Bug fixes and thermal gauges",
            draft: false,
            prerelease: false,
            assets: [
                .init(name: "Peek-0.2.0-arm64.dmg", browser_download_url: "https://example.com/arm64.dmg"),
                .init(name: "Peek-0.2.0-arm64.zip", browser_download_url: "https://example.com/arm64.zip"),
                .init(name: "Peek-0.2.0-x86_64.zip", browser_download_url: "https://example.com/x86_64.zip"),
                .init(name: "SHA256SUMS.txt", browser_download_url: "https://example.com/SHA256SUMS.txt"),
            ]
        )

        let arm = UpdateManager.evaluateRelease(payload, currentVersion: "0.1.0", arch: "arm64")
        XCTAssertEqual(arm?.version, "0.2.0")
        XCTAssertEqual(arm?.assetName, "Peek-0.2.0-arm64.zip")
        XCTAssertEqual(arm?.downloadURL.absoluteString, "https://example.com/arm64.zip")
        XCTAssertEqual(arm?.sha256AssetURL?.absoluteString, "https://example.com/SHA256SUMS.txt")

        let intel = UpdateManager.evaluateRelease(payload, currentVersion: "0.1.0", arch: "x86_64")
        XCTAssertEqual(intel?.assetName, "Peek-0.2.0-x86_64.zip")

        // 已是最新版时返回 nil
        XCTAssertNil(UpdateManager.evaluateRelease(payload, currentVersion: "0.2.0", arch: "arm64"))
        XCTAssertNil(UpdateManager.evaluateRelease(payload, currentVersion: "0.3.0", arch: "arm64"))
    }

    func testParseSHA256Sums() {
        let validHash = String(repeating: "a", count: 64)
        let otherHash = String(repeating: "b", count: 64)
        let text = """
        \(otherHash)  Peek-0.2.0-x86_64.zip
        \(validHash)  dist/Peek-0.2.0-arm64.zip
        """
        XCTAssertEqual(
            UpdateManager.parseSHA256(from: text, assetName: "Peek-0.2.0-arm64.zip"),
            validHash
        )
        XCTAssertNil(UpdateManager.parseSHA256(from: text, assetName: "Peek-0.2.0-arm64.dmg"))
    }

    func testParseLeafCertHash() {
        let output = """
        Executable=/Applications/Peek.app/Contents/MacOS/Peek
        designated => identifier "cc.yuntianyou.peek" and certificate leaf = H"73cef962bf164989daa9a3b606d13c32c98f376b"
        """
        XCTAssertEqual(
            UpdateManager.parseLeafCertHash(from: output),
            "73cef962bf164989daa9a3b606d13c32c98f376b"
        )
        XCTAssertNil(UpdateManager.parseLeafCertHash(from: "designated => cdhash H\"1234\""))
    }
}
