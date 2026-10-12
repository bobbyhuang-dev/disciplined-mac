import ServiceManagement
import SwiftUI

/// Tabs across the top of the window, like most Mac apps' settings; it resizes to fit each one.
struct SettingsView: View {
    @AppStorage(AppTheme.key) private var theme = AppTheme.indigo

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .tint(theme.color)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @State private var language = AppLanguage.current
    @AppStorage(AppTheme.key) private var theme = AppTheme.indigo
    /// The user can also change this in System Settings › General › Login Items, so it's read from there, not saved.
    @State private var loginItem = SMAppService.mainApp.status
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: openAtLogin)
            } footer: {
                if loginItem == .requiresApproval {
                    HStack {
                        Text("Allow Disciplined in Login Items so it can open at login.")
                            .footerStyle()
                        Spacer()
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                            .controlSize(.small)
                    }
                } else if let loginError {
                    Text(loginError)
                        .footerStyle()
                }
            }

            Section {
                LabeledContent("Accent color") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ThemePicker(selection: $theme)
                        Text(theme.name)
                            .footerStyle()
                    }
                }
            } footer: {
                Text("Also colors the page browsers show for blocked sites.")
                    .footerStyle()
            }

            Section {
                Picker("Language", selection: $language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.name).tag(language)
                    }
                }
                .onChange(of: language) { _, language in language.save() }
            } footer: {
                if language.needsRelaunch {
                    HStack {
                        Text("Disciplined will switch languages when it relaunches.")
                            .footerStyle()
                        Spacer()
                        Button("Relaunch Now") { AppLanguage.relaunch() }
                            .controlSize(.small)
                    }
                }
            }
        }
        .settingsPane()
        .onAppear { loginItem = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginItem = SMAppService.mainApp.status
        }
    }

    private var openAtLogin: Binding<Bool> {
        Binding {
            loginItem == .enabled || loginItem == .requiresApproval
        } set: { on in
            do {
                if on {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                loginError = nil
            } catch {
                loginError = error.localizedDescription
            }
            loginItem = SMAppService.mainApp.status
        }
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @AppStorage(Favicon.showKey) private var showIcons = true
    @AppStorage(Favicon.sourceKey) private var source = Favicon.Source.google
    @AppStorage(SiteListPrivacy.hideKey) private var hideList = true
    @AppStorage(SiteListPrivacy.authenticateKey) private var authenticate = false

    var body: some View {
        Form {
            Section {
                Toggle("Hide site list", isOn: protected($hideList))
                Toggle("Require Touch ID or password to show", isOn: protected($authenticate))
                    .disabled(!hideList)
            } header: {
                Text("Site List")
            } footer: {
                Text("Sites show only when you ask, and hide again when you switch apps or lock your Mac.")
                    .footerStyle()
            }

            Section {
                Toggle("Show site icons", isOn: $showIcons)
                Picker("Source", selection: $source) {
                    ForEach(Favicon.Source.allCases) { source in
                        Text(source.name).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!showIcons)
            } header: {
                Text("Site Icons")
            } footer: {
                // Blocked sites can't serve their own icons, so the source sees the list.
                Text(showIcons ? String(localized: "Site names are sent to \(source.name) to find their icons.") : String(localized: "Sites show their first letter."))
                    .footerStyle()
                    .contentTransition(.opacity)
                    .animation(.smooth, value: showIcons)
            }
        }
        .settingsPane()
    }

    /// While Touch ID guards the list, turning a protection off asks for it too, so it can't be skipped here.
    private func protected(_ setting: Binding<Bool>) -> Binding<Bool> {
        Binding {
            setting.wrappedValue
        } set: { on in
            guard !on, hideList, authenticate else {
                setting.wrappedValue = on
                return
            }
            Task {
                if await SiteListPrivacy.authenticate() { setting.wrappedValue = on }
            }
        }
    }
}

// MARK: - Shared

private extension Text {
    func footerStyle() -> some View {
        font(.caption).foregroundStyle(.secondary)
    }
}

private extension View {
    /// Every tab is the same width and exactly as tall as its settings.
    func settingsPane() -> some View {
        formStyle(.grouped)
            .scrollDisabled(true)
            .frame(width: 420)
            .fixedSize(horizontal: false, vertical: true)
    }
}
