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
        let fallbackTemplate = bundledBySlug["gpt-5.5"]
            ?? bundledBySlug["gpt-5.4"]
            ?? bundledModels.first
            ?? existingBySlug["gpt-5.5"]
            ?? existingBySlug["gpt-5.4"]
            ?? existingModels.first
            ?? minimalTemplate()
        let enriched = applyingOfficialMetadata(to: models, catalogModels: bundledModels)

        let outputModels = enriched.map { model in
            let exactTemplate = bundledBySlug[model.codexSlug] ?? existingBySlug[model.codexSlug]
            return modelEntry(
                for: model,
                exactTemplate: exactTemplate,
                fallbackTemplate: fallbackTemplate
            )
        }
        let output: [String: Any] = ["models": outputModels]
        return try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys])
    }

    public static func applyingOfficialMetadata(
        to models: [RouterModel],
        codexCLI: URL?
    ) -> [RouterModel] {
        applyingOfficialMetadata(
            to: models,
            catalogModels: catalogModels(from: loadBundledCatalog(codexCLI: codexCLI))
        )
    }

    private static func applyingOfficialMetadata(
        to models: [RouterModel],
        catalogModels: [[String: Any]]
    ) -> [RouterModel] {
        guard !catalogModels.isEmpty else {
            return sorted(models.map(sanitizedWithoutOfficialMetadata))
        }
        let officialBySlug = modelsBySlug(catalogModels)
        return sorted(models.map { model in
            guard let official = officialBySlug[model.codexSlug] else {
                return sanitizedWithoutOfficialMetadata(model)
            }

            var result = model
            if let displayName = official["display_name"] as? String, !displayName.isEmpty {
                result.displayName = displayName
            }
            if let priority = integer(official["priority"]) {
                result.priority = priority
            }
            if let visibility = official["visibility"] as? String {
                result.visible = model.visibilityOverride
                    ?? (visibility.caseInsensitiveCompare("list") == .orderedSame)
            }

            let officialLevels = reasoningLevels(from: official)
            result.supportedReasoningLevels = intersectReasoningLevels(
                official: officialLevels,
                router: model.capabilitySource == .routerMetadata ? model.supportedReasoningLevels : nil
            )
            result.additionalSpeedTiers = intersectStrings(
                official: official["additional_speed_tiers"] as? [String],
                router: model.capabilitySource == .routerMetadata ? model.additionalSpeedTiers : nil
            )
            result.serviceTiers = intersectServiceTiers(
                official: serviceTiers(from: official),
                router: model.capabilitySource == .routerMetadata ? model.serviceTiers : nil
            )
            result.reasoningEffort = safeDefaultEffort(
                preferred: model.reasoningEffort,
                officialDefault: official["default_reasoning_level"] as? String,
                levels: result.supportedReasoningLevels ?? []
            )
            result.capabilitySource = .codexCatalog
            return result
        })
    }

    private static func sanitizedWithoutOfficialMetadata(_ model: RouterModel) -> RouterModel {
        var result = model
        let hasTrustedCachedMetadata = model.capabilitySource == .routerMetadata
            || model.capabilitySource == .codexCatalog
        let cachedLevels = hasTrustedCachedMetadata
            ? sanitizedReasoningLevels(model.supportedReasoningLevels ?? [])
            : []
        result.supportedReasoningLevels = cachedLevels.isEmpty
            ? [RouterReasoningLevel(effort: "medium", description: "Balanced reasoning for this model")]
            : cachedLevels
        result.additionalSpeedTiers = hasTrustedCachedMetadata
            ? model.additionalSpeedTiers
            : nil
        result.serviceTiers = hasTrustedCachedMetadata
            ? model.serviceTiers
            : nil
        result.reasoningEffort = safeDefaultEffort(
            preferred: model.reasoningEffort,
            officialDefault: "medium",
            levels: result.supportedReasoningLevels ?? []
        )
        result.capabilitySource = hasTrustedCachedMetadata ? model.capabilitySource : .conservative
        return result
    }

    private static func modelEntry(
        for model: RouterModel,
        exactTemplate: [String: Any]?,
        fallbackTemplate: [String: Any]
    ) -> [String: Any] {
        var entry = exactTemplate ?? fallbackTemplate
        copyMissingRequiredFields(into: &entry, from: fallbackTemplate)
        entry["slug"] = model.codexSlug
        entry["display_name"] = model.displayName
        if exactTemplate == nil {
            entry["description"] = model.notes ?? "9Router model routed through Codex Model Switcher."
        }
        entry["visibility"] = model.visible ? "list" : "hide"
        entry["supported_in_api"] = true
        entry["priority"] = model.priority
        entry["supported_reasoning_levels"] = (model.supportedReasoningLevels ?? []).map {
            ["effort": $0.effort, "description": $0.description]
        }
        entry["default_reasoning_level"] = model.reasoningEffort

        if let speedTiers = model.additionalSpeedTiers, !speedTiers.isEmpty {
            entry["additional_speed_tiers"] = speedTiers
        } else {
            entry.removeValue(forKey: "additional_speed_tiers")
        }
        if let tiers = model.serviceTiers, !tiers.isEmpty {
            entry["service_tiers"] = tiers.map {
                ["id": $0.id, "name": $0.name, "description": $0.description]
            }
        } else {
            entry.removeValue(forKey: "service_tiers")
        }
        return entry
    }

    private static func copyMissingRequiredFields(
        into entry: inout [String: Any],
        from template: [String: Any]
    ) {
        let minimal = minimalTemplate()
        for key in requiredTemplateKeys where entry[key] == nil {
            if let value = template[key] ?? minimal[key] {
                entry[key] = value
            }
        }
    }

    private static let requiredTemplateKeys = [
        "base_instructions",
        "model_messages",
        "supported_reasoning_levels",
        "shell_type",
        "supports_reasoning_summaries",
        "default_reasoning_summary",
        "support_verbosity",
        "default_verbosity"
    ]

    private static func minimalTemplate() -> [String: Any] {
        let baseInstructions = """
        You are Codex, an agent based on GPT-5. You and the user share one workspace, and your job is to collaborate with them until their goal is genuinely handled.
        """
        return [
            "slug": "router-model",
            "display_name": "Router Model",
            "description": "9Router model routed through Codex Model Switcher.",
            "base_instructions": baseInstructions,
            "default_reasoning_level": "medium",
            "supported_reasoning_levels": [
                ["effort": "medium", "description": "Balanced reasoning for this model"]
            ],
            "shell_type": "shell_command",
            "visibility": "list",
            "supported_in_api": true,
            "priority": 100,
            "supports_reasoning_summaries": true,
            "default_reasoning_summary": "none",
            "support_verbosity": true,
            "default_verbosity": "medium",
            "model_messages": [
                "instructions_template": baseInstructions,
                "instructions_variables": [
                    "personality_default": "",
                    "personality_friendly": "",
                    "personality_pragmatic": ""
                ]
            ]
        ]
    }

    private static func reasoningLevels(from item: [String: Any]) -> [RouterReasoningLevel] {
        let values = item["supported_reasoning_levels"] as? [[String: Any]] ?? []
        return sanitizedReasoningLevels(values.compactMap { value in
            guard let effort = value["effort"] as? String else { return nil }
            return RouterReasoningLevel(
                effort: effort,
                description: (value["description"] as? String) ?? effort.capitalized
            )
        })
    }

    private static func sanitizedReasoningLevels(
        _ levels: [RouterReasoningLevel]
    ) -> [RouterReasoningLevel] {
        levels.filter { $0.effort.caseInsensitiveCompare("ultra") != .orderedSame }
    }

    private static func intersectReasoningLevels(
        official: [RouterReasoningLevel],
        router: [RouterReasoningLevel]?
    ) -> [RouterReasoningLevel] {
        let safeOfficial = sanitizedReasoningLevels(official)
        guard let router, !router.isEmpty else {
            return safeOfficial
        }
        let routerEfforts = Set(sanitizedReasoningLevels(router).map { $0.effort.lowercased() })
        return safeOfficial.filter { routerEfforts.contains($0.effort.lowercased()) }
    }

    private static func intersectStrings(
        official: [String]?,
        router: [String]?
    ) -> [String]? {
        guard let official, !official.isEmpty else { return nil }
        guard let router else { return official }
        guard !router.isEmpty else { return nil }
        let routerValues = Set(router.map { $0.lowercased() })
        let intersection = official.filter { routerValues.contains($0.lowercased()) }
        return intersection.isEmpty ? nil : intersection
    }

    private static func intersectServiceTiers(
        official: [RouterServiceTier]?,
        router: [RouterServiceTier]?
    ) -> [RouterServiceTier]? {
        guard let official, !official.isEmpty else { return nil }
        guard let router else { return official }
        guard !router.isEmpty else { return nil }
        let routerIDs = Set(router.map { $0.id.lowercased() })
        let intersection = official.filter { routerIDs.contains($0.id.lowercased()) }
        return intersection.isEmpty ? nil : intersection
    }

    private static func safeDefaultEffort(
        preferred: String,
        officialDefault: String?,
        levels: [RouterReasoningLevel]
    ) -> String {
        let supported = Set(levels.map { $0.effort.lowercased() })
        for candidate in [preferred, officialDefault ?? "", "max", "xhigh", "high", "medium", "low", "minimal", "none"] {
            let normalized = candidate.lowercased()
            if supported.contains(normalized) {
                return candidate
            }
        }
        return "medium"
    }

    private static func serviceTiers(from item: [String: Any]) -> [RouterServiceTier]? {
        guard let values = item["service_tiers"] as? [[String: Any]] else { return nil }
        let tiers = values.compactMap { value -> RouterServiceTier? in
            guard let id = value["id"] as? String else { return nil }
            return RouterServiceTier(
                id: id,
                name: (value["name"] as? String) ?? id.capitalized,
                description: (value["description"] as? String) ?? ""
            )
        }
        return tiers.isEmpty ? nil : tiers
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
        guard let url, FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let catalog = object as? [String: Any],
              catalog["models"] is [[String: Any]] else {
            return nil
        }
        return catalog
    }

    private static func loadBundledCatalog(codexCLI: URL?) -> [String: Any]? {
        guard let codexCLI,
              let result = try? Shell.run(codexCLI.path, ["debug", "models", "--bundled"], requireSuccess: false),
              result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let catalog = object as? [String: Any],
              catalog["models"] is [[String: Any]] else {
            return nil
        }
        return catalog
    }

    private static func sorted(_ models: [RouterModel]) -> [RouterModel] {
        models.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.codexSlug < rhs.codexSlug
            }
            return lhs.priority < rhs.priority
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
