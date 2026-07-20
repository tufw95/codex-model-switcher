import AppKit
import CodexModelSwitcherCore
import SwiftUI

struct CompactSwitchView: View {
    @EnvironmentObject private var app: AppState
    @State private var editingAPIKey = false

    private var usingNineRouter: Bool {
        app.status.activeProvider == "NineRouter"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(nsImage: BrandAssets.appIcon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Codex Switch")
                        .font(.system(size: 15, weight: .semibold))
                    Text(usingNineRouter ? "Routing through 9Router" : "Using authentic Codex")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(usingNineRouter ? Color.green : Color.blue)
                    .frame(width: 8, height: 8)
            }

            if !app.status.apiKeyAvailable || editingAPIKey {
                VStack(alignment: .leading, spacing: 8) {
                    Text("9Router API key")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SecureField("Paste API key once", text: $app.apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            app.saveAPIKey()
                            if app.errorMessage == nil {
                                editingAPIKey = false
                            }
                        }

                    HStack {
                        Text("Stored locally on this Mac")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Save") {
                            app.saveAPIKey()
                            if app.errorMessage == nil {
                                editingAPIKey = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(app.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Mode")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 6) {
                    ModeButton(
                        title: "9Router",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        isActive: usingNineRouter,
                        isBusy: app.isBusy
                    ) {
                        app.switchToNineRouter()
                    }

                    ModeButton(
                        title: "Authentic",
                        systemImage: "sparkles",
                        isActive: !usingNineRouter,
                        isBusy: app.isBusy
                    ) {
                        app.switchToAuthenticCodex()
                    }
                }
            }

            if app.status.apiKeyAvailable && app.quotaFeatureAvailable {
                QuotaSection()
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

            HStack(spacing: 8) {
                Text(app.status.apiKeyAvailable ? "API key saved locally" : "API key required for 9Router")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if app.status.apiKeyAvailable && !editingAPIKey {
                    Button("Change Key") {
                        app.apiKeyInput = ""
                        editingAPIKey = true
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }

            if let update = app.updateManifest {
                Button {
                    app.installAvailableUpdate()
                } label: {
                    HStack(spacing: 7) {
                        if app.isInstallingUpdate {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        }
                        Text(app.isInstallingUpdate ? "Installing v\(update.version)" : "Install v\(update.version)")
                            .font(.system(size: 12, weight: .semibold))
                        Spacer()
                        if !app.isInstallingUpdate {
                            Image(systemName: "arrow.up.forward.app")
                                .font(.caption2)
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(app.isInstallingUpdate)
            }

            HStack(spacing: 10) {
                Text(app.versionLabel)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    Task {
                        await app.checkForUpdates(force: true)
                    }
                } label: {
                    if app.isCheckingForUpdates {
                        ProgressView()
                            .controlSize(.mini)
                            .frame(width: 82)
                    } else {
                        Label("Check Update", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(app.isCheckingForUpdates)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Quit Codex Switch")
            }
        }
        .padding(14)
        .background(.regularMaterial)
    }
}

struct QuotaSection: View {
    @EnvironmentObject private var app: AppState
    private let columns = [
        GridItem(.flexible(), spacing: 14, alignment: .top),
        GridItem(.flexible(), spacing: 14, alignment: .top),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Label("Quota", systemImage: "gauge.with.dots.needle.67percent")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let summary = app.quotaSummary {
                    Text("\(summary.availableAccounts)/\(summary.accounts)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Button {
                    app.refreshQuota()
                } label: {
                    if app.isRefreshingQuota {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Refresh quota")
                .disabled(app.isRefreshingQuota)
            }

            if let error = app.quotaErrorMessage {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            } else if app.isRefreshingQuota && app.quotaAccounts.isEmpty {
                ProgressView("Loading quota")
                    .controlSize(.small)
                    .font(.caption2)
            } else if app.quotaAccounts.isEmpty {
                Text("No active Codex accounts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(app.quotaAccounts) { account in
                        QuotaAccountRow(account: account)
                    }
                }
            }
        }
        .padding(9)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct QuotaAccountRow: View {
    let account: CodexQuotaAccount

    private var quota: CodexQuotaWindow? {
        account.primaryQuota
    }

    private var remainingColor: Color {
        guard let remaining = quota?.remaining else { return .secondary }
        if remaining <= 20 { return .red }
        if remaining <= 50 { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(remainingColor)
                    .frame(width: 6, height: 6)
                Text(account.label)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .help(account.label)
                Spacer(minLength: 4)
                if let quota {
                    Text("\(Int(quota.remaining.rounded()))%")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(remainingColor)
                } else {
                    Text("Unavailable")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let quota {
                HStack(spacing: 7) {
                    ProgressView(value: quota.remaining, total: max(quota.total, 1))
                        .progressViewStyle(.linear)
                        .tint(remainingColor)

                    if let resetAt = quota.resetAt {
                        Text(resetLabel(resetAt))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 42, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func resetLabel(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            return ""
        }
        let interval = date.timeIntervalSinceNow
        if interval <= 0 {
            return "now"
        }
        let seconds = Int(interval)
        let minutes = seconds / 60
        if minutes < 60 {
            return "in \(max(1, minutes))m"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "in \(hours)h"
        }
        return "in \(hours / 24)d"
    }
}

struct ModeButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let isBusy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(isActive ? .white : .primary)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(isActive ? Color.accentColor : Color(nsColor: .controlBackgroundColor).opacity(0.9))
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
            Image(nsImage: BrandAssets.appIcon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 52, height: 52)

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
                        .onSubmit { app.saveRouterTarget() }
                    Button {
                        app.saveRouterTarget()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Save router URL")
                }
            }

            Text("HTTPS is required except for localhost development. Your API key is sent to this router.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
                    Text(manifest.message ?? "Install the latest build when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    app.installAvailableUpdate()
                } label: {
                    if app.isInstallingUpdate {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("Install Update", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(app.isInstallingUpdate)
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
        if let update = app.updateManifest {
            Button("Install Update v\(update.version)") {
                app.installAvailableUpdate()
            }
            .disabled(app.isInstallingUpdate)
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
