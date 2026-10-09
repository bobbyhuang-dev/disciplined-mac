import SwiftUI

struct DisciplinedApp: App {
    @State private var model = BlockerModel()

    var body: some Scene {
        Window("Disciplined", id: "main") {
            ContentView()
                .environment(model)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 380, height: 520)
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Remove Blocker Helper…") {
                    Task { await model.removeHelper() }
                }
                .disabled(!model.helperInstalled)
            }
        }

        // Always visible while the app is running, so it's obvious whether it's open and easy to quit.
        MenuBarExtra {
            MenuBarMenu()
                .environment(model)
        } label: {
            Image(systemName: model.status == .active ? "shield.lefthalf.filled" : "shield")
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarMenu: View {
    @Environment(BlockerModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        Text(model.statusText)
        Toggle("Block Websites", isOn: $model.isBlocking)
            .disabled(!model.helperInstalled)
        Divider()
        Button("Open Disciplined") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")
        Divider()
        Button("Quit Disciplined") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
