import Foundation
import Testing

/// Runs apply-blocklist.sh against a fake system in a temporary folder. The script normally runs as
/// root on every blocklist change, so this is the only place its output gets checked before it
/// rewrites the real /etc/hosts and browser policies.
@Suite(.serialized)
struct HelperScriptTests {
    @Test func blocksEachDomainAndKeepsTheRestOfHosts() throws {
        let system = try FakeSystem()
        try system.writeHosts("""
        127.0.0.1 localhost
        \(BlockerHelper.beginMark)
        0.0.0.0 old.com
        \(BlockerHelper.endMark)
        ::1 localhost

        """)
        try system.run(blocklist: "youtube.com\nreddit.com\n")

        let hosts = try system.hosts()
        let domains = ["youtube.com", "reddit.com"]
        // The app shows "Applying…" until it reads back exactly these hosts.
        #expect(BlockerHelper.appliedHosts(in: hosts) == Set(domains.flatMap(Domain.hosts(for:))))
        for host in domains.flatMap(Domain.hosts(for:)) {
            #expect(hosts.contains("\n:: \(host)\n"), "IPv6 isn't blocked for \(host)")
        }
        #expect(hosts.removingSection() == "127.0.0.1 localhost\n::1 localhost\n")

        try system.run(blocklist: "youtube.com\nreddit.com\n")
        #expect(try system.hosts() == hosts)
    }

    /// The blocklist is user-writable and the script runs as root.
    @Test func ignoresLinesThatArentDomains() throws {
        let system = try FakeSystem()
        try system.makeGeckoApp("Firefox", bundleID: "org.mozilla.firefox", milestone: 140, requiresSigning: true)
        let pwned = system.root.appendingPathComponent("pwned").path
        try system.run(blocklist: """
        valid.com
        ok.com\r
        evil.com 127.0.0.1
        0.0.0.0 bank.com
        UPPER.com
        x.com</string><string>*://*/*
        $(touch \(pwned)).com
        `touch \(pwned)`.com
        -lead.com
        nodot
        a..b.com

        """)

        let hosts = try system.hosts()
        #expect(BlockerHelper.appliedHosts(in: hosts) == Set(["ok.com", "valid.com"].flatMap(Domain.hosts(for:))))
        #expect(hosts.split(separator: "\n").count == 1 + 2 + 2 * 3 * 2, "unexpected lines in hosts:\n\(hosts)")
        #expect(!FileManager.default.fileExists(atPath: pwned))
        #expect(try system.websiteFilter("org.mozilla.firefox") == ["*://*.ok.com/*", "*://*.valid.com/*"])
    }

    @Test func turningOffRestoresHosts() throws {
        let system = try FakeSystem()
        try system.makeGeckoApp("Firefox", bundleID: "org.mozilla.firefox", milestone: 140, requiresSigning: true)
        let original = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n"
        try system.writeHosts(original)
        try system.run(blocklist: "youtube.com\n")
        try system.run(blocklist: "")

        #expect(try system.hosts() == original)
        // Still written: the app compares its date with the browser's launch to ask for a restart.
        #expect(try system.websiteFilter("org.mozilla.firefox") == [])
    }

    @Test func forceInstallsExtensionOnlyWhereFirefoxAllowsIt() throws {
        let system = try FakeSystem()
        let zen = try system.makeGeckoApp("Zen", bundleID: "app.zen-browser.zen", milestone: 140, requiresSigning: false)
        try system.makeGeckoApp("Firefox", bundleID: "org.mozilla.firefox", milestone: 140, requiresSigning: true)
        try system.makeGeckoApp("Old Wolf", bundleID: "io.example.oldwolf", milestone: 115, requiresSigning: false)
        try system.run(blocklist: "youtube.com\n")

        let browsers = BrowserExtension.geckoBrowsers(in: try system.browsersTSV())
        #expect(browsers.map(\.bundleID) == ["app.zen-browser.zen", "io.example.oldwolf", "org.mozilla.firefox"])
        #expect(browsers.map(\.mode) == [.extension, .filter, .filter])
        #expect(browsers.map(\.profileFolder) == ["Zen Profiles", "Old Wolf Profiles", "Firefox Profiles"])
        #expect(browsers.first?.appURL.standardizedFileURL == zen.standardizedFileURL)
        #expect(browsers.first?.name == "Zen")

        let policy = try system.policy("app.zen-browser.zen")
        let settings = (policy["ExtensionSettings"] as? [String: Any])?[BrowserExtension.firefoxExtensionID] as? [String: Any]
        #expect(settings?["installation_mode"] as? String == "force_installed")
        let installURL = try #require((settings?["install_url"] as? String).flatMap { URL(string: $0) })
        #expect(installURL.path == system.xpi.path)
        let signing = (policy["Preferences"] as? [String: Any])?["xpinstall.signatures.required"] as? [String: Any]
        #expect(signing?["Value"] as? Bool == false)
        #expect(signing?["Status"] as? String == "locked")
    }

    @Test func removesPolicyOfUninstalledBrowser() throws {
        let system = try FakeSystem()
        let app = try system.makeGeckoApp("Firefox", bundleID: "org.mozilla.firefox", milestone: 140, requiresSigning: true)
        try system.run(blocklist: "youtube.com\n")
        #expect(FileManager.default.fileExists(atPath: system.policyURL("org.mozilla.firefox").path))

        try FileManager.default.removeItem(at: app)
        try system.run(blocklist: "youtube.com\n")
        #expect(!FileManager.default.fileExists(atPath: system.policyURL("org.mozilla.firefox").path))
        #expect(try system.browsersTSV().isEmpty)
    }
}

/// A temporary folder standing in for the paths the script touches, with a copy of the script pointed at it.
private final class FakeSystem {
    let root: URL
    let hostsURL: URL
    let managedPrefs: URL
    let stateDir: URL
    let home: URL
    let blocklist: URL
    let xpi: URL
    private let script: URL
    private let bin: URL

    init() throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("disciplined-tests-\(UUID().uuidString)", isDirectory: true)
        hostsURL = root.appendingPathComponent("etc/hosts")
        managedPrefs = root.appendingPathComponent("Managed Preferences", isDirectory: true)
        stateDir = root.appendingPathComponent("State", isDirectory: true)
        // Laid out like the real home folder: the script finds ~/Applications from the blocklist's path.
        home = root.appendingPathComponent("home", isDirectory: true)
        blocklist = home.appendingPathComponent("Library/Application Support/Disciplined/blocklist.txt")
        xpi = blocklist.deletingLastPathComponent().appendingPathComponent("Disciplined.xpi")
        script = root.appendingPathComponent("apply-blocklist.sh")
        bin = root.appendingPathComponent("bin", isDirectory: true)

        for dir in [hostsURL.deletingLastPathComponent(), blocklist.deletingLastPathComponent(), bin,
                    home.appendingPathComponent("Applications"), root.appendingPathComponent("Applications")] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data("xpi".utf8).write(to: xpi)
        try writeHosts("127.0.0.1 localhost\n")

        // Each replacement must apply, or the copy would point at the real system.
        var text = try Repo.read("Resources/apply-blocklist.sh")
        for (original, replacement) in [
            (#"HOSTS="/etc/hosts""#, "HOSTS=\(Self.quoted(hostsURL.path))"),
            (#"MANAGED_PREFS="/Library/Managed Preferences""#, "MANAGED_PREFS=\(Self.quoted(managedPrefs.path))"),
            (#"STATE_DIR="/Library/Application Support/Disciplined""#, "STATE_DIR=\(Self.quoted(stateDir.path))"),
            ("for app in /Applications/*.app ", "for app in \(Self.quoted(root.path))/Applications/*.app "),
        ] {
            guard text.contains(original) else { throw FakeSystemError.scriptChanged(original) }
            text = text.replacingOccurrences(of: original, with: replacement)
        }
        try text.write(to: script, atomically: true, encoding: .utf8)

        // Stand-ins for the commands that need root or would affect the real system.
        try Self.writeExecutable(bin.appendingPathComponent("killall"), "exit 0")
        try Self.writeExecutable(bin.appendingPathComponent("dscacheutil"), "exit 0")
        try Self.writeExecutable(bin.appendingPathComponent("install"), """
        args=()
        while [ $# -gt 0 ]; do case "$1" in -o|-g) shift 2 ;; *) args+=("$1"); shift ;; esac; done
        exec /usr/bin/install "${args[@]}"
        """)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func run(blocklist text: String) throws {
        try text.write(to: blocklist, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, blocklist.path]
        process.environment = ["PATH": "\(bin.path):/usr/bin:/bin:/usr/sbin:/sbin"]
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "apply-blocklist.sh failed: \(stderr)")
    }

    func writeHosts(_ text: String) throws { try text.write(to: hostsURL, atomically: true, encoding: .utf8) }
    func hosts() throws -> String { try String(contentsOf: hostsURL, encoding: .utf8) }
    func browsersTSV() throws -> String { try String(contentsOf: stateDir.appendingPathComponent("browsers.tsv"), encoding: .utf8) }
    func policyURL(_ bundleID: String) -> URL { managedPrefs.appendingPathComponent("\(bundleID).plist") }

    func policy(_ bundleID: String) throws -> [String: Any] {
        let data = try Data(contentsOf: policyURL(bundleID))
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] ?? [:]
    }

    func websiteFilter(_ bundleID: String) throws -> [String]? {
        let policy = try policy(bundleID)
        #expect(policy["EnterprisePoliciesEnabled"] as? Bool == true)
        return (policy["WebsiteFilter"] as? [String: Any])?["Block"] as? [String]
    }

    /// Just enough of a Firefox-based browser for the script to detect it, in ~/Applications.
    @discardableResult
    func makeGeckoApp(_ name: String, bundleID: String, milestone: Int, requiresSigning: Bool) throws -> URL {
        let fm = FileManager.default
        let app = home.appendingPathComponent("Applications/\(name).app", isDirectory: true)
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        try fm.createDirectory(at: resources.appendingPathComponent("browser"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": bundleID], format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        try "[App]\nName=\(name)\nProfile=\(name) Profiles\n".write(to: resources.appendingPathComponent("application.ini"), atomically: true, encoding: .utf8)
        try "[Build]\nMilestone=\(milestone).0\n".write(to: resources.appendingPathComponent("platform.ini"), atomically: true, encoding: .utf8)

        let omni = root.appendingPathComponent("omni-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: omni) }
        try fm.createDirectory(at: omni.appendingPathComponent("modules"), withIntermediateDirectories: true)
        try "export const AppConstants = { MOZ_REQUIRE_SIGNING: \(requiresSigning), };\n"
            .write(to: omni.appendingPathComponent("modules/AppConstants.sys.mjs"), atomically: true, encoding: .utf8)
        try Self.zip(omni, to: resources.appendingPathComponent("omni.ja"))
        try Self.zip(omni, to: resources.appendingPathComponent("browser/omni.ja"))
        return app
    }

    private static func zip(_ folder: URL, to archive: URL) throws {
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-r", archive.path, "."]
        zip.currentDirectoryURL = folder
        try zip.run()
        zip.waitUntilExit()
        #expect(zip.terminationStatus == 0)
    }

    private static func writeExecutable(_ url: URL, _ body: String) throws {
        try "#!/bin/bash\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private enum FakeSystemError: Error {
    case scriptChanged(String)
}

private extension String {
    /// The hosts file without the Disciplined section.
    func removingSection() -> String {
        var inSection = false
        return split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            if line == BlockerHelper.beginMark { inSection = true; return false }
            if line == BlockerHelper.endMark { inSection = false; return false }
            return !inSection
        }.joined(separator: "\n")
    }
}
