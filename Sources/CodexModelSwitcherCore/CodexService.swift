import Darwin
import Foundation

public struct RuntimeStatus: Equatable, Sendable {
    public var codexCLIPath: String?
    public var apiKeyAvailable: Bool
    public var proxyHealthy: Bool
    public var activeProvider: String?
    public var activeModel: String?

    public init(
        codexCLIPath: String?,
        apiKeyAvailable: Bool,
        proxyHealthy: Bool,
        activeProvider: String?,
        activeModel: String?
    ) {
        self.codexCLIPath = codexCLIPath
        self.apiKeyAvailable = apiKeyAvailable
        self.proxyHealthy = proxyHealthy
        self.activeProvider = activeProvider
        self.activeModel = activeModel
    }
}

public enum CodexServiceError: Error, LocalizedError {
    case missingAPIKey
    case missingProxyScript
    case proxyDidNotStart(logPath: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing 9Router API key. Paste it once and the app will save it to ~/.codex/.env."
        case .missingProxyScript:
            return "Could not locate the Codex Model Switcher executable for Swift proxy mode."
        case let .proxyDidNotStart(logPath):
            return "The local 9Router proxy did not start. See \(logPath)."
        }
    }
}

public final class CodexService {
    public let paths: AppPaths
    public let proxyPort: Int
    public let routerTargetURL: URL

    public init(
        paths: AppPaths = AppPaths(),
        proxyPort: Int = 9783,
        routerTargetURL: URL = URL(string: "https://9router.bigroll.vn")!
    ) {
        self.paths = paths
        self.proxyPort = proxyPort
        self.routerTargetURL = routerTargetURL
    }

    public var proxyBaseURL: String {
        "http://127.0.0.1:\(proxyPort)/v1"
    }

    public func status() -> RuntimeStatus {
        let config = (try? String(contentsOf: paths.defaultCodexConfig, encoding: .utf8)) ?? ""
        return RuntimeStatus(
            codexCLIPath: detectCodexCLI()?.path,
            apiKeyAvailable: !(readAPIKey() ?? "").isEmpty,
            proxyHealthy: isProxyHealthy(),
            activeProvider: topLevelValue("model_provider", in: config),
            activeModel: topLevelValue("model", in: config)
        )
    }

    public func switchToNineRouter(
        selectedModel: RouterModel,
        allModels: [RouterModel],
        apiKey: String?,
        openNewThread: Bool = true
    ) throws {
        try paths.ensureBaseDirectories()
        let key = normalizedAPIKey(apiKey ?? readAPIKey() ?? "")
        let preflight = validateNineRouterSetup(
            selectedModel: selectedModel,
            allModels: allModels,
            apiKey: key
        )
        guard preflight.canSwitch else {
            throw PreflightError.failed(preflight)
        }

        try saveAPIKey(key)
        let codexCLI = detectCodexCLI()
        try CodexModelCatalog.write(
            models: allModels,
            to: paths.generatedModelCatalog,
            codexCLI: codexCLI
        )
        try startProxy(allModels: allModels)
        try rewriteConfig(
            profile: .nineRouter,
            model: selectedModel,
            useChatGPTAuthentication: isChatGPTLoggedIn(codexCLI: codexCLI)
        )
        try repairNodeReplConfigIfPossible(codexCLI: codexCLI)
        try restartCodex(openNewThread: openNewThread, codexCLI: codexCLI)
    }

    public func validateNineRouterSetup(
        selectedModel: RouterModel,
        allModels: [RouterModel],
        apiKey: String?
    ) -> PreflightReport {
        var checks: [PreflightCheck] = []
        let key = normalizedAPIKey(apiKey ?? readAPIKey() ?? "")
        if key.isEmpty {
            checks.append(PreflightCheck(
                title: "9Router API key",
                message: "Missing 9Router API key.",
                status: .failed
            ))
        } else {
            checks.append(PreflightCheck(
                title: "9Router API key",
                message: "API key is available.",
                status: .passed
            ))
        }

        if let proxyExecutable = proxyExecutableURL(),
           FileManager.default.isExecutableFile(atPath: proxyExecutable.path) {
            checks.append(PreflightCheck(
                title: "Swift proxy",
                message: "Swift proxy executable is available.",
                status: .passed
            ))
        } else {
            checks.append(PreflightCheck(
                title: "Swift proxy",
                message: "Could not locate the app executable for proxy mode.",
                status: .failed
            ))
        }

        if detectCodexCLI() == nil {
            checks.append(PreflightCheck(
                title: "Codex CLI",
                message: "Codex CLI was not found. The app will still try the codex:// URL scheme.",
                status: .warning
            ))
        } else {
            checks.append(PreflightCheck(
                title: "Codex CLI",
                message: "Codex CLI is available.",
                status: .passed
            ))
        }

        if isChatGPTLoggedIn(codexCLI: detectCodexCLI()) {
            checks.append(PreflightCheck(
                title: "ChatGPT features",
                message: "ChatGPT sign-in is available for Scheduled, Plugins, Sites, and Chat.",
                status: .passed
            ))
        } else {
            checks.append(PreflightCheck(
                title: "ChatGPT features",
                message: "9Router will work, but ChatGPT cloud menu items require a ChatGPT sign-in.",
                status: .warning
            ))
        }

        if allModels.contains(where: { $0.codexSlug == selectedModel.codexSlug }) {
            checks.append(PreflightCheck(
                title: "Selected model",
                message: "\(selectedModel.codexSlug) maps to \(selectedModel.upstreamModel).",
                status: .passed
            ))
        } else {
            checks.append(PreflightCheck(
                title: "Selected model",
                message: "\(selectedModel.codexSlug) is not in the model registry.",
                status: .failed
            ))
        }

        do {
            _ = try CodexModelCatalog.buildData(
                models: allModels,
                existingCatalogURL: paths.generatedModelCatalog,
                codexCLI: detectCodexCLI()
            )
            checks.append(PreflightCheck(
                title: "Model catalog",
                message: "Codex model catalog can be generated.",
                status: .passed
            ))
        } catch {
            checks.append(PreflightCheck(
                title: "Model catalog",
                message: "Codex model catalog could not be generated: \(error.localizedDescription)",
                status: .failed
            ))
        }

        return PreflightReport(checks: checks)
    }

    public func switchToAuthenticCodex(
        model: RouterModel = RouterModel.inferred(from: "gpt-5.5"),
        openNewThread: Bool = true
    ) throws {
        try paths.ensureBaseDirectories()
        try rewriteConfig(profile: .authenticCodex, model: model)
        try repairNodeReplConfigIfPossible(codexCLI: detectCodexCLI())
        _ = try? Shell.run("/bin/launchctl", ["unsetenv", "NINEROUTER_API_KEY"], requireSuccess: false)
        stopProxy()
        try restartCodex(openNewThread: openNewThread, codexCLI: detectCodexCLI())
    }

    public func readAPIKey() -> String? {
        let envValue = normalizedAPIKey(ProcessInfo.processInfo.environment["NINEROUTER_API_KEY"] ?? "")
        if !envValue.isEmpty {
            return envValue
        }

        if let launchValue = try? Shell.run("/bin/launchctl", ["getenv", "NINEROUTER_API_KEY"], requireSuccess: false),
           launchValue.succeeded {
            let value = normalizedAPIKey(launchValue.stdout)
            if !value.isEmpty {
                return value
            }
        }

        return readAPIKeyFromEnvFile(paths.codexEnvFile)
    }

    public func saveAPIKey(_ key: String) throws {
        let cleanKey = normalizedAPIKey(key)
        guard !cleanKey.isEmpty else {
            throw CodexServiceError.missingAPIKey
        }

        try paths.ensureBaseDirectories()
        let existing = (try? String(contentsOf: paths.codexEnvFile, encoding: .utf8)) ?? ""
        let updated = updateEnv(existing: existing, key: cleanKey)
        try updated.write(to: paths.codexEnvFile, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: paths.codexEnvFile.path)
        try Shell.run("/bin/launchctl", ["setenv", "NINEROUTER_API_KEY", cleanKey], requireSuccess: false)
    }

    public func detectCodexCLI() -> URL? {
        let candidates = [
            paths.home.appendingPathComponent(".codex/packages/standalone/current/codex").path,
            "/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        if let which = try? Shell.run("/usr/bin/which", ["codex"], requireSuccess: false),
           which.succeeded {
            let path = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    public func isProxyHealthy() -> Bool {
        let result = try? Shell.run(
            "/usr/bin/curl",
            ["-fsS", "http://127.0.0.1:\(proxyPort)/health"],
            requireSuccess: false
        )
        return result?.succeeded == true
    }

    public func stopProxy() {
        let domain = launchDomain()
        _ = try? Shell.run("/bin/launchctl", ["bootout", domain, paths.proxyLaunchAgent.path], requireSuccess: false)
        _ = try? Shell.run("/bin/launchctl", ["bootout", domain, paths.legacyProxyLaunchAgent.path], requireSuccess: false)
        _ = try? Shell.run("/usr/bin/pkill", ["-f", "CodexModelSwitcher --proxy"], requireSuccess: false)
    }

    public func writeModelCatalog(models: [RouterModel]) throws {
        try CodexModelCatalog.write(
            models: models,
            to: paths.generatedModelCatalog,
            codexCLI: detectCodexCLI()
        )
    }

    @discardableResult
    public func migrateProxyToStrictRoutingIfNeeded(allModels: [RouterModel]) throws -> Bool {
        guard proxyUsesLegacyModelRouting() else {
            return false
        }
        try startProxy(allModels: allModels)
        return true
    }

    private func proxyUsesLegacyModelRouting() -> Bool {
        guard let data = try? Data(contentsOf: paths.proxyLaunchAgent),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let plist = object as? [String: Any],
              let arguments = plist["ProgramArguments"] as? [String] else {
            return false
        }
        return Self.requiresStrictRoutingMigration(arguments: arguments)
    }

    static func requiresStrictRoutingMigration(arguments: [String]) -> Bool {
        let legacyFlags = ["--fallback-to", "--rewrite-openai-models", "--rewrite-to", "--rewrite-from"]
        return !arguments.contains("--strict-model-routing")
            || legacyFlags.contains(where: arguments.contains)
    }

    private func startProxy(allModels: [RouterModel]) throws {
        guard let proxyExecutable = proxyExecutableURL(),
              FileManager.default.isExecutableFile(atPath: proxyExecutable.path) else {
            throw CodexServiceError.missingProxyScript
        }

        try writeProxyLaunchAgent(
            proxyExecutable: proxyExecutable,
            allModels: allModels
        )

        let domain = launchDomain()
        _ = try? Shell.run("/bin/launchctl", ["bootout", domain, paths.proxyLaunchAgent.path], requireSuccess: false)
        _ = try? Shell.run("/bin/launchctl", ["bootout", domain, paths.legacyProxyLaunchAgent.path], requireSuccess: false)
        _ = try? Shell.run("/usr/bin/pkill", ["-f", "CodexModelSwitcher --proxy"], requireSuccess: false)
        try Shell.run("/bin/launchctl", ["bootstrap", domain, paths.proxyLaunchAgent.path], requireSuccess: false)
        try Shell.run("/bin/launchctl", ["kickstart", "-k", "\(domain)/com.bigroll.codex-model-switcher.proxy"], requireSuccess: false)
        Thread.sleep(forTimeInterval: 1.0)

        guard isProxyHealthy() else {
            throw CodexServiceError.proxyDidNotStart(logPath: paths.proxyLog.path)
        }
    }

    private func writeProxyLaunchAgent(
        proxyExecutable: URL,
        allModels: [RouterModel]
    ) throws {
        let arguments = Self.strictProxyArguments(
            proxyExecutable: proxyExecutable,
            proxyPort: proxyPort,
            routerTargetURL: routerTargetURL,
            apiKeyFile: paths.codexEnvFile,
            modelRegistry: paths.modelRegistry,
            modelCatalog: paths.generatedModelCatalog,
            allModels: allModels
        )

        let plist: [String: Any] = [
            "Label": "com.bigroll.codex-model-switcher.proxy",
            "ProgramArguments": arguments,
            "RunAtLoad": true,
            "KeepAlive": true,
            "StandardOutPath": paths.proxyLog.path,
            "StandardErrorPath": paths.proxyLog.path
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(at: paths.launchAgents, withIntermediateDirectories: true)
        try data.write(to: paths.proxyLaunchAgent, options: .atomic)
    }

    static func strictProxyArguments(
        proxyExecutable: URL,
        proxyPort: Int,
        routerTargetURL: URL,
        apiKeyFile: URL,
        modelRegistry: URL,
        modelCatalog: URL,
        allModels: [RouterModel]
    ) -> [String] {
        var arguments = [
            proxyExecutable.path,
            "--proxy",
            "--port",
            String(proxyPort),
            "--target",
            routerTargetURL.absoluteString,
            "--api-key-file",
            apiKeyFile.path,
            "--model-registry",
            modelRegistry.path,
            "--strict-model-routing"
        ]

        for model in allModels {
            for input in model.rewriteInputs {
                arguments.append(contentsOf: ["--rewrite-map", "\(input)=\(model.upstreamModel)"])
            }
        }

        arguments.append(contentsOf: [
            "--model-catalog",
            modelCatalog.path
        ])
        return arguments
    }

    private func proxyExecutableURL() -> URL? {
        if let executable = Bundle.main.executableURL,
           FileManager.default.isExecutableFile(atPath: executable.path) {
            return executable
        }

        let argv0 = CommandLine.arguments.first ?? ""
        if !argv0.isEmpty, FileManager.default.isExecutableFile(atPath: argv0) {
            return URL(fileURLWithPath: argv0)
        }
        return nil
    }

    private func rewriteConfig(
        profile: CodexProfile,
        model: RouterModel,
        useChatGPTAuthentication: Bool = true
    ) throws {
        let configURL = paths.defaultCodexConfig
        try FileManager.default.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let backup = URL(fileURLWithPath: configURL.path + ".before-model-switcher")
        if !FileManager.default.fileExists(atPath: backup.path), !existing.isEmpty {
            try? existing.write(to: backup, atomically: true, encoding: .utf8)
        }

        let rewritten = CodexConfigRewriter.rewriteModelConfig(
            existing: existing,
            profile: profile,
            model: model,
            catalogPath: paths.generatedModelCatalog.path,
            proxyBaseURL: proxyBaseURL,
            reasoningEffort: model.reasoningEffort,
            useChatGPTAuthentication: useChatGPTAuthentication
        )
        try rewritten.write(to: configURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func repairNodeReplConfigIfPossible(codexCLI: URL?) throws {
        guard let config = detectNodeReplConfig(codexCLI: codexCLI) else {
            return
        }
        let configURL = paths.defaultCodexConfig
        let existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let rewritten = CodexConfigRewriter.rewriteNodeReplConfig(existing: existing, config: config)
        try rewritten.write(to: configURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private func detectNodeReplConfig(codexCLI: URL?) -> NodeReplConfig? {
        let resourceCandidates = codexResourceCandidates(codexCLI: codexCLI)
        for resources in resourceCandidates {
            let cuaNodeRepl = resources.appendingPathComponent("cua_node/bin/node_repl")
            let cuaNode = resources.appendingPathComponent("cua_node/bin/node")
            let flatNodeRepl = resources.appendingPathComponent("node_repl")
            let flatNode = resources.appendingPathComponent("node")

            let nodeRepl: URL
            let node: URL
            let moduleDirs: String
            if FileManager.default.isExecutableFile(atPath: cuaNodeRepl.path),
               FileManager.default.isExecutableFile(atPath: cuaNode.path) {
                nodeRepl = cuaNodeRepl
                node = cuaNode
                moduleDirs = resources.appendingPathComponent("cua_node/lib/node_modules").path
            } else if FileManager.default.isExecutableFile(atPath: flatNodeRepl.path),
                      FileManager.default.isExecutableFile(atPath: flatNode.path) {
                nodeRepl = flatNodeRepl
                node = flatNode
                moduleDirs = ""
            } else {
                continue
            }

            let browserClient = paths.home.appendingPathComponent(".codex/plugins/cache/openai-bundled/chrome/latest/scripts/browser-client.mjs")
            guard FileManager.default.fileExists(atPath: browserClient.path) else {
                continue
            }

            let sha = ((try? Shell.run("/usr/bin/shasum", ["-a", "256", browserClient.path]))?.stdout ?? "")
                .split(separator: " ")
                .first
                .map(String.init) ?? ""
            guard !sha.isEmpty else {
                continue
            }

            let version = browserClient
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                .lastPathComponent

            return NodeReplConfig(
                nodeReplPath: nodeRepl.path,
                nodePath: node.path,
                nodeModuleDirs: moduleDirs,
                browserClientSHA256s: sha,
                chromePluginVersion: version == "latest" ? "unknown" : version,
                codexCLIPath: (codexCLI ?? detectCodexCLI())?.path ?? ""
            )
        }
        return nil
    }

    private func codexResourceCandidates(codexCLI: URL?) -> [URL] {
        var candidates: [URL] = []
        if let codexCLI, codexCLI.path.contains(".app/Contents/Resources/") {
            candidates.append(codexCLI.deletingLastPathComponent())
        }
        candidates.append(URL(fileURLWithPath: "/Applications/Codex.app/Contents/Resources"))
        candidates.append(URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources"))
        var seen = Set<String>()
        return candidates.filter { url in
            guard !seen.contains(url.path) else { return false }
            seen.insert(url.path)
            return FileManager.default.fileExists(atPath: url.path)
        }
    }

    private func restartCodex(openNewThread: Bool, codexCLI: URL?) throws {
        let previouslyRunning = quitCodexApps()

        if let codexCLI {
            _ = try? Shell.run(codexCLI.path, ["app-server", "daemon", "restart"], requireSuccess: false)
            _ = try? Shell.run(codexCLI.path, ["app-server", "daemon", "start"], requireSuccess: false)
            _ = try? Shell.run(codexCLI.path, ["app-server", "daemon", "enable-remote-control"], requireSuccess: false)
            _ = try? Shell.run(codexCLI.path, ["remote-control", "start"], requireSuccess: false)
        }

        reopenCodexApp(previouslyRunning: previouslyRunning)
        waitForCodexAppToLaunch(timeout: 6.0)

        if openNewThread {
            _ = try? Shell.run("/usr/bin/open", ["codex://threads/new"], requireSuccess: false)
        }
    }

    private struct ManagedCodexApp {
        var processName: String
        var applicationName: String
        var bundleIdentifier: String?
        var applicationPath: String?
    }

    private var managedCodexApps: [ManagedCodexApp] {
        [
            ManagedCodexApp(
                processName: "ChatGPT",
                applicationName: "ChatGPT",
                bundleIdentifier: "com.openai.codex",
                applicationPath: "/Applications/ChatGPT.app"
            ),
            ManagedCodexApp(
                processName: "Codex",
                applicationName: "Codex",
                bundleIdentifier: nil,
                applicationPath: "/Applications/Codex.app"
            )
        ]
    }

    private func quitCodexApps() -> [ManagedCodexApp] {
        let running = runningCodexApps()
        for app in running {
            let target = app.bundleIdentifier.map { "id \"\($0)\"" } ?? "\"\(app.applicationName)\""
            _ = try? Shell.run(
                "/usr/bin/osascript",
                ["-e", "tell application \(target) to quit"],
                requireSuccess: false
            )
        }

        waitForCodexAppsToExit(timeout: 2.0)
        for app in running where isProcessRunning(app.processName) {
            _ = try? Shell.run("/usr/bin/killall", [app.processName], requireSuccess: false)
        }
        waitForCodexAppsToExit(timeout: 1.0)
        return running
    }

    private func reopenCodexApp(previouslyRunning: [ManagedCodexApp]) {
        var candidates = previouslyRunning + managedCodexApps
        var seen = Set<String>()
        candidates = candidates.filter { seen.insert($0.processName).inserted }

        for app in candidates {
            if let path = app.applicationPath,
               FileManager.default.fileExists(atPath: path),
               (try? Shell.run("/usr/bin/open", [path], requireSuccess: false).succeeded) == true {
                return
            }
            if let bundleIdentifier = app.bundleIdentifier,
               (try? Shell.run("/usr/bin/open", ["-b", bundleIdentifier], requireSuccess: false).succeeded) == true {
                return
            }
            if (try? Shell.run("/usr/bin/open", ["-a", app.applicationName], requireSuccess: false).succeeded) == true {
                return
            }
        }
    }

    private func runningCodexApps() -> [ManagedCodexApp] {
        managedCodexApps.filter { isProcessRunning($0.processName) }
    }

    private func isAnyCodexAppRunning() -> Bool {
        managedCodexApps.contains { isProcessRunning($0.processName) }
    }

    private func isProcessRunning(_ processName: String) -> Bool {
        let result = try? Shell.run("/usr/bin/pgrep", ["-x", processName], requireSuccess: false)
        return result?.succeeded == true
    }

    private func waitForCodexAppsToExit(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isAnyCodexAppRunning() {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func waitForCodexAppToLaunch(timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if isAnyCodexAppRunning() {
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    private func launchDomain() -> String {
        "gui/\(getuid())"
    }

    private func isChatGPTLoggedIn(codexCLI: URL?) -> Bool {
        guard let codexCLI,
              let result = try? Shell.run(codexCLI.path, ["login", "status"], requireSuccess: false),
              result.succeeded else {
            return false
        }
        return result.stdout.localizedCaseInsensitiveContains("Logged in using ChatGPT")
            || result.stderr.localizedCaseInsensitiveContains("Logged in using ChatGPT")
    }

    private func normalizedAPIKey(_ value: String) -> String {
        value.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }

    private func readAPIKeyFromEnvFile(_ url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        for line in content.components(separatedBy: .newlines) {
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard lowered.hasPrefix("ninerouter_api_key")
                || lowered.hasPrefix("nine_router_api_key")
                || lowered.hasPrefix("9router_api_key")
                || lowered.hasPrefix("ninerouter_token")
                || lowered.hasPrefix("nine_router_token")
                || lowered.hasPrefix("export ninerouter_api_key") else {
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                continue
            }
            let value = String(line[line.index(after: equals)...])
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? ""
            let clean = normalizedAPIKey(value)
            if !clean.isEmpty {
                return clean
            }
        }
        return nil
    }

    private func updateEnv(existing: String, key: String) -> String {
        var replaced = false
        var lines = existing.components(separatedBy: .newlines).map { line -> String in
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            let matches = lowered.hasPrefix("ninerouter_api_key")
                || lowered.hasPrefix("nine_router_api_key")
                || lowered.hasPrefix("9router_api_key")
                || lowered.hasPrefix("ninerouter_token")
                || lowered.hasPrefix("nine_router_token")
                || lowered.hasPrefix("export ninerouter_api_key")
            guard matches else {
                return line
            }
            replaced = true
            return "NINEROUTER_API_KEY=\(quoteEnv(key))"
        }

        if !replaced {
            if lines.last?.isEmpty == false {
                lines.append("")
            }
            lines.append("NINEROUTER_API_KEY=\(quoteEnv(key))")
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private func quoteEnv(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\""
    }

    private func topLevelValue(_ key: String, in config: String) -> String? {
        for line in config.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") {
                return nil
            }
            guard trimmed.hasPrefix("\(key)") else {
                continue
            }
            guard let equals = trimmed.firstIndex(of: "=") else {
                continue
            }
            return String(trimmed[trimmed.index(after: equals)...])
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"")))
        }
        return nil
    }
}
