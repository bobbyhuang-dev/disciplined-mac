import Foundation

/// Installs and talks to the root LaunchDaemon that applies the blocklist to /etc/hosts and to managed
/// browser policies (which still apply when a proxy like Surge resolves DNS itself).
///
/// The app writes domains to `blocklistURL` (owned by the user). launchd watches that file and runs
/// `apply-blocklist.sh` as root whenever it changes, so no password is needed after the one-time setup.
enum BlockerHelper {
    static let label = "com.disciplined.blocker"
    static let plistPath = "/Library/LaunchDaemons/\(label).plist"
    static let helperDir = "/Library/Application Support/Disciplined"
    static let helperScriptPath = "\(helperDir)/apply-blocklist.sh"
    /// Firefox-based browsers the helper found; see `BrowserExtension.geckoBrowsers()`.
    static let browsersPath = "\(helperDir)/browsers.tsv"
    static let hostsPath = "/etc/hosts"
    static let beginMark = "# >>> Disciplined blocklist >>>"
    static let endMark = "# <<< Disciplined blocklist <<<"

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Disciplined", isDirectory: true)
    }

    static var blocklistURL: URL { supportDir.appendingPathComponent("blocklist.txt") }

    private static var bundledScriptURL: URL? {
        Bundle.main.url(forResource: "apply-blocklist", withExtension: "sh")
    }

    // MARK: - State

    /// True when the daemon is installed and its script matches the one bundled with this build.
    static var isInstalled: Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: plistPath),
              let installed = fm.contents(atPath: helperScriptPath),
              let bundled = bundledScriptURL.flatMap({ try? Data(contentsOf: $0) })
        else { return false }
        return installed == bundled
    }

    /// Hostnames currently blocked by our section of /etc/hosts.
    static func appliedHosts() -> Set<String> {
        guard let text = try? String(contentsOfFile: hostsPath, encoding: .utf8) else { return [] }
        var inSection = false
        var hosts = Set<String>()
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line == beginMark { inSection = true; continue }
            if line == endMark { inSection = false; continue }
            guard inSection else { continue }
            let parts = line.split(separator: " ")
            if parts.count == 2, parts[0] == "0.0.0.0" { hosts.insert(String(parts[1])) }
        }
        return hosts
    }

    static func writeBlocklist(_ domains: [String]) throws {
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let text = domains.isEmpty ? "" : domains.joined(separator: "\n") + "\n"
        try text.write(to: blocklistURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Install / uninstall (asks for an admin password)

    static func install() async throws {
        guard let script = bundledScriptURL else { throw HelperError.message("Helper script missing from app bundle.") }
        if !FileManager.default.fileExists(atPath: blocklistURL.path) { try writeBlocklist([]) }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/bash", helperScriptPath, blocklistURL.path],
            // Watch the file and its folder: atomic saves replace the file, which only the folder sees.
            "WatchPaths": [blocklistURL.path, supportDir.path],
            "RunAtLoad": true,
            // Re-apply periodically so removed browser policy files come back.
            "StartInterval": 60,
            "ThrottleInterval": 1,
        ]
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("disciplined-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let plistURL = tmp.appendingPathComponent("\(label).plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)

        try await runAsAdmin("""
        set -e
        mkdir -p \(q(helperDir))
        install -o root -g wheel -m 755 \(q(script.path)) \(q(helperScriptPath))
        launchctl bootout system/\(label) 2>/dev/null || true
        install -o root -g wheel -m 644 \(q(plistURL.path)) \(q(plistPath))
        launchctl bootstrap system \(q(plistPath))
        """, workDir: tmp)
    }

    static func uninstall() async throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("disciplined-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await runAsAdmin("""
        launchctl bootout system/\(label) 2>/dev/null || true
        rm -f \(q(plistPath))
        if [ -x \(q(helperScriptPath)) ]; then /bin/bash \(q(helperScriptPath)) ""; fi
        rm -rf \(q(helperDir))
        """, workDir: tmp)
    }

    private static func runAsAdmin(_ shell: String, workDir: URL) async throws {
        let scriptURL = workDir.appendingPathComponent("run.sh")
        try shell.write(to: scriptURL, atomically: true, encoding: .utf8)
        let apple = "do shell script \"/bin/bash \" & quoted form of \"\(scriptURL.path)\" with administrator privileges"

        try await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", apple]
            let errPipe = Pipe()
            process.standardError = errPipe
            process.standardOutput = Pipe()
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if err.contains("-128") { throw HelperError.cancelled }
                throw HelperError.message(err.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.value
    }

    /// Single-quotes a string for the shell.
    private static func q(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    enum HelperError: LocalizedError {
        case cancelled
        case message(String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Cancelled."
            case .message(let m): m.isEmpty ? "Something went wrong." : m
            }
        }
    }
}
