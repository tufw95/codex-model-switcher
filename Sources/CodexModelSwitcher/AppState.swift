import AppKit
import CodexModelSwitcherCore
import Foundation
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
    @Published var statusMessage = "Ready"
    @Published var errorMessage: String?
    @Published var updateSettings: UpdateSettings
    @Published var updateManifest: UpdateManifest?
    @Published var preflightReport: PreflightReport?
    @Published var routerTarget = "https://9router.bigroll.vn"

    private let registry: ModelRegistryStore
    private var codexService: CodexService
    private let updateService: UpdateService
    private let teamPreset: TeamPreset
    private var didBootstrap = false

    init(
        registry: ModelRegistryStore = ModelRegistryStore(),
        codexService: CodexService = CodexService(),
        updateService: UpdateService = UpdateService()
    ) {
        self.registry = registry
        self.codexService = codexService
        self.updateService = updateService
        self.teamPreset = TeamPreset.load()
        var loadedUpdateSettings = updateService.loadSettings()
        if let bundledURL = teamPreset.updateManifestURL,
           loadedUpdateSettings.manifestURL == UpdateSettings().manifestURL {
            loadedUpdateSettings.manifestURL = bundledURL
        }
        self.updateSettings = loadedUpdateSettings
        self.routerTarget = teamPreset.routerTargetURL
        if let url = URL(string: teamPreset.routerTargetURL) {
            self.codexService = CodexService(routerTargetURL: url)
        }
        applyTeamPresetIfNeeded()
        load()
        Task {
            await bootstrapOnLaunch()
        }
    }

    var selectedModel: RouterModel {
        models.first(where: { $0.codexSlug == selectedModelID }) ?? models.first ?? RouterModel.defaults[0]
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    func load() {
        do {
            models = try registry.load()
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
        await checkForUpdates(silent: true)
        guard teamPreset.autoRefreshModelsOnLaunch else {
            return
        }
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

    private func refreshModelsFromRouter(silent: Bool, showProgress: Bool = true) async {
        guard let key = codexService.readAPIKey(), !key.isEmpty else {
            if !silent {
                errorMessage = "Save your 9Router API key first, then refresh models."
            }
            return
        }
        guard let url = URL(string: routerTarget) else {
            if !silent {
                errorMessage = "Router URL is invalid."
            }
            return
        }

        if showProgress {
            isBusy = true
            statusMessage = "Refreshing models from 9Router"
        }
        do {
            let service = ModelRegistryStore()
            let fresh = try await service.refreshFromRouter(apiKey: key, targetBaseURL: url)
            models = fresh
            if !models.contains(where: { $0.codexSlug == selectedModelID }) {
                selectedModelID = models.first?.codexSlug ?? selectedModelID
            }
            statusMessage = "Model list refreshed"
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
        if let url = URL(string: routerTarget) {
            codexService = CodexService(routerTargetURL: url)
        }
        Task {
            isBusy = true
            statusMessage = "Preparing 9Router"
            await refreshModelsFromRouter(silent: true, showProgress: false)
            let apiKey = apiKeyInput.contains("...") ? codexService.readAPIKey() : apiKeyInput
            let model = selectedModel
            let allModels = models
            do {
                try codexService.switchToNineRouter(selectedModel: model, allModels: allModels, apiKey: apiKey)
                statusMessage = "Codex is now using 9Router"
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
        if let url = URL(string: routerTarget) {
            codexService = CodexService(routerTargetURL: url)
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
        let model = selectedModel
        run("Switching Codex to authentic provider") {
            try codexService.switchToAuthenticCodex(model: model)
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

    func checkForUpdates(silent: Bool = false) async {
        do {
            let result = try await updateService.check(currentVersion: currentVersion, settings: updateSettings)
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

    func openUpdateDownload() {
        guard let urlString = updateManifest?.downloadURL, let url = URL(string: urlString) else {
            return
        }
        NSWorkspace.shared.open(url)
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

    private func applyTeamPresetIfNeeded() {
        guard codexService.readAPIKey() == nil,
              let bundledKey = teamPreset.bundledAPIKey,
              !bundledKey.isEmpty else {
            return
        }
        try? codexService.saveAPIKey(bundledKey)
    }

    private func notifyUpdate(_ manifest: UpdateManifest) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Codex Model Switcher \(manifest.version)"
            content.body = manifest.message ?? "A new version is ready to download."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: "codex-model-switcher-update-\(manifest.version)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func maskKey(_ key: String) -> String {
        guard key.count > 8 else {
            return key
        }
        return "\(key.prefix(4))...\(key.suffix(4))"
    }
}
