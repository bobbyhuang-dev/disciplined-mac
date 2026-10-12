import AppKit

/// The app's language, picked in Settings. It's stored where System Settings keeps an app's language
/// (`AppleLanguages` in the app's own defaults), so the two stay in sync. macOS only reads it at launch.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: Self { self }

    /// Languages are named in their own language, so they're recognizable whatever the current one is.
    var name: String {
        switch self {
        case .system: String(localized: "System Language")
        case .english: "English"
        case .simplifiedChinese: "简体中文"
        }
    }

    private static let key = "AppleLanguages"

    /// The saved choice; a language the app doesn't have counts as the system's.
    static var current: AppLanguage {
        let domain = Bundle.main.bundleIdentifier.flatMap(UserDefaults.standard.persistentDomain(forName:))
        guard let first = (domain?[key] as? [String])?.first else { return .system }
        return allCases.first { $0 != .system && (first == $0.rawValue || first.hasPrefix($0.rawValue + "-")) } ?? .system
    }

    func save() {
        if self == .system {
            UserDefaults.standard.removeObject(forKey: Self.key)
        } else {
            UserDefaults.standard.set([rawValue], forKey: Self.key)
        }
    }

    /// The app's next launch would show a different language than this one does.
    var needsRelaunch: Bool {
        let preferences = self == .system ? Self.systemLanguages : [rawValue]
        let next = Bundle.preferredLocalizations(from: Bundle.main.localizations, forPreferences: preferences).first
        return next != Bundle.main.preferredLocalizations.first
    }

    /// The user's languages in System Settings, ignoring the app's own override.
    private static var systemLanguages: [String] {
        CFPreferencesCopyValue(key as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            as? [String] ?? []
    }

    /// Quits, then opens the app again once this process has exited.
    @MainActor
    static func relaunch() {
        let wait = Process()
        wait.executableURL = URL(fileURLWithPath: "/bin/sh")
        wait.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.1; done; open \"$0\"",
                          Bundle.main.bundlePath]
        try? wait.run()
        NSApp.terminate(nil)
    }
}
