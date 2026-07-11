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

public final class ModelRegistryStore {
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
        return RouterModel(
            codexSlug: codexSlug,
            displayName: isCombo ? cleanRawID : RouterModel.displayName(for: codexSlug),
            upstreamModel: upstream,
            aliases: ["openai/\(codexSlug)"],
            visible: !isCombo && RouterModel.defaultVisibility(for: codexSlug),
            priority: item["priority"] as? Int ?? RouterModel.defaultPriority(for: codexSlug),
            notes: isCombo ? "9Router Combo" : nil
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
        var merged = Dictionary(uniqueKeysWithValues: RouterModel.defaults.map { ($0.codexSlug, $0) })
        for localModel in localModels where localModel.notes == "Manual" {
            merged[localModel.codexSlug] = localModel
        }
        for routerModel in routerModels {
            if var existing = merged[routerModel.codexSlug] {
                existing.displayName = routerModel.displayName
                existing.upstreamModel = routerModel.upstreamModel
                existing.aliases = routerModel.aliases
                existing.priority = routerModel.priority
                existing.visible = routerModel.visible
                existing.notes = routerModel.notes
                merged[routerModel.codexSlug] = existing
            } else {
                merged[routerModel.codexSlug] = routerModel
            }
        }
        return Array(merged.values).sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.codexSlug < rhs.codexSlug
            }
            return lhs.priority < rhs.priority
        }
    }

}
