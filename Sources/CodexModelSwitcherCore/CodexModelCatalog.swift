import Foundation

public enum CodexModelCatalog {
    public static func write(
        models: [RouterModel],
        to catalogURL: URL,
        codexCLI: URL?
    ) throws {
        let data = try buildData(models: models, existingCatalogURL: catalogURL, codexCLI: codexCLI)
        try FileManager.default.createDirectory(
            at: catalogURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: catalogURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: catalogURL.path)
    }

    public static func buildData(
        models: [RouterModel],
        existingCatalogURL: URL?,
        codexCLI: URL?
    ) throws -> Data {
        let bundledModels = catalogModels(from: loadBundledCatalog(codexCLI: codexCLI))
        let existingModels = catalogModels(from: loadCatalog(from: existingCatalogURL))
        let bundledBySlug = modelsBySlug(bundledModels)
        let existingBySlug = modelsBySlug(existingModels)

        let bundledFallback = bundledBySlug["gpt-5.5"]
            ?? bundledBySlug["gpt-5.4"]
            ?? bundledModels.first
        let existingFallback = existingBySlug["gpt-5.5"]
            ?? existingBySlug["gpt-5.4"]
            ?? existingModels.first
        let fallbackTemplate = bundledFallback ?? existingFallback

        let outputModels = models
            .sorted { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.codexSlug < rhs.codexSlug
                }
                return lhs.priority < rhs.priority
            }
            .map { model in
                let exactTemplate = bundledBySlug[model.codexSlug] ?? existingBySlug[model.codexSlug]
                return modelEntry(for: model, exactTemplate: exactTemplate, fallbackTemplate: fallbackTemplate)
            }

        let output: [String: Any] = ["models": outputModels]
        return try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    }

    private static func catalogModels(from catalog: [String: Any]?) -> [[String: Any]] {
        catalog?["models"] as? [[String: Any]] ?? []
    }

    private static func modelsBySlug(_ models: [[String: Any]]) -> [String: [String: Any]] {
        Dictionary(uniqueKeysWithValues: models.compactMap { item -> (String, [String: Any])? in
            guard let slug = item["slug"] as? String else { return nil }
            return (slug, item)
        })
    }

    private static func loadCatalog(from url: URL?) -> [String: Any]? {
        guard let url, FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let catalog = object as? [String: Any],
              catalog["models"] is [[String: Any]] else {
            return nil
        }
        return catalog
    }

    private static func loadBundledCatalog(codexCLI: URL?) -> [String: Any]? {
        guard let codexCLI else {
            return nil
        }
        guard let result = try? Shell.run(codexCLI.path, ["debug", "models", "--bundled"], requireSuccess: false),
              result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let catalog = object as? [String: Any],
              catalog["models"] is [[String: Any]] else {
            return nil
        }
        return catalog
    }

    private static func modelEntry(
        for model: RouterModel,
        exactTemplate: [String: Any]?,
        fallbackTemplate: [String: Any]?
    ) -> [String: Any] {
        var entry = exactTemplate ?? fallbackTemplate ?? minimalTemplate()
        entry["slug"] = model.codexSlug
        entry["display_name"] = model.displayName
        entry["description"] = model.notes ?? "9Router model routed through Codex Model Switcher."
        entry["visibility"] = model.visible ? "list" : "hide"
        entry["supported_in_api"] = true
        entry["priority"] = model.priority
        if !model.reasoningEffort.isEmpty {
            entry["default_reasoning_level"] = model.reasoningEffort == "xhigh" ? "medium" : model.reasoningEffort
        }
        return entry
    }

    private static func minimalTemplate() -> [String: Any] {
        [
            "slug": "gpt-5.5",
            "display_name": "GPT-5.5",
            "description": "9Router model routed through Codex Model Switcher.",
            "default_reasoning_level": "medium",
            "supported_reasoning_levels": [
                ["effort": "low", "description": "Fast responses with lighter reasoning"],
                ["effort": "medium", "description": "Balances speed and reasoning depth"],
                ["effort": "high", "description": "Greater reasoning depth"],
                ["effort": "xhigh", "description": "Extra high reasoning depth"]
            ],
            "shell_type": "shell_command",
            "visibility": "list",
            "supported_in_api": true,
            "priority": 100,
            "supports_reasoning_summaries": true,
            "default_reasoning_summary": "none",
            "support_verbosity": true,
            "default_verbosity": "medium"
        ]
    }
}
