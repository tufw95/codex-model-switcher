import Foundation

public enum CodexProfile: String, Codable, Sendable {
    case nineRouter
    case authenticCodex
}

public struct NodeReplConfig: Equatable, Sendable {
    public var nodeReplPath: String
    public var nodePath: String
    public var nodeModuleDirs: String
    public var browserClientSHA256s: String
    public var chromePluginVersion: String
    public var codexCLIPath: String

    public init(
        nodeReplPath: String,
        nodePath: String,
        nodeModuleDirs: String,
        browserClientSHA256s: String,
        chromePluginVersion: String,
        codexCLIPath: String
    ) {
        self.nodeReplPath = nodeReplPath
        self.nodePath = nodePath
        self.nodeModuleDirs = nodeModuleDirs
        self.browserClientSHA256s = browserClientSHA256s
        self.chromePluginVersion = chromePluginVersion
        self.codexCLIPath = codexCLIPath
    }
}

public enum CodexConfigRewriter {
    public static func rewriteModelConfig(
        existing: String,
        profile: CodexProfile,
        model: RouterModel,
        catalogPath: String,
        proxyBaseURL: String,
        reasoningEffort: String = "xhigh"
    ) -> String {
        var header: [String] = []
        switch profile {
        case .nineRouter:
            header.append("model_provider = \"NineRouter\"")
            header.append("model = \"\(escape(model.codexSlug))\"")
            header.append("model_catalog_json = \"\(escape(catalogPath))\"")
        case .authenticCodex:
            header.append("model = \"\(escape(model.codexSlug))\"")
        }
        header.append("model_reasoning_effort = \"\(escape(reasoningEffort))\"")

        let body = strip(
            existing: existing,
            topLevelKeys: ["model_provider", "model", "model_reasoning_effort", "model_catalog_json"],
            sections: ["model_providers.NineRouter"]
        )

        var output = header.joined(separator: "\n")
        if !body.isEmpty {
            output += "\n" + body
        }

        if profile == .nineRouter {
            output += """


            [model_providers.NineRouter]
            name = "9Router"
            base_url = "\(escape(proxyBaseURL))"
            env_key = "NINEROUTER_API_KEY"
            wire_api = "responses"
            """
        }
        return normalized(output)
    }

    public static func rewriteNodeReplConfig(existing: String, config: NodeReplConfig) -> String {
        let body = strip(
            existing: existing,
            topLevelKeys: [],
            sections: ["mcp_servers.node_repl", "mcp_servers.node_repl.env"]
        )

        var output = body
        if !output.isEmpty {
            output += "\n\n"
        }
        output += """
        [mcp_servers.node_repl]
        args = []
        command = "\(escape(config.nodeReplPath))"
        startup_timeout_sec = 120

        [mcp_servers.node_repl.env]
        NODE_REPL_NATIVE_PIPE_CONNECT_TIMEOUT_MS = "10000"
        NODE_REPL_NODE_MODULE_DIRS = "\(escape(config.nodeModuleDirs))"
        NODE_REPL_NODE_PATH = "\(escape(config.nodePath))"
        NODE_REPL_TRUSTED_CODE_PATHS = "\(escape(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path))"
        CODEX_HOME = "\(escape(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex").path))"
        NODE_REPL_TRUSTED_BROWSER_CLIENT_SHA256S = "\(escape(config.browserClientSHA256s))"
        BROWSER_USE_AVAILABLE_BACKENDS = "chrome,iab"
        NODE_REPL_INSTRUCTIONS_USE_CASE_BROWSER = "Control the in-app browser in conjunction with the Browser Plugin."
        NODE_REPL_INSTRUCTIONS_USE_CASE_CHROME = "Control the Chrome browser in conjunction with the Chrome Plugin. Prefer this method of controlling Chrome over alternatives (such as Computer Use) unless the user explicitly mentions an alternative."
        BROWSER_USE_CODEX_APP_BUILD_FLAVOR = "prod"
        BROWSER_USE_CODEX_APP_VERSION = "\(escape(config.chromePluginVersion))"
        CODEX_CLI_PATH = "\(escape(config.codexCLIPath))"
        """
        return normalized(output)
    }

    static func strip(existing: String, topLevelKeys: Set<String>, sections: Set<String>) -> String {
        let lines = existing.components(separatedBy: .newlines)
        var kept: [String] = []
        var currentSection: String?
        var skippingSection = false

        for line in lines {
            if let section = sectionName(line) {
                currentSection = section
                skippingSection = sections.contains(section)
                if skippingSection {
                    continue
                }
            }

            if skippingSection {
                continue
            }

            if currentSection == nil, let key = topLevelKey(line), topLevelKeys.contains(key) {
                continue
            }

            kept.append(line)
        }

        return trimBlankEdges(kept).joined(separator: "\n")
    }

    private static func sectionName(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else {
            return nil
        }
        return String(trimmed.dropFirst().dropLast())
    }

    private static func topLevelKey(_ line: String) -> String? {
        guard let equals = line.firstIndex(of: "=") else {
            return nil
        }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        return key.isEmpty ? nil : key
    }

    private static func trimBlankEdges(_ lines: [String]) -> [String] {
        var start = lines.startIndex
        var end = lines.endIndex
        while start < end, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
            start = lines.index(after: start)
        }
        while end > start {
            let previous = lines.index(before: end)
            if !lines[previous].trimmingCharacters(in: .whitespaces).isEmpty {
                break
            }
            end = previous
        }
        return Array(lines[start..<end])
    }

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
