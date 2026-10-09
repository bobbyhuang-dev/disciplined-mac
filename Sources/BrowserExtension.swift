import AppKit

/// Sets up the browser extensions and the native messaging manifests that let them launch `NativeHost`.
/// None of this needs admin rights.
///
/// - Chromium browsers: a stable copy of the extension the user loads unpacked.
/// - Firefox-based browsers: an .xpi the root helper force-installs through the browser's policy file.
enum BrowserExtension {

    static let hostName = "com.disciplined.mac"
    /// Fixed by the "key" in Extension/manifest.json.
    static let extensionID = "cahkffffmoegiemnmmgeommallbcgdhk"
    /// Fixed by browser_specific_settings in FirefoxExtension/manifest.json.
    static let firefoxExtensionID = "disciplined@disciplined.mac"

    /// Where the user loads the unpacked extension from. Kept outside the app bundle so it survives app moves.
    static var folderURL: URL { BlockerHelper.supportDir.appendingPathComponent("Chrome Extension", isDirectory: true) }

    /// Unpacked Firefox build, zipped into `xpiURL`.
    private static var firefoxFolderURL: URL { BlockerHelper.supportDir.appendingPathComponent("Firefox Extension", isDirectory: true) }

    /// Must match the path apply-blocklist.sh puts in the Firefox/Zen policy.
    static var xpiURL: URL { BlockerHelper.supportDir.appendingPathComponent("Disciplined.xpi") }

    /// Profile folders of Chromium browsers; each gets a host manifest if the browser is installed.
    private static let browserDirs = [
        "Google/Chrome", "BraveSoftware/Brave-Browser", "Microsoft Edge", "Chromium", "Vivaldi",
    ]

    /// Firefox (and Zen) read host manifests from Mozilla/; forks that changed that path use their profile folder.
    private static let mozillaDir = "Mozilla"

    /// An installed browser, for showing its name and icon.
    struct InstalledBrowser: Hashable {
        let name: String
        let appURL: URL
    }

    /// The installed Chromium browser the user most likely loads the extension into, if any.
    static let chromiumBrowser = firstInstalled([
        ("com.google.Chrome", "Chrome"), ("com.brave.Browser", "Brave"), ("com.microsoft.edgemac", "Edge"),
        ("org.chromium.Chromium", "Chromium"), ("com.vivaldi.Vivaldi", "Vivaldi"),
    ])

    private static func firstInstalled(_ candidates: [(bundleID: String, name: String)]) -> InstalledBrowser? {
        for candidate in candidates {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: candidate.bundleID) {
                return InstalledBrowser(name: candidate.name, appURL: url)
            }
        }
        return nil
    }

    // MARK: - Firefox-based browsers

    /// A Firefox-based browser the root helper found and wrote a policy for.
    struct GeckoBrowser: Hashable, Identifiable {
        enum Mode: String {
            /// Force-installed extension; list changes apply live.
            case `extension`
            /// WebsiteFilter policy (release Firefox only installs signed extensions); read at startup.
            case filter
        }

        let bundleID: String
        let mode: Mode
        /// Folder under ~/Library/Application Support holding its profiles.
        let profileFolder: String
        let appURL: URL

        var id: String { bundleID }
        var name: String { appURL.deletingPathExtension().lastPathComponent }
        var installed: InstalledBrowser { InstalledBrowser(name: name, appURL: appURL) }
        var policyURL: URL { URL(fileURLWithPath: "/Library/Managed Preferences/\(bundleID).plist") }
        var profilesURL: URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/\(profileFolder)", isDirectory: true)
        }
    }

    /// Reads the helper's browsers.tsv: "bundle-id<TAB>mode<TAB>profile-folder<TAB>app-path" per line.
    static func geckoBrowsers() -> [GeckoBrowser] {
        guard let text = try? String(contentsOfFile: BlockerHelper.browsersPath, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, let mode = GeckoBrowser.Mode(rawValue: fields[1]) else { return nil }
            return GeckoBrowser(bundleID: fields[0], mode: mode, profileFolder: fields[2],
                                appURL: URL(fileURLWithPath: fields[3], isDirectory: true))
        }
    }

    /// Heartbeat key for Chromium browsers; Firefox-based ones use their bundle ID.
    static let chromeKey = "chrome"

    private static func heartbeatURL(_ key: String) -> URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("com.disciplined.mac/extension-heartbeat-\(key)")
    }

    // MARK: - Install

    static func install() throws {
        try copyExtension()
        try buildFirefoxExtension()
        try writeHostManifests(gecko: geckoBrowsers())
    }

    private static func copyExtension() throws {
        guard let bundled = Bundle.main.url(forResource: "Extension", withExtension: nil) else { return }
        try mirror(bundled, to: folderURL)
    }

    /// The shared extension files with the Firefox manifest swapped in, zipped into `xpiURL`.
    private static func buildFirefoxExtension() throws {
        let fm = FileManager.default
        guard let shared = Bundle.main.url(forResource: "Extension", withExtension: nil),
              let manifest = Bundle.main.url(forResource: "FirefoxExtension", withExtension: nil)?
                  .appendingPathComponent("manifest.json")
        else { return }

        let staging = fm.temporaryDirectory.appendingPathComponent("disciplined-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: shared, to: staging)
        let stagedManifest = staging.appendingPathComponent("manifest.json")
        try fm.removeItem(at: stagedManifest)
        try fm.copyItem(at: manifest, to: stagedManifest)

        let changed = try mirror(staging, to: firefoxFolderURL)
        if !changed && fm.fileExists(atPath: xpiURL.path) { return }

        let tmpXPI = BlockerHelper.supportDir.appendingPathComponent(".Disciplined.xpi.tmp")
        try? fm.removeItem(at: tmpXPI)
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.arguments = ["-q", "-X", "-r", tmpXPI.path, "."]
        zip.currentDirectoryURL = firefoxFolderURL
        try zip.run()
        zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        if fm.fileExists(atPath: xpiURL.path) {
            _ = try fm.replaceItemAt(xpiURL, withItemAt: tmpXPI)
        } else {
            try fm.moveItem(at: tmpXPI, to: xpiURL)
        }
    }

    /// Makes `destination` an exact copy of `source`. Returns whether anything had to change.
    @discardableResult
    private static func mirror(_ source: URL, to destination: URL) throws -> Bool {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(atPath: source.path)
        let existing = (try? fm.contentsOfDirectory(atPath: destination.path)) ?? []
        let upToDate = Set(files) == Set(existing) && files.allSatisfy {
            fm.contentsEqual(atPath: source.appendingPathComponent($0).path, andPath: destination.appendingPathComponent($0).path)
        }
        if upToDate { return false }
        try? fm.removeItem(at: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: source, to: destination)
        return true
    }

    /// Also called when the helper finds a new Firefox-based browser, to cover its profile folder.
    static func writeHostManifests(gecko: [GeckoBrowser]) throws {
        guard let executable = Bundle.main.executablePath else { return }
        let appSupport = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let base: [String: Any] = [
            "name": hostName,
            "description": "Disciplined blocklist",
            "path": executable,
            "type": "stdio",
        ]
        var chrome = base
        chrome["allowed_origins"] = ["chrome-extension://\(extensionID)/"]
        var firefox = base
        firefox["allowed_extensions"] = [firefoxExtensionID]

        for dir in browserDirs { try writeHostManifest(chrome, in: appSupport.appendingPathComponent(dir)) }
        let geckoDirs = Set([mozillaDir] + gecko.map(\.profileFolder))
        for dir in geckoDirs { try writeHostManifest(firefox, in: appSupport.appendingPathComponent(dir)) }
    }

    /// Writes the manifest into the browser's NativeMessagingHosts folder, if the browser is installed.
    private static func writeHostManifest(_ manifest: [String: Any], in browser: URL) throws {
        guard FileManager.default.fileExists(atPath: browser.path) else { return }
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        let hosts = browser.appendingPathComponent("NativeMessagingHosts")
        try FileManager.default.createDirectory(at: hosts, withIntermediateDirectories: true)
        let url = hosts.appendingPathComponent("\(hostName).json")
        if (try? Data(contentsOf: url)) != data { try data.write(to: url, options: .atomic) }
    }

    // MARK: - Connection status

    /// Called by the host every second while the extension is connected.
    static func markConnected(_ key: String) {
        let url = heartbeatURL(key)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: url)
    }

    static func isConnected(_ key: String) -> Bool {
        guard let modified = try? heartbeatURL(key).resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return false }
        return Date().timeIntervalSince(modified) < 3
    }
}
