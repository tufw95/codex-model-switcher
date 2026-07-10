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
        } else {
            var next = inferred
            next.priority = (models.map(\.priority).max() ?? 90) + 10
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

    private static func model(fromRouterItem item: [String: Any]) -> RouterModel? {
        let rawID = (item["id"] as? String) ?? (item["slug"] as? String) ?? (item["model"] as? String)
        guard let rawID, !rawID.isEmpty else {
            return nil
        }

        let upstream = rawID.hasPrefix("cx/") ? rawID : "cx/\(RouterModel.normalizeSlug(rawID))"
        let codexSlug = upstream.hasPrefix("cx/") ? String(upstream.dropFirst(3)) : upstream
        let displayName = (item["display_name"] as? String)
            ?? (item["name"] as? String)
            ?? RouterModel.displayName(for: codexSlug)
        return RouterModel(
            codexSlug: codexSlug,
            displayName: displayName,
            upstreamModel: upstream,
            aliases: ["openai/\(codexSlug)"],
            visible: true,
            priority: item["priority"] as? Int ?? 100
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

    private func merge(routerModels: [RouterModel], localModels: [RouterModel]) -> [RouterModel] {
        var merged = Dictionary(uniqueKeysWithValues: localModels.map { ($0.codexSlug, $0) })
        for routerModel in routerModels {
            if var existing = merged[routerModel.codexSlug] {
                existing.displayName = routerModel.displayName
                existing.upstreamModel = routerModel.upstreamModel
                existing.visible = true
                merged[routerModel.codexSlug] = existing
            } else {
                merged[routerModel.codexSlug] = routerModel
            }
        }
        return Array(merged.values).sorted { $0.priority < $1.priority }
    }
}
