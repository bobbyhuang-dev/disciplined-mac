import AppKit

/// Quits a Firefox-based browser and opens it again with its windows and tabs, the way its own restart
/// does: `browser.sessionstore.resume_session_once` restores the last session on the next launch only,
/// whatever the user's startup setting is.
enum BrowserRestarter {
    enum RestartError: LocalizedError {
        case didNotQuit(String)

        var errorDescription: String? {
            switch self {
            case .didNotQuit(let name): "\(name) didn't quit. Close any open dialogs in it and try again."
            }
        }
    }

    @MainActor
    static func restart(_ browser: BrowserExtension.GeckoBrowser) async throws {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID)
        let appURL = running.first?.bundleURL ?? browser.appURL
        // Found before quitting: the profiles in use are the ones still saving their session.
        let profiles = profilesInUse(by: browser)

        for app in running { app.terminate() }
        // Firefox saves the session and shuts down its content processes first, which can take a while.
        let deadline = Date().addingTimeInterval(30)
        while running.contains(where: { !$0.isTerminated }) {
            guard Date() < deadline else { throw RestartError.didNotQuit(browser.name) }
            try await Task.sleep(for: .milliseconds(200))
        }

        // prefs.js is rewritten on quit, so this has to happen after the browser has exited.
        for profile in profiles { resumeSessionOnce(in: profile) }
        _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Profiles the browser has open, falling back to its default profile.
    private static func profilesInUse(by browser: BrowserExtension.GeckoBrowser) -> [URL] {
        let root = browser.profilesURL
        let all = iniValues("Path", in: root.appendingPathComponent("profiles.ini")).map { profileURL($0, root: root) }
        let open = all.filter(isLocked)
        if !open.isEmpty { return open }
        return iniValues("Default", in: root.appendingPathComponent("installs.ini")).map { profileURL($0, root: root) }
    }

    /// A running browser holds an fcntl lock on the profile's .parentlock; F_GETLK checks without taking it.
    private static func isLocked(_ profile: URL) -> Bool {
        let fd = open(profile.appendingPathComponent(".parentlock").path, O_RDWR)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var lock = flock()
        lock.l_type = Int16(F_WRLCK)
        lock.l_whence = Int16(SEEK_SET)
        guard fcntl(fd, F_GETLK, &lock) == 0 else { return false }
        return lock.l_type != Int16(F_UNLCK)
    }

    /// Profile paths are relative to the profiles folder unless they're absolute.
    private static func profileURL(_ path: String, root: URL) -> URL {
        path.hasPrefix("/") ? URL(fileURLWithPath: path, isDirectory: true) : root.appendingPathComponent(path, isDirectory: true)
    }

    private static func iniValues(_ key: String, in file: URL) -> [String] {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            line.hasPrefix("\(key)=") ? String(line.dropFirst(key.count + 1)) : nil
        }
    }

    private static func resumeSessionOnce(in profile: URL) {
        let prefs = profile.appendingPathComponent("prefs.js")
        guard let handle = try? FileHandle(forWritingTo: prefs) else { return }
        defer { try? handle.close() }
        // A later line wins over any earlier value of the pref.
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("user_pref(\"browser.sessionstore.resume_session_once\", true);\n".utf8))
    }
}
