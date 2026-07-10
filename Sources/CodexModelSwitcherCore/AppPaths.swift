import Foundation

public struct AppPaths: Sendable {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var codexHome: URL {
        home.appendingPathComponent(".codex", isDirectory: true)
    }

    public var defaultCodexConfig: URL {
        if let custom = ProcessInfo.processInfo.environment["CODEX_CONFIG_PATH"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        return codexHome.appendingPathComponent("config.toml")
    }

    public var codexEnvFile: URL {
        codexHome.appendingPathComponent(".env")
    }

    public var appSupport: URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Codex Model Switcher", isDirectory: true)
    }

    public var modelRegistry: URL {
        appSupport.appendingPathComponent("models.json")
    }

    public var updateSettings: URL {
        appSupport.appendingPathComponent("updates.json")
    }

    public var generatedModelCatalog: URL {
        codexHome.appendingPathComponent("9router-model-catalog.json")
    }

    public var launchAgents: URL {
        home
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
    }

    public var proxyLaunchAgent: URL {
        launchAgents.appendingPathComponent("com.bigroll.codex-model-switcher.proxy.plist")
    }

    public var legacyProxyLaunchAgent: URL {
        launchAgents.appendingPathComponent("com.codex.ninerouter-proxy.plist")
    }

    public var proxyLog: URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codex_model_switcher_9router_proxy.log")
    }

    public func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(at: codexHome, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: launchAgents, withIntermediateDirectories: true)
    }

}
