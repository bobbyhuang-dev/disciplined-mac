import SwiftUI

struct ContentView: View {
    @Environment(BlockerModel.self) private var model

    var body: some View {
        Group {
            if model.helperInstalled {
                MainView()
            } else {
                SetupView()
            }
        }
        .frame(width: 380)
        .frame(minHeight: 480, idealHeight: 520)
        .background(.background)
        .animation(.smooth(duration: 0.25), value: model.helperInstalled)
    }
}

// MARK: - Main

private struct MainView: View {
    @Environment(BlockerModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            Header()
                .padding(.horizontal, 24)
                .padding(.top, 36)
                .padding(.bottom, 20)

            AddField()
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            if model.domains.isEmpty {
                EmptyState()
            } else {
                DomainList()
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .padding(12)
            }

            Divider()
            ExtensionFooter()
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
        }
    }
}

// MARK: - Browser extension

/// One browser's extension (or policy), as shown in the footer.
private struct BrowserStatus: Identifiable {
    enum Kind { case chromium, gecko(GeckoBrowserStatus) }
    let kind: Kind
    let browser: BrowserExtension.InstalledBrowser
    let id: String

    init(chromium browser: BrowserExtension.InstalledBrowser, connected: Bool) {
        kind = .chromium
        self.browser = browser
        id = BrowserExtension.chromeKey
        self.connected = connected
    }

    init(gecko status: GeckoBrowserStatus) {
        kind = .gecko(status)
        browser = status.browser.installed
        id = status.browser.bundleID
        // A policy-only browser has nothing to connect; it's fine as long as it has the current list.
        connected = status.browser.mode == .filter ? !status.needsRestart : status.connected
    }

    /// Shown in full color; dimmed otherwise.
    let connected: Bool

    var gecko: GeckoBrowserStatus? {
        if case .gecko(let status) = kind { status } else { nil }
    }

    /// Something the user has to do.
    var needsAction: Bool { gecko?.needsRestart ?? !connected }

    var detail: String {
        guard let gecko else { return connected ? "Connected" : "Not connected" }
        switch gecko.browser.mode {
        case .extension:
            if gecko.connected { return "Connected" }
            return gecko.isRunning ? "Restart to connect" : "Connects when opened"
        case .filter:
            // Release Firefox only installs extensions signed by Mozilla, so it gets the list at startup.
            return gecko.needsRestart ? "Restart to apply changes" : "Blocks via policy, updated on restart"
        }
    }

    /// One-line summary when this is the only browser that needs attention.
    var hint: String {
        guard let gecko else { return "Set up \(browser.name) to connect" }
        return gecko.browser.mode == .filter ? "Restart \(browser.name) to apply changes" : "Restart \(browser.name) to connect"
    }
}

/// A single row however many browsers there are; the details live in a popover.
private struct ExtensionFooter: View {
    @Environment(BlockerModel.self) private var model
    @State private var showingList = false
    @State private var showingSetup = false
    @State private var hovering = false

    private var browsers: [BrowserStatus] {
        var browsers: [BrowserStatus] = []
        if let chromium = BrowserExtension.chromiumBrowser {
            browsers.append(BrowserStatus(chromium: chromium, connected: model.chromeConnected))
        }
        return browsers + model.geckoBrowsers.map(BrowserStatus.init(gecko:))
    }

    var body: some View {
        let browsers = browsers
        let pending = browsers.filter(\.needsAction)
        if !browsers.isEmpty {
            Button { showingList.toggle() } label: {
                HStack(spacing: 10) {
                    BrowserIconStack(browsers: browsers)
                    Text(summary(browsers: browsers, pending: pending))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                    Spacer(minLength: 4)
                    if !pending.isEmpty {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                            .transition(.scale.combined(with: .opacity))
                    }
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .animation(.smooth, value: pending.count)
            .popover(isPresented: $showingList, arrowEdge: .top) {
                BrowserList(browsers: browsers) {
                    showingList = false
                    showingSetup = true
                }
            }
            .sheet(isPresented: $showingSetup) {
                ExtensionSetupView()
            }
        }
    }

    private func summary(browsers: [BrowserStatus], pending: [BrowserStatus]) -> String {
        switch pending.count {
        case 0:
            browsers.count == 1 ? "Connected to \(browsers[0].browser.name)" : "Connected to \(browsers.count) browsers"
        case 1:
            pending[0].hint
        default:
            "\(pending.count) browsers need attention"
        }
    }
}

/// Overlapping app icons; browsers that aren't connected are dimmed.
private struct BrowserIconStack: View {
    let browsers: [BrowserStatus]
    private let limit = 4

    var body: some View {
        HStack(spacing: -5) {
            ForEach(browsers.prefix(limit)) { status in
                BrowserIcon(browser: status.browser, size: 18)
                    .saturation(status.connected ? 1 : 0)
                    .opacity(status.connected ? 1 : 0.45)
            }
            if browsers.count > limit {
                Text("+\(browsers.count - limit)")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: Circle())
            }
        }
    }
}

private struct BrowserIcon: View {
    let browser: BrowserExtension.InstalledBrowser
    let size: CGFloat

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: browser.appURL.path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

private struct BrowserList: View {
    let browsers: [BrowserStatus]
    let onSetUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Browser Extensions")
                    .font(.system(size: 13, weight: .semibold))
                Text("Blocks sites even through VPNs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 0) {
                ForEach(Array(browsers.enumerated()), id: \.element.id) { index, status in
                    if index > 0 { Divider().padding(.leading, 48) }
                    BrowserRow(status: status, onSetUp: onSetUp)
                }
            }
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(14)
        .frame(width: 290)
    }
}

private struct BrowserRow: View {
    @Environment(BlockerModel.self) private var model
    let status: BrowserStatus
    let onSetUp: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            BrowserIcon(browser: status.browser, size: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.browser.name)
                    .font(.system(size: 13))
                HStack(spacing: 4) {
                    Circle()
                        .fill(status.connected ? AnyShapeStyle(.green) : status.needsAction ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let gecko = status.gecko {
                if model.restarting.contains(gecko.id) {
                    ProgressView()
                        .controlSize(.small)
                } else if gecko.needsRestart {
                    Button("Restart") {
                        Task { await model.restart(gecko.browser) }
                    }
                    .controlSize(.small)
                    .help("Quits and reopens \(status.browser.name) with your tabs restored.")
                }
            } else if !status.connected {
                Button("Set Up…", action: onSetUp)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .animation(.smooth, value: status.connected)
    }
}

private struct ExtensionSetupView: View {
    @Environment(BlockerModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 10) {
                Image(systemName: model.chromeConnected ? "checkmark.circle.fill" : "puzzlepiece.extension.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(model.chromeConnected ? AnyShapeStyle(.green.gradient) : AnyShapeStyle(.indigo.gradient))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(height: 48)
                Text("Add to \(BrowserExtension.chromiumBrowser?.name ?? "Chrome")")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Blocks sites even through VPNs.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                StepRow(number: 1, title: "Open chrome://extensions") {
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString("chrome://extensions", forType: .string)
                        copied = true
                    }
                }
                Divider().padding(.leading, 42)
                StepRow(number: 2, title: "Turn on Developer mode") { EmptyView() }
                Divider().padding(.leading, 42)
                StepRow(number: 3, title: "Drag the folder in") {
                    Button("Show Folder") {
                        NSWorkspace.shared.activateFileViewerSelecting([BrowserExtension.folderURL])
                    }
                }
            }
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            HStack {
                HStack(spacing: 6) {
                    if model.chromeConnected {
                        Text("Connected")
                    } else {
                        ProgressView().controlSize(.mini)
                        Text("Waiting for \(BrowserExtension.chromiumBrowser?.name ?? "Chrome")…")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 340)
        .animation(.smooth, value: model.chromeConnected)
        .onChange(of: model.chromeConnected) { _, connected in
            guard connected else { return }
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                dismiss()
            }
        }
    }
}

private struct StepRow<Accessory: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let accessory: Accessory

    var body: some View {
        HStack(spacing: 10) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.indigo)
                .frame(width: 20, height: 20)
                .background(.indigo.opacity(0.15), in: Circle())
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 8)
            accessory
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }
}

private struct Header: View {
    @Environment(BlockerModel.self) private var model

    var body: some View {
        @Bindable var model = model
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Disciplined")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                StatusLabel(status: model.status, text: model.statusText)
            }
            Spacer()
            Toggle("", isOn: $model.isBlocking)
                .toggleStyle(.switch)
                .controlSize(.large)
                .tint(.indigo)
                .labelsHidden()
        }
    }
}

private struct StatusLabel: View {
    let status: BlockerModel.Status
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: text)
    }

    private var color: Color {
        switch status {
        case .active: .green
        case .applying: .orange
        case .off, .needsSetup: .secondary.opacity(0.5)
        }
    }
}

private struct AddField: View {
    @Environment(BlockerModel.self) private var model
    @State private var text = ""
    @State private var shake = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
            TextField("Add a website", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused)
                .onSubmit(submit)
            if !text.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.indigo)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(shake ? Color.red.opacity(0.6) : .clear, lineWidth: 1)
        )
        .offset(x: shake ? 6 : 0)
        .animation(.snappy(duration: 0.15), value: text.isEmpty)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        if model.add(text) {
            withAnimation(.smooth) { text = "" }
        } else {
            withAnimation(.spring(response: 0.15, dampingFraction: 0.2)) { shake = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.smooth) { shake = false }
            }
        }
    }
}

private struct DomainList: View {
    @Environment(BlockerModel.self) private var model

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(model.domains, id: \.self) { domain in
                    DomainRow(domain: domain, blocking: model.isBlocking) {
                        withAnimation(.smooth) { model.remove(domain) }
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
            .animation(.smooth, value: model.domains)
        }
        .scrollIndicators(.never)
    }
}

private struct DomainRow: View {
    let domain: String
    let blocking: Bool
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            Text(domain.prefix(1).uppercased())
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .saturation(blocking ? 1 : 0.2)
            Text(domain)
                .font(.system(size: 14))
                .foregroundStyle(blocking ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.quaternary, in: Circle())
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(hovering ? AnyShapeStyle(.quaternary.opacity(0.5)) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Remove", role: .destructive, action: onRemove)
        }
    }

    /// Stable color per domain.
    private var tint: Color {
        let palette: [Color] = [.indigo, .pink, .orange, .teal, .purple, .blue, .mint, .red]
        let hash = domain.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return palette[hash % palette.count]
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "globe")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No websites yet")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Setup

private struct SetupView: View {
    @Environment(BlockerModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 54, weight: .light))
                .foregroundStyle(.indigo.gradient)
            VStack(spacing: 6) {
                Text("One-time setup")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text("Allow Disciplined to block sites\nin every browser.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                Task { await model.setUp() }
            } label: {
                Group {
                    if model.isWorking {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Continue")
                    }
                }
                .frame(width: 140, height: 22)
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
            .controlSize(.large)
            .disabled(model.isWorking)

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
            Text("You'll be asked for your password once.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
    }
}
