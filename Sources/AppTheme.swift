import AppKit
import SwiftUI

/// The app's accent color, picked in Settings. It tints the app and, through the native messaging host,
/// the browser extension's blocked page. The app icon stays indigo.
enum AppTheme: String, CaseIterable, Identifiable {
    case indigo, blue, teal, orange, pink
    /// The accent color in System Settings › Appearance.
    case system

    static let key = "appTheme"

    var id: Self { self }

    var name: String {
        switch self {
        case .indigo: String(localized: "Indigo")
        case .blue: String(localized: "Blue")
        case .teal: String(localized: "Teal")
        case .orange: String(localized: "Orange")
        case .pink: String(localized: "Pink")
        case .system: String(localized: "System Accent")
        }
    }

    var color: Color { Color(nsColor: nsColor) }

    private var nsColor: NSColor {
        switch self {
        case .indigo: .systemIndigo
        case .blue: .systemBlue
        case .teal: .systemTeal
        case .orange: .systemOrange
        case .pink: .systemPink
        case .system: .controlAccentColor
        }
    }

    static var current: AppTheme {
        UserDefaults.standard.string(forKey: key).flatMap(AppTheme.init) ?? .indigo
    }

    /// The current colors, saved by the app for the native host. Outside a running app `controlAccentColor`
    /// keeps the value it had at launch, so the host can't follow a new system accent on its own.
    private static let colorsKey = "appThemeColors"

    /// Run by the app's 1s poll, which catches both a new choice here and a new accent in System Settings.
    static func saveColors() {
        let colors = current.hex
        if UserDefaults.standard.dictionary(forKey: colorsKey) as? [String: String] != colors {
            UserDefaults.standard.set(colors, forKey: colorsKey)
        }
    }

    /// For the native host, which reads them each second.
    static var savedColors: [String: String] {
        UserDefaults.standard.dictionary(forKey: colorsKey) as? [String: String] ?? current.hex
    }

    /// The color as `#rrggbb` in light and dark mode, for the blocked page's CSS.
    var hex: [String: String] {
        ["light": Self.hex(nsColor, in: .aqua), "dark": Self.hex(nsColor, in: .darkAqua)]
    }

    private static func hex(_ color: NSColor, in appearance: NSAppearance.Name) -> String {
        var result = ""
        NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
            guard let rgb = color.usingColorSpace(.sRGB) else { return }
            let bytes = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
                .map { Int((min(max($0, 0), 1) * 255).rounded()) }
            result = "#" + bytes.map { String(format: "%02x", $0) }.joined()
        }
        return result
    }
}

/// A row of color dots, like the accent color picker in System Settings.
struct ThemePicker: View {
    @Binding var selection: AppTheme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppTheme.allCases) { theme in
                Button {
                    selection = theme
                } label: {
                    swatch(theme)
                }
                .buttonStyle(.plain)
                .help(theme.name)
                .accessibilityLabel(theme.name)
                .accessibilityAddTraits(theme == selection ? .isSelected : [])
            }
        }
    }

    private func swatch(_ theme: AppTheme) -> some View {
        ZStack {
            if theme == .system {
                Circle().fill(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red], center: .center))
            } else {
                Circle().fill(theme.color.gradient)
            }
            Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
            if theme == selection {
                Circle().fill(.white).frame(width: 6, height: 6)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: 16, height: 16)
        .contentShape(Circle())
        .animation(.smooth(duration: 0.2), value: selection)
    }
}
