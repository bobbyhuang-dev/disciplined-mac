import SwiftUI

struct SettingsView: View {
    @AppStorage(Favicon.showKey) private var showIcons = true
    @AppStorage(Favicon.sourceKey) private var source = Favicon.Source.google

    var body: some View {
        Form {
            Section {
                Toggle("Show site icons", isOn: $showIcons)
                Picker("Source", selection: $source) {
                    ForEach(Favicon.Source.allCases) { source in
                        Text(source.name).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!showIcons)
            } footer: {
                // Blocked sites can't serve their own icons, so the source sees the list.
                Text(showIcons ? "Site names are sent to \(source.name) to find their icons." : "Sites show their first letter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .animation(.smooth, value: showIcons)
            }
        }
        .formStyle(.grouped)
        .tint(.indigo)
        .scrollDisabled(true)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
