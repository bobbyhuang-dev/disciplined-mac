import Foundation

/// Native messaging host for the browser extensions. The browser launches this binary while its
/// extension is connected; it streams the blocklist to the extension.
///
/// Protocol: each message is a 32-bit native-endian length followed by that many bytes of UTF-8 JSON.
enum NativeHost {
    /// The heartbeat key of the browser that launched us, or nil for a normal app launch.
    /// Chrome passes the extension's origin; Firefox passes the manifest path and the extension's ID.
    static var launchingBrowser: String? {
        let args = CommandLine.arguments.dropFirst()
        if args.contains(where: { $0.hasPrefix("chrome-extension://") }) { return BrowserExtension.chromeKey }
        if args.contains(BrowserExtension.firefoxExtensionID) { return parentBundleID() ?? "firefox" }
        return nil
    }

    /// Firefox-based browsers launch the host from their main process, so the parent says which one it is.
    private static func parentBundleID() -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(getppid(), &buffer, UInt32(buffer.count)) > 0 else { return nil }
        var url = URL(fileURLWithPath: String(cString: buffer))
        while url.pathComponents.count > 1 {
            if url.pathExtension == "app" { return Bundle(url: url)?.bundleIdentifier }
            url.deleteLastPathComponent()
        }
        return nil
    }

    static func run(for browser: String) -> Never {
        // The browser closes stdin when the extension disconnects. Nothing it sends needs a reply.
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while read(STDIN_FILENO, &buffer, buffer.count) > 0 {}
            exit(0)
        }

        var lastSent: [String]?
        while true {
            let domains = currentDomains()
            if domains != lastSent {
                send(["domains": domains])
                lastSent = domains
            }
            BrowserExtension.markConnected(browser)
            sleep(1)
        }
    }

    /// The list the app wants enforced right now (empty while blocking is off).
    private static func currentDomains() -> [String] {
        guard let text = try? String(contentsOf: BlockerHelper.blocklistURL, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { Domain.normalize($0) == $0 }
    }

    private static func send(_ message: [String: Any]) {
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        var length = UInt32(body.count)
        let header = Data(bytes: &length, count: 4)
        FileHandle.standardOutput.write(header + body)
    }
}
