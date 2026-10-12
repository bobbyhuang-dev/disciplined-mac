import AppKit
import Combine
import LocalAuthentication

/// Keeps the site list out of sight (screen sharing, someone nearby) until the user asks to see it.
@MainActor
enum SiteListPrivacy {
    /// UserDefaults keys for the settings.
    static let hideKey = "hideSiteList"
    static let authenticateKey = "authenticateToShowSites"

    /// Touch ID, or the login password on Macs without it. False if the user cancels.
    static func authenticate() async -> Bool {
        let context = LAContext()
        // Without a way to ask, don't lock the user out of their own list.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else { return true }
        // macOS shows this as "Disciplined is trying to …".
        let reason = String(localized: "show your blocked sites")
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// When a shown list hides again: the app goes to the background, the screen locks or sleeps,
    /// the Mac sleeps, or another user switches in.
    static let hideTriggers: AnyPublisher<Void, Never> = {
        let workspace = NSWorkspace.shared.notificationCenter
        return Publishers.MergeMany(
            NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification),
            workspace.publisher(for: NSWorkspace.willSleepNotification),
            workspace.publisher(for: NSWorkspace.screensDidSleepNotification),
            workspace.publisher(for: NSWorkspace.sessionDidResignActiveNotification),
            DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.screenIsLocked"))
        )
        .map { _ in }
        .eraseToAnyPublisher()
    }()
}
