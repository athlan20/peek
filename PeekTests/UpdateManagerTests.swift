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

    func testExtractTagNameFromReleaseURL() {
        XCTAssertEqual(
            UpdateManager.extractTagName(
                fromReleaseURL: URL(string: "https://github.com/athlan20/peek/releases/tag/v0.1.6")!
            ),
            "v0.1.6"
        )
        XCTAssertEqual(
            UpdateManager.extractTagName(
                fromReleaseURL: URL(string: "https://github.com/athlan20/peek/releases/tag/v0.2.0?foo=bar")!
            ),
            "v0.2.0"
        )
        XCTAssertNil(
            UpdateManager.extractTagName(
                fromReleaseURL: URL(string: "https://github.com/athlan20/peek/releases")!
            )
        )
    }

    func testBuildFallbackReleaseWithAndWithoutChecksums() {
        let fallback = UpdateManager.buildFallbackRelease(
            tagName: "v0.1.6",
            currentVersion: "0.1.3",
            arch: "arm64"
        )
        XCTAssertEqual(fallback?.version, "0.1.6")
        XCTAssertEqual(fallback?.tagName, "v0.1.6")
        XCTAssertEqual(fallback?.assetName, "Peek-0.1.6-arm64.zip")
        XCTAssertEqual(
            fallback?.downloadURL.absoluteString,
            "https://github.com/athlan20/peek/releases/download/v0.1.6/Peek-0.1.6-arm64.zip"
        )
        XCTAssertEqual(
            fallback?.sha256AssetURL?.absoluteString,
            "https://github.com/athlan20/peek/releases/download/v0.1.6/SHA256SUMS.txt"
        )
        XCTAssertEqual(
            fallback?.releasePageURL.absoluteString,
            "https://github.com/athlan20/peek/releases/tag/v0.1.6"
        )

        // 已是最新版时返回 nil
        XCTAssertNil(
            UpdateManager.buildFallbackRelease(tagName: "v0.1.3", currentVersion: "0.1.3", arch: "arm64")
        )

        // 结合 SHA256SUMS.txt 精确匹配架构
        let hashA = String(repeating: "a", count: 64)
        let hashB = String(repeating: "b", count: 64)
        let sums = """
        \(hashA)  Peek-0.1.6-arm64.dmg
        \(hashB)  Peek-0.1.6-x86_64.zip
        """
        let intel = UpdateManager.buildFallbackRelease(
            tagName: "v0.1.6",
            currentVersion: "0.1.3",
            arch: "x86_64",
            sha256SumsText: sums
        )
        XCTAssertEqual(intel?.assetName, "Peek-0.1.6-x86_64.zip")
        // SHA256SUMS.txt 中不含 arm64.zip 时返回 nil
        XCTAssertNil(
            UpdateManager.buildFallbackRelease(
                tagName: "v0.1.6",
                currentVersion: "0.1.3",
                arch: "arm64",
                sha256SumsText: sums
            )
        )
    }

    func testShouldAutoCheckThrottlesSuccessAndFailure() {
        let now = Date()
        XCTAssertTrue(UpdateManager.shouldAutoCheck(now: now, lastSuccess: nil, lastFailure: nil))
        // 成功后 24 小时内不检查
        XCTAssertFalse(UpdateManager.shouldAutoCheck(now: now, lastSuccess: now.addingTimeInterval(-3600), lastFailure: nil))
        XCTAssertTrue(UpdateManager.shouldAutoCheck(now: now, lastSuccess: now.addingTimeInterval(-25 * 3600), lastFailure: nil))
        // 失败后 1 小时内不检查，超过 1 小时可重试
        XCTAssertFalse(UpdateManager.shouldAutoCheck(now: now, lastSuccess: nil, lastFailure: now.addingTimeInterval(-600)))
        XCTAssertTrue(UpdateManager.shouldAutoCheck(now: now, lastSuccess: nil, lastFailure: now.addingTimeInterval(-3700)))
        XCTAssertFalse(UpdateManager.shouldAutoCheck(
            now: now,
            lastSuccess: now.addingTimeInterval(-25 * 3600),
            lastFailure: now.addingTimeInterval(-600)
        ))
    }

    func testLatestReleasePageURL() {
        XCTAssertEqual(UpdateManager.latestReleasePageURL.absoluteString, "https://github.com/athlan20/peek/releases/latest")
    }
}
