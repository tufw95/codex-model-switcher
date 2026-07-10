import AppKit
import CodexModelSwitcherCore
import SwiftUI

struct CompactSwitchView: View {
    @EnvironmentObject private var app: AppState

    private var usingNineRouter: Bool {
        app.status.activeProvider == "NineRouter"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "switch.2")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        LinearGradient(
                            colors: [Color(red: 0.05, green: 0.46, blue: 0.63), Color(red: 0.12, green: 0.65, blue: 0.42)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Codex Switch")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text(usingNineRouter ? "9Router is active" : "Authentic Codex is active")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(usingNineRouter ? "9Router" : "Codex")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(usingNineRouter ? Color.green : Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("CHOOSE MODE")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    ModeButton(
                        title: "9Router",
                        subtitle: "Team API",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        isActive: usingNineRouter,
                        isBusy: app.isBusy
                    ) {
                        app.switchToNineRouter()
                    }

                    ModeButton(
                        title: "Authentic",
                        subtitle: "OpenAI",
                        systemImage: "sparkles",
                        isActive: !usingNineRouter,
                        isBusy: app.isBusy
                    ) {
                        app.switchToAuthenticCodex()
                    }
                }
            }

            if app.isBusy {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text(app.statusMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else if let error = app.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(3)
            } else {
                Text(app.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            HStack {
                Text("Models sync automatically")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(22)
        .background(.regularMaterial)
    }
}

struct ModeButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let isActive: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .semibold))
                Text(title)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(isActive ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 108)
            .background(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? Color.clear : Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }
}

struct ContentView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            HeaderView()
            Divider()
            HStack(spacing: 0) {
                ModelListView()
                    .frame(width: 310)
                Divider()
                ControlPanelView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            FooterView()
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert("Codex Model Switcher", isPresented: Binding(
            get: { app.errorMessage != nil },
            set: { if !$0 { app.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { app.errorMessage = nil }
        } message: {
            Text(app.errorMessage ?? "")
        }
    }
}

struct HeaderView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "switch.2")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.05, green: 0.45, blue: 0.58), Color(red: 0.10, green: 0.58, blue: 0.40)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Codex Model Switcher")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("Smart 9Router bridge for Codex on macOS")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StatusPill(
                title: app.status.proxyHealthy ? "Proxy online" : "Proxy stopped",
                systemImage: app.status.proxyHealthy ? "checkmark.seal.fill" : "pause.circle",
                tint: app.status.proxyHealthy ? .green : .secondary
            )

            if app.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
        .background(.regularMaterial)
    }
}

struct ModelListView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Models")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(app.models) { model in
                        ModelRow(model: model, isSelected: app.selectedModelID == model.codexSlug)
                            .onTapGesture {
                                app.selectedModelID = model.codexSlug
                            }
                    }
                }
                .padding(.vertical, 2)
            }

            HStack(spacing: 8) {
                TextField("gpt 5.6", text: $app.newModelName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { app.addModel() }
                Button {
                    app.addModel()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add model")
            }

            HStack {
                Button {
                    app.refreshModelsFromRouter()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(app.isBusy)

                Spacer()

                Button(role: .destructive) {
                    app.removeSelectedModel()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Remove selected model")
                .disabled(app.models.count <= 1)
            }
        }
        .padding(18)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct ModelRow: View {
    @EnvironmentObject private var app: AppState
    let model: RouterModel
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: model.visible ? "eye.fill" : "eye.slash")
                .foregroundStyle(model.visible ? Color.teal : Color.secondary)
                .frame(width: 20)
                .onTapGesture {
                    app.toggleVisibility(for: model)
                }
                .help(model.visible ? "Visible in Codex picker" : "Hidden in Codex picker")

            VStack(alignment: .leading, spacing: 3) {
                Text(model.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text("\(model.codexSlug) -> \(model.upstreamModel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
        }
        .padding(10)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }
}

struct ControlPanelView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                UpdateBanner()
                StatusGrid()
                SwitchPanel()
                RouterSettingsPanel()
                UpdateSettingsPanel()
            }
            .padding(22)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.45))
    }
}

struct StatusGrid: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
            GridRow {
                StatusTile(
                    title: "Codex CLI",
                    value: app.status.codexCLIPath == nil ? "Not found" : "Ready",
                    systemImage: "terminal",
                    tint: app.status.codexCLIPath == nil ? .orange : .green
                )
                StatusTile(
                    title: "API Key",
                    value: app.status.apiKeyAvailable ? "Saved" : "Missing",
                    systemImage: "key.fill",
                    tint: app.status.apiKeyAvailable ? .green : .orange
                )
            }
            GridRow {
                StatusTile(
                    title: "Provider",
                    value: app.status.activeProvider ?? "OpenAI",
                    systemImage: "network",
                    tint: app.status.activeProvider == "NineRouter" ? .teal : .blue
                )
                StatusTile(
                    title: "Active Model",
                    value: app.status.activeModel ?? "Unknown",
                    systemImage: "cpu",
                    tint: .indigo
                )
            }
        }
    }
}

struct StatusTile: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SwitchPanel: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Switch", systemImage: "bolt.horizontal")

            HStack(spacing: 12) {
                Button {
                    app.runSafetyCheck()
                } label: {
                    Label("Safety Check", systemImage: "checkmark.shield")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(app.isBusy)

                Button {
                    app.switchToNineRouter()
                } label: {
                    Label("Use 9Router", systemImage: "point.3.connected.trianglepath.dotted")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(app.isBusy)

                Button {
                    app.switchToAuthenticCodex()
                } label: {
                    Label("Use Authentic Codex", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(app.isBusy)

                Button {
                    app.stopProxy()
                } label: {
                    Image(systemName: "stop.circle")
                }
                .controlSize(.large)
                .help("Stop proxy")
            }

            Text("Selected: \(app.selectedModel.displayName)")
                .foregroundStyle(.secondary)

            if let report = app.preflightReport {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(report.checks.enumerated()), id: \.offset) { _, check in
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: check.status))
                                .foregroundStyle(color(for: check.status))
                                .frame(width: 18)
                            Text(check.title)
                                .font(.system(size: 12, weight: .semibold))
                            Text(check.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
        .panelStyle()
    }

    private func icon(for status: PreflightCheck.Status) -> String {
        switch status {
        case .passed: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    private func color(for status: PreflightCheck.Status) -> Color {
        switch status {
        case .passed: .green
        case .warning: .orange
        case .failed: .red
        }
    }
}

struct RouterSettingsPanel: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "9Router", systemImage: "slider.horizontal.3")

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("API Key")
                        .foregroundStyle(.secondary)
                    SecureField("NINEROUTER_API_KEY", text: $app.apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        app.saveAPIKey()
                    } label: {
                        Image(systemName: "externaldrive.badge.checkmark")
                    }
                    .help("Save API key")
                }
                GridRow {
                    Text("Router URL")
                        .foregroundStyle(.secondary)
                    TextField("https://9router.bigroll.vn", text: $app.routerTarget)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        app.refreshStatus()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh status")
                }
            }

            if let path = app.status.codexCLIPath {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .panelStyle()
    }
}

struct UpdateSettingsPanel: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(title: "Updates", systemImage: "square.and.arrow.down")

            Toggle("Check for updates on launch", isOn: $app.updateSettings.checkOnLaunch)
                .onChange(of: app.updateSettings.checkOnLaunch) { _ in
                    app.saveUpdateSettings()
                }

            HStack(spacing: 8) {
                TextField("Manifest URL", text: $app.updateSettings.manifestURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { app.saveUpdateSettings() }
                Button {
                    app.saveUpdateSettings()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save update manifest URL")
                Button {
                    Task { await app.checkForUpdates() }
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .help("Check now")
            }
        }
        .panelStyle()
    }
}

struct UpdateBanner: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        if let manifest = app.updateManifest {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.app.fill")
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Version \(manifest.version) is available")
                        .font(.headline)
                    Text(manifest.message ?? "Download the latest build when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    app.openUpdateDownload()
                } label: {
                    Label("Download", systemImage: "arrow.down")
                }
            }
            .padding(12)
            .background(Color.teal.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct FooterView: View {
    @EnvironmentObject private var app: AppState

    var body: some View {
        HStack {
            Text(app.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("v\(app.currentVersion)")
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}

struct MenuContentView: View {
    @EnvironmentObject private var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Switcher") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        }
        Divider()
        Picker("Model", selection: $app.selectedModelID) {
            ForEach(app.models) { model in
                Text(model.displayName).tag(model.codexSlug)
            }
        }
        Button("Use 9Router") {
            app.switchToNineRouter()
        }
        Button("Use Authentic Codex") {
            app.switchToAuthenticCodex()
        }
        Button("Check for Updates") {
            Task { await app.checkForUpdates() }
        }
        Divider()
        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }
}

struct SectionTitle: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.teal)
            Text(title)
                .font(.headline)
        }
    }
}

struct StatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

private extension View {
    func panelStyle() -> some View {
        self
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            )
    }
}
