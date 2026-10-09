import AppKit
import Observation

/// A Firefox-based browser's extension or policy, as the footer shows it.
struct GeckoBrowserStatus: Equatable, Identifiable {
    let browser: BrowserExtension.GeckoBrowser
    let connected: Bool
    let isRunning: Bool
    /// The running browser hasn't picked up its policy, extension or (for `.filter`) the current list.
    let needsRestart: Bool
    var id: String { browser.bundleID }
}

@MainActor
@Observable
final class BlockerModel {
    enum Status { case needsSetup, off, applying, active }

    private(set) var domains: [String]
    var isBlocking: Bool {
        didSet { persist() }
    }
    private(set) var helperInstalled = BlockerHelper.isInstalled
    private(set) var appliedHosts = BlockerHelper.appliedHosts()
    private(set) var chromeConnected = BrowserExtension.isConnected(BrowserExtension.chromeKey)
    private(set) var geckoBrowsers: [GeckoBrowserStatus] = []
    /// Bundle IDs of browsers being restarted.
    private(set) var restarting: Set<String> = []
    private(set) var isWorking = false
    var errorMessage: String?

    private let defaults = UserDefaults.standard
    private var monitor: Task<Void, Never>?
    private var knownGecko: [BrowserExtension.GeckoBrowser] = []

    init() {
        domains = defaults.stringArray(forKey: "domains") ?? []
        isBlocking = defaults.bool(forKey: "isBlocking")
        do {
            try BrowserExtension.install()
        } catch {
            errorMessage = error.localizedDescription
        }
        persist()
        startMonitoring()
    }

    var status: Status {
        if !helperInstalled { return .needsSetup }
        if appliedHosts != expectedHosts { return .applying }
        return isBlocking && !domains.isEmpty ? .active : .off
    }

    var statusText: String {
        switch status {
        case .active: domains.count == 1 ? "Blocking 1 site" : "Blocking \(domains.count) sites"
        case .applying: "Applying…"
        case .needsSetup: "Setup needed"
        case .off: "Off"
        }
    }

    private var expectedHosts: Set<String> {
        isBlocking ? Set(domains.flatMap(Domain.hosts(for:))) : []
    }

    // MARK: - Editing

    /// Returns false if the input isn't a valid domain.
    @discardableResult
    func add(_ input: String) -> Bool {
        guard let domain = Domain.normalize(input) else { return false }
        if !domains.contains(domain) {
            domains.insert(domain, at: 0)
            persist()
        }
        return true
    }

    func remove(_ domain: String) {
        domains.removeAll { $0 == domain }
        persist()
    }

    // MARK: - Helper

    func setUp() async {
        await runHelperTask { try await BlockerHelper.install() }
    }

    func removeHelper() async {
        await runHelperTask { try await BlockerHelper.uninstall() }
    }

    private func runHelperTask(_ work: () async throws -> Void) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await work()
            persist()
        } catch BlockerHelper.HelperError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    // MARK: - Browsers

    func restart(_ browser: BrowserExtension.GeckoBrowser) async {
        restarting.insert(browser.bundleID)
        errorMessage = nil
        defer {
            restarting.remove(browser.bundleID)
            refresh()
        }
        do {
            try await BrowserRestarter.restart(browser)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func status(of browser: BrowserExtension.GeckoBrowser) -> GeckoBrowserStatus {
        let connected = BrowserExtension.isConnected(browser.bundleID)
        let launched = NSRunningApplication.runningApplications(withBundleIdentifier: browser.bundleID)
            .compactMap(\.launchDate).min()
        var needsRestart = false
        if let launched {
            // Policies (and the extension they install) are only read when the browser starts.
            let changed = [browser.policyURL, BrowserExtension.xpiURL].contains { modified($0).map { $0 > launched } ?? false }
            switch browser.mode {
            case .extension:
                // Once connected, the list updates live; give a fresh launch a moment to connect.
                needsRestart = !connected && (changed || Date().timeIntervalSince(launched) > 15)
            case .filter:
                needsRestart = changed
            }
        }
        return GeckoBrowserStatus(browser: browser, connected: connected, isRunning: launched != nil, needsRestart: needsRestart)
    }

    private static func modified(_ url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    // MARK: - Sync

    private func persist() {
        defaults.set(domains, forKey: "domains")
        defaults.set(isBlocking, forKey: "isBlocking")
        do {
            try BlockerHelper.writeBlocklist(isBlocking ? domains : [])
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }

    private func refresh() {
        let installed = BlockerHelper.isInstalled
        let applied = BlockerHelper.appliedHosts()
        let chrome = BrowserExtension.isConnected(BrowserExtension.chromeKey)
        let gecko = BrowserExtension.geckoBrowsers()
        if gecko != knownGecko {
            // A newly found browser may keep its host manifests in its own folder.
            knownGecko = gecko
            try? BrowserExtension.writeHostManifests(gecko: gecko)
        }
        let geckoStatuses = gecko.map(Self.status(of:))
        // Only assign on change so the 1s poll doesn't redraw the UI.
        if installed != helperInstalled { helperInstalled = installed }
        if applied != appliedHosts { appliedHosts = applied }
        if chrome != chromeConnected { chromeConnected = chrome }
        if geckoStatuses != geckoBrowsers { geckoBrowsers = geckoStatuses }
    }

    private func startMonitoring() {
        monitor = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }
}
