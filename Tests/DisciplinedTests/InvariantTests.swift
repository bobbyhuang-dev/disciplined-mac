import CryptoKit
import Foundation
import Testing

/// The "Invariants that span files" in CLAUDE.md. Breaking any of them fails silently at runtime.
struct InvariantTests {
    @Test func domainPatternMatchesScriptAndExtension() throws {
        let script = try Repo.capture(#"^DOMAIN_RE='(.+)'$"#, in: "Resources/apply-blocklist.sh")
        let extensionPattern = try Repo.capture(#"^const DOMAIN_RE = /(.+)/;$"#, in: "Extension/background.js")
        #expect(script == Domain.pattern)
        #expect(extensionPattern == Domain.pattern)
    }

    /// Native messaging only lets in the origin in the host manifest, which `extensionID` fills in.
    @Test func chromeExtensionIDMatchesManifestKey() throws {
        let key = try #require(Repo.json("Extension/manifest.json")["key"] as? String)
        let der = try #require(Data(base64Encoded: key))
        // Chrome's ID: the first 128 bits of the key's SHA-256, one letter a–p per hex digit.
        let id = SHA256.hash(data: der).prefix(16)
            .flatMap { [$0 >> 4, $0 & 0xF] }
            .map { String(UnicodeScalar(UInt8(ascii: "a") + $0)) }
            .joined()
        #expect(id == BrowserExtension.extensionID)
    }

    @Test func firefoxExtensionIDMatchesManifestAndScript() throws {
        let manifest = try Repo.json("FirefoxExtension/manifest.json")
        let gecko = (manifest["browser_specific_settings"] as? [String: Any])?["gecko"] as? [String: Any]
        let script = try Repo.capture(#"^EXTENSION_ID="(.+)"$"#, in: "Resources/apply-blocklist.sh")
        #expect(gecko?["id"] as? String == BrowserExtension.firefoxExtensionID)
        #expect(script == BrowserExtension.firefoxExtensionID)
    }

    @Test func minimumGeckoMatchesScript() throws {
        let manifest = try Repo.json("FirefoxExtension/manifest.json")
        let gecko = (manifest["browser_specific_settings"] as? [String: Any])?["gecko"] as? [String: Any]
        let minVersion = try #require(gecko?["strict_min_version"] as? String)
        let script = try Repo.capture(#"^MIN_EXTENSION_GECKO=(\d+)$"#, in: "Resources/apply-blocklist.sh")
        #expect(minVersion.split(separator: ".").first.map(String.init) == script)
    }

    /// The script finds ~/Applications by stripping this suffix from the blocklist path, and the .xpi
    /// it force-installs is the one next to the blocklist.
    @Test func scriptDerivesPathsFromBlocklistLocation() throws {
        let suffix = try #require(try Repo.capture(#"user_home="\$\{LIST%(.+)\}""#, in: "Resources/apply-blocklist.sh"))
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(BlockerHelper.blocklistURL.path == (home as NSString).appendingPathComponent(suffix))
        #expect(BrowserExtension.xpiURL == BlockerHelper.blocklistURL.deletingLastPathComponent().appendingPathComponent("Disciplined.xpi"))
    }
}
