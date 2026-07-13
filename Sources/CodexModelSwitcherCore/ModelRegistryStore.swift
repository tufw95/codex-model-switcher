import Foundation

public enum ModelRegistryError: Error, LocalizedError {
    case emptyModelName
    case noModelsInRouterResponse

    public var errorDescription: String? {
        switch self {
        case .emptyModelName:
            return "Model name is empty."
        case .noModelsInRouterResponse:
            return "9Router did not return a recognizable model list."
        }
    }
}

public final class ModelRegistryStore: @unchecked Sendable {
    public let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public func load() throws -> [RouterModel] {
        try paths.ensureBaseDirectories()
        guard FileManager.default.fileExists(atPath: paths.modelRegistry.path) else {
            try save(RouterModel.defaults)
            return RouterModel.defaults
        }

        let data = try Data(contentsOf: paths.modelRegistry)
        let file = try JSONDecoder().decode(ModelRegistryFile.self, from: data)
        return file.models.sorted { $0.priority < $1.priority }
    }

    public func save(_ models: [RouterModel]) throws {
        try paths.ensureBaseDirectories()
        let sorted = models.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.codexSlug < rhs.codexSlug
            }
            return lhs.priority < rhs.priority
        }
        let file = ModelRegistryFile(models: sorted)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: paths.modelRegistry, options: .atomic)
    }

    @discardableResult
    public func upsert(rawModelName: String) throws -> [RouterModel] {
        let trimmed = rawModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ModelRegistryError.emptyModelName
        }

        var models = try load()
        let inferred = RouterModel.inferred(from: trimmed)
        if let index = models.firstIndex(where: { $0.codexSlug == inferred.codexSlug }) {
            models[index].displayName = inferred.displayName
            models[index].upstreamModel = inferred.upstreamModel
            models[index].visible = true
            models[index].notes = "Manual"
        } else {
            var next = inferred
            next.priority = (models.map(\.priority).max() ?? 90) + 10
            next.notes = "Manual"
            models.append(next)
        }
        try save(models)
        return models
    }

    public func refreshFromRouter(apiKey: String, targetBaseURL: URL) async throws -> [RouterModel] {
        let url = modelListURL(from: targetBaseURL)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ModelRegistryError.noModelsInRouterResponse
        }

        let rawItems = (json["models"] as? [[String: Any]]) ?? (json["data"] as? [[String: Any]]) ?? []
        let models = rawItems.compactMap(Self.model(fromRouterItem:))
        guard !models.isEmpty else {
            throw ModelRegistryError.noModelsInRouterResponse
        }

        let merged = merge(routerModels: models, localModels: (try? load()) ?? RouterModel.defaults)
        try save(merged)
        return merged
    }

    static func model(fromRouterItem item: [String: Any]) -> RouterModel? {
        let rawID = (item["id"] as? String) ?? (item["slug"] as? String) ?? (item["model"] as? String)
        guard let rawID, !rawID.isEmpty else {
            return nil
        }

        let cleanRawID = rawID.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCombo = (item["owned_by"] as? String)?.caseInsensitiveCompare("combo") == .orderedSame
        let normalized = RouterModel.normalizeSlug(rawID)
        let upstream = isCombo
            ? cleanRawID
            : (normalized.hasPrefix("cx/") ? normalized : "cx/\(normalized)")
        let codexSlug = normalized.hasPrefix("cx/") ? String(normalized.dropFirst(3)) : normalized
        let reasoningLevels = reasoningLevels(from: item)
        let speedTiers = stringArray(item["additional_speed_tiers"])
            ?? stringArray((item["capabilities"] as? [String: Any])?["additional_speed_tiers"])
        let serviceTiers = serviceTiers(from: item)
        let hasRouterCapabilities = !(reasoningLevels ?? []).isEmpty
            || !(speedTiers ?? []).isEmpty
            || !(serviceTiers ?? []).isEmpty
        let defaultEffort = (item["default_reasoning_level"] as? String)
            ?? ((item["reasoning"] as? [String: Any])?["default"] as? String)
            ?? "xhigh"
        let routerDisplayName = (item["display_name"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = isCombo
            ? cleanRawID
            : (routerDisplayName.flatMap { $0.isEmpty ? nil : $0 } ?? RouterModel.displayName(for: codexSlug))
        return RouterModel(
            codexSlug: codexSlug,
            displayName: displayName,
            upstreamModel: upstream,
            aliases: ["openai/\(codexSlug)"],
            visible: !isCombo && RouterModel.defaultVisibility(for: codexSlug),
            reasoningEffort: defaultEffort,
            priority: integer(item["priority"]) ?? RouterModel.defaultPriority(for: codexSlug),
            notes: isCombo ? "9Router Combo" : nil,
            capabilitySource: hasRouterCapabilities ? .routerMetadata : nil,
            supportedReasoningLevels: reasoningLevels,
            additionalSpeedTiers: speedTiers,
            serviceTiers: serviceTiers
        )
    }

    private func modelListURL(from baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let path = (components?.path ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.hasSuffix("v1/models") {
            return baseURL
        }
        if path.hasSuffix("v1") {
            components?.path = "/" + path + "/models"
        } else if path.isEmpty {
            components?.path = "/v1/models"
        } else {
            components?.path = "/" + path + "/v1/models"
        }
        return components?.url ?? baseURL.appendingPathComponent("v1").appendingPathComponent("models")
    }

    func merge(routerModels: [RouterModel], localModels: [RouterModel]) -> [RouterModel] {
        var merged: [String: RouterModel] = [:]
        let localBySlug = Dictionary(uniqueKeysWithValues: localModels.map { ($0.codexSlug, $0) })
        for localModel in localModels where localModel.notes == "Manual" {
            merged[localModel.codexSlug] = localModel
        }
        for var routerModel in routerModels {
            if let local = localBySlug[routerModel.codexSlug] {
                if let override = local.visibilityOverride {
                    routerModel.visibilityOverride = override
                    routerModel.visible = override
                }
                if !local.reasoningEffort.isEmpty {
                    routerModel.reasoningEffort = local.reasoningEffort
                }
                if routerModel.capabilitySource == nil, local.capabilitySource != nil {
                    routerModel.capabilitySource = local.capabilitySource
                    routerModel.supportedReasoningLevels = local.supportedReasoningLevels
                    routerModel.additionalSpeedTiers = local.additionalSpeedTiers
                    routerModel.serviceTiers = local.serviceTiers
                    if local.capabilitySource == .codexCatalog {
                        routerModel.displayName = local.displayName
                        routerModel.priority = local.priority
                    }
                }
            }
            merged[routerModel.codexSlug] = routerModel
        }
        return Array(merged.values).sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.codexSlug < rhs.codexSlug
            }
            return lhs.priority < rhs.priority
        }
    }

    private static func reasoningLevels(from item: [String: Any]) -> [RouterReasoningLevel]? {
        let capabilities = item["capabilities"] as? [String: Any]
        let reasoning = item["reasoning"] as? [String: Any]
        let raw = item["supported_reasoning_levels"]
            ?? capabilities?["supported_reasoning_levels"]
            ?? reasoning?["supported_levels"]
            ?? reasoning?["efforts"]

        if let dictionaries = raw as? [[String: Any]] {
            let levels = dictionaries.compactMap { value -> RouterReasoningLevel? in
                guard let effort = (value["effort"] as? String) ?? (value["id"] as? String) else {
                    return nil
                }
                return RouterReasoningLevel(
                    effort: effort,
                    description: (value["description"] as? String) ?? effort.capitalized
                )
            }
            return levels.isEmpty ? nil : levels
        }

        guard let efforts = stringArray(raw), !efforts.isEmpty else {
            return nil
        }
        return efforts.map {
            RouterReasoningLevel(effort: $0, description: $0.capitalized)
        }
    }

    private static func serviceTiers(from item: [String: Any]) -> [RouterServiceTier]? {
        let capabilities = item["capabilities"] as? [String: Any]
        let raw = item["service_tiers"] ?? capabilities?["service_tiers"]
        guard let dictionaries = raw as? [[String: Any]] else {
            return nil
        }
        let tiers = dictionaries.compactMap { value -> RouterServiceTier? in
            guard let id = (value["id"] as? String) ?? (value["tier"] as? String) else {
                return nil
            }
            return RouterServiceTier(
                id: id,
                name: (value["name"] as? String) ?? id.capitalized,
                description: (value["description"] as? String) ?? ""
            )
        }
        return tiers.isEmpty ? nil : tiers
    }

    private static func stringArray(_ value: Any?) -> [String]? {
        if let strings = value as? [String] {
            return strings
        }
        guard let values = value as? [Any] else {
            return nil
        }
        let strings = values.compactMap { $0 as? String }
        return strings.isEmpty ? nil : strings
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }
        if let value = value as? NSNumber {
            return value.intValue
        }
        if let value = value as? String {
            return Int(value)
        }
        return nil
    }

}
