import AppKit
import CodexModelSwitcherCore
import Foundation
import ServiceManagement
import SwiftUI
import UserNotifications

@MainActor
final class AppState: ObservableObject {
    @Published var models: [RouterModel] = []
    @Published var selectedModelID: String = "gpt-5.5"
    @Published var status = RuntimeStatus(
        codexCLIPath: nil,
        apiKeyAvailable: false,
        proxyHealthy: false,
        activeProvider: nil,
        activeModel: nil
    )
    @Published var apiKeyInput = ""
    @Published var newModelName = ""
    @Published var isBusy = false
    @Published var isCheckingForUpdates = false
    @Published var isInstallingUpdate = false
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?
    @Published var updateSettings: UpdateSettings
    @Published var updateManifest: UpdateManifest?
    @Published var preflightReport: PreflightReport?
    @Published var routerTarget = "https://9router.bigroll.vn"
    @Published var quotaAccounts: [CodexQuotaAccount] = []
    @Published var quotaSummary: CodexQuotaSummary?
    @Published var quotaErrorMessage: String?
    @Published var isRefreshingQuota = false
    @Published var quotaFeatureAvailable = true

    private let registry: ModelRegistryStore
    private var codexService: CodexService
    private let quotaService: QuotaService
    private let updateService: UpdateService
    private let updateInstaller: UpdateInstaller
    private let teamPreset: TeamPreset
    private var didBootstrap = false
    private var updateMonitorTask: Task<Void, Never>?
    private var modelMonitorTask: Task<Void, Never>?
    private var quotaMonitorTask: Task<Void, Never>?

    init(
        registry: ModelRegistryStore = ModelRegistryStore(),
        codexService: CodexService = CodexService(),
        quotaService: QuotaService = QuotaService(),
        updateService: UpdateService = UpdateService(),
        updateInstaller: UpdateInstaller = UpdateInstaller()
    ) {
        self.registry = registry
        self.codexService = codexService
        self.quotaService = quotaService
        self.updateService = updateService
        self.updateInstaller = updateInstaller
        self.teamPreset = TeamPreset.load()
        var loadedUpdateSettings = updateService.loadSettings()
        if let bundledURL = teamPreset.updateManifestURL,
           loadedUpdateSettings.manifestURL == UpdateSettings().manifestURL {
            loadedUpdateSettings.manifestURL = bundledURL
        }
        self.updateSettings = loadedUpdateSettings
        let initialRouterURL = RouterTargetSettings.load(bundledValue: teamPreset.routerTargetURL)
        self.routerTarget = initialRouterURL.absoluteString
        if let url = try? RouterEndpoint.normalizedURL(from: self.routerTarget) {
            self.codexService = CodexService(routerTargetURL: url)
        }
        load()
        Task {
            await bootstrapOnLaunch()
        }
    }

    var selectedModel: RouterModel {
        models.first(where: { $0.codexSlug == selectedModelID }) ?? models.first ?? RouterModel.defaults[0]
    }

    var preferredNineRouterModel: RouterModel {
        if let visible = models.filter(\.visible).sorted(by: { $0.priority < $1.priority }).first {
            return visible
        }
        if let combo = models.first(where: { $0.notes == "9Router Combo" }) {
            return combo
        }
        return selectedModel
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var currentBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    var versionLabel: String {
        "v\(currentVersion)"
    }

    func load() {
        do {
            let loaded = try registry.load()
            let enriched = CodexModelCatalog.applyingOfficialMetadata(
                to: loaded,
                codexCLI: codexService.detectCodexCLI()
            )
            models = enriched
            if enriched != loaded {
                try registry.save(enriched)
            }
            if !models.contains(where: { $0.codexSlug == selectedModelID }) {
                selectedModelID = models.first?.codexSlug ?? "gpt-5.5"
            }
            apiKeyInput = codexService.readAPIKey().map(maskKey) ?? ""
            refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func bootstrapOnLaunch() async {
        guard !didBootstrap else {
            return
        }
        didBootstrap = true
        configureLaunchAtLogin()
        requestUpdateNotificationAuthorization()
        await checkForUpdates(silent: true, force: true)
        startPeriodicUpdateChecks()
        startPeriodicQuotaSync()
        await loadQuota(silent: true, forceRefresh: false)
        guard teamPreset.autoRefreshModelsOnLaunch else {
            return
        }
        startPeriodicModelSync()
        await refreshModelsFromRouter(silent: true)
    }

    func refreshStatus() {
        status = codexService.status()
        statusMessage = status.proxyHealthy ? "9Router proxy is running" : "Proxy is stopped"
    }

    func saveAPIKey() {
        let value = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("...") else {
            errorMessage = "Paste the full 9Router API key before saving."
            return
        }

        run("Saving API key") {
            try codexService.saveAPIKey(value)
            return "API key saved to ~/.codex/.env"
        }
        if errorMessage == nil {
            Task {
                await loadQuota(silent: true, forceRefresh: true)
            }
        }
    }

    func saveRouterTarget() {
        do {
            let url = try RouterTargetSettings.save(routerTarget)
            routerTarget = url.absoluteString
            codexService = CodexService(routerTargetURL: url)
            statusMessage = "Router URL saved"
            errorMessage = nil
            refreshStatus()
            Task {
                await loadQuota(silent: true, forceRefresh: true)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addModel() {
        let value = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }

        do {
            models = try registry.upsert(rawModelName: value)
            selectedModelID = RouterModel.inferred(from: value).codexSlug
            newModelName = ""
            statusMessage = "Added \(selectedModel.displayName)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func removeSelectedModel() {
        guard models.count > 1 else {
            return
        }
        models.removeAll { $0.codexSlug == selectedModelID }
        selectedModelID = models.first?.codexSlug ?? "gpt-5.5"
        do {
            try registry.save(models)
            statusMessage = "Model removed"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleVisibility(for model: RouterModel) {
        guard let index = models.firstIndex(of: model) else {
            return
        }
        models[index].visible.toggle()
        models[index].visibilityOverride = models[index].visible
        do {
            try registry.save(models)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshModelsFromRouter() {
        Task {
            await refreshModelsFromRouter(silent: false)
        }
    }

    func refreshQuota() {
        Task {
            await loadQuota(silent: false, forceRefresh: true)
        }
    }

    private func loadQuota(silent: Bool, forceRefresh: Bool) async {
        guard !isRefreshingQuota else {
            return
        }
        guard let apiKey = codexService.readAPIKey(), !apiKey.isEmpty else {
            quotaAccounts = []
            quotaSummary = nil
            quotaErrorMessage = nil
            return
        }

        let targetURL: URL
        do {
            targetURL = try RouterEndpoint.normalizedURL(from: routerTarget)
        } catch {
            if !silent {
                quotaErrorMessage = error.localizedDescription
            }
            return
        }

        isRefreshingQuota = true
        defer { isRefreshingQuota = false }
        do {
            let response = try await quotaService.fetch(
                apiKey: apiKey,
                targetBaseURL: targetURL,
                forceRefresh: forceRefresh
            )
            quotaAccounts = response.data
            quotaSummary = response.summary
            quotaErrorMessage = nil
            quotaFeatureAvailable = true
        } catch QuotaServiceError.unsupported {
            quotaAccounts = []
            quotaSummary = nil
            quotaErrorMessage = nil
            quotaFeatureAvailable = false
        } catch {
            quotaFeatureAvailable = true
            if !silent || quotaAccounts.isEmpty {
                quotaErrorMessage = error.localizedDescription
            }
        }
    }

    private func refreshModelsFromRouter(silent: Bool, showProgress: Bool = true) async {
        guard let key = codexService.readAPIKey(), !key.isEmpty else {
            if !silent {
                errorMessage = "Save your 9Router API key first, then refresh models."
            }
            return
        }
        let url: URL
        do {
            url = try RouterEndpoint.normalizedURL(from: routerTarget)
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
            }
            return
        }

        if showProgress {
            isBusy = true
            statusMessage = "Refreshing models from 9Router"
        }
        do {
            let previousSlugs = Set(models.map(\.codexSlug))
            let routerModels = try await registry.refreshFromRouter(apiKey: key, targetBaseURL: url)
            let fresh = CodexModelCatalog.applyingOfficialMetadata(
                to: routerModels,
                codexCLI: codexService.detectCodexCLI()
            )
            try registry.save(fresh)
            models = fresh
            try codexService.writeModelCatalog(models: fresh)
            if !models.contains(where: { $0.codexSlug == selectedModelID }) {
                selectedModelID = models.first(where: \.visible)?.codexSlug
                    ?? models.first?.codexSlug
                    ?? selectedModelID
            }
            if !silent {
                let addedCount = Set(fresh.map(\.codexSlug)).subtracting(previousSlugs).count
                statusMessage = addedCount > 0
                    ? "Added \(addedCount) new 9Router model\(addedCount == 1 ? "" : "s")"
                    : "Model list is up to date"
            }
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
            }
            statusMessage = silent ? "Ready" : "Refresh failed"
        }
        if showProgress {
            isBusy = false
        }
        refreshStatus()
    }

    func switchToNineRouter() {
        let url: URL
        do {
            url = try RouterTargetSettings.save(routerTarget)
            routerTarget = url.absoluteString
            codexService = CodexService(routerTargetURL: url)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Switch failed"
            return
        }
        Task {
            isBusy = true
            statusMessage = "Preparing 9Router"
            await refreshModelsFromRouter(silent: true, showProgress: false)
            let apiKey = apiKeyInput.contains("...") ? codexService.readAPIKey() : apiKeyInput
            let model = preferredNineRouterModel
            let allModels = models
            do {
                try codexService.switchToNineRouter(selectedModel: model, allModels: allModels, apiKey: apiKey)
                selectedModelID = model.codexSlug
                statusMessage = "Codex is now using 9Router: \(model.displayName)"
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Switch failed"
            }
            isBusy = false
            refreshStatus()
        }
    }

    func runSafetyCheck() {
        do {
            let url = try RouterEndpoint.normalizedURL(from: routerTarget)
            codexService = CodexService(routerTargetURL: url)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Safety check failed"
            return
        }
        let apiKey = apiKeyInput.contains("...") ? codexService.readAPIKey() : apiKeyInput
        preflightReport = codexService.validateNineRouterSetup(
            selectedModel: selectedModel,
            allModels: models,
            apiKey: apiKey
        )
        statusMessage = preflightReport?.summary ?? "Safety check finished"
    }

    func switchToAuthenticCodex() {
        run("Switching Codex to authentic provider") {
            try codexService.switchToAuthenticCodex()
            return "Codex is now using the authentic provider"
        }
    }

    func stopProxy() {
        codexService.stopProxy()
        refreshStatus()
    }

    func saveUpdateSettings() {
        do {
            try updateService.saveSettings(updateSettings)
            statusMessage = "Update settings saved"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func checkForUpdates(silent: Bool = false, force: Bool = false) async {
        if !silent {
            isCheckingForUpdates = true
        }
        defer {
            if !silent {
                isCheckingForUpdates = false
            }
        }

        do {
            var settings = updateSettings
            if force {
                settings.checkOnLaunch = true
            }
            let result = try await updateService.check(currentVersion: currentVersion, settings: settings)
            switch result {
            case .disabled:
                if !silent {
                    statusMessage = "Update checks are disabled"
                }
            case .upToDate:
                updateManifest = nil
                if !silent {
                    statusMessage = "You are on the latest version"
                }
            case let .available(manifest):
                updateManifest = manifest
                statusMessage = "Update \(manifest.version) is available"
                notifyUpdate(manifest)
            }
        } catch {
            if !silent {
                errorMessage = error.localizedDescription
            }
        }
    }

    func installAvailableUpdate() {
        guard let manifest = updateManifest, !isInstallingUpdate else {
            return
        }
        Task {
            isInstallingUpdate = true
            isBusy = true
            errorMessage = nil
            statusMessage = "Downloading update \(manifest.version)"

            do {
                let plan = try await updateInstaller.prepareInstallation(
                    manifest: manifest,
                    currentAppURL: Bundle.main.bundleURL,
                    expectedBundleIdentifier: Bundle.main.bundleIdentifier ?? "vn.bigroll.codex-model-switcher"
                )
                statusMessage = plan.requiresAdministratorPrivileges
                    ? "Waiting for macOS permission"
                    : "Installing and restarting"
                try updateInstaller.launchInstallation(
                    plan,
                    currentProcessID: ProcessInfo.processInfo.processIdentifier
                )
                try? await Task.sleep(nanoseconds: 250_000_000)
                NSApplication.shared.terminate(nil)
            } catch {
                errorMessage = error.localizedDescription
                statusMessage = "Update failed"
                isInstallingUpdate = false
                isBusy = false
            }
        }
    }

    private func run(_ message: String, operation: () throws -> String) {
        isBusy = true
        errorMessage = nil
        statusMessage = message
        do {
            let success = try operation()
            statusMessage = success
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Action failed"
        }
        isBusy = false
        refreshStatus()
    }

    private func notifyUpdate(_ manifest: UpdateManifest) {
        let notificationKey = "lastNotifiedUpdateVersion"
        if UserDefaults.standard.string(forKey: notificationKey) == manifest.version {
            return
        }

        Task.detached(priority: .utility) {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else {
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Codex Model Switcher \(manifest.version)"
            content.body = manifest.message ?? "A new version is ready to install."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "codex-model-switcher-update-\(manifest.version)",
                content: content,
                trigger: nil
            )
            do {
                try await center.add(request)
                UserDefaults.standard.set(manifest.version, forKey: notificationKey)
            } catch {
                return
            }
        }
    }

    private func configureLaunchAtLogin() {
        guard #available(macOS 13.0, *),
              Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            return
        }
        guard SMAppService.mainApp.status == .notRegistered else {
            return
        }
        try? SMAppService.mainApp.register()
    }

    private func requestUpdateNotificationAuthorization() {
        Task.detached(priority: .utility) {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func startPeriodicUpdateChecks() {
        guard updateMonitorTask == nil else {
            return
        }
        updateMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6 * 60 * 60 * 1_000_000_000)
                guard !Task.isCancelled, let self else {
                    return
                }
                await self.checkForUpdates(silent: true, force: true)
            }
        }
    }

    private func startPeriodicModelSync() {
        guard modelMonitorTask == nil else {
            return
        }
        modelMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                guard !Task.isCancelled, let self else {
                    return
                }
                await self.refreshModelsFromRouter(silent: true, showProgress: false)
            }
        }
    }

    private func startPeriodicQuotaSync() {
        guard quotaMonitorTask == nil else {
            return
        }
        quotaMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2 * 60 * 1_000_000_000)
                guard !Task.isCancelled, let self else {
                    return
                }
                await self.loadQuota(silent: true, forceRefresh: false)
            }
        }
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 8 else {
            return key
        }
        return "\(key.prefix(4))...\(key.suffix(4))"
    }
}
