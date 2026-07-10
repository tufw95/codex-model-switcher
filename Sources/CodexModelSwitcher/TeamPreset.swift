import Foundation

struct TeamPreset {
    var routerTargetURL: String
    var bundledAPIKey: String?
    var autoRefreshModelsOnLaunch: Bool
    var updateManifestURL: String?

    static func load() -> TeamPreset {
        let info = Bundle.main.infoDictionary ?? [:]
        let routerTargetURL = (info["DefaultRouterTargetURL"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? "https://9router.bigroll.vn"
        let bundledAPIKey = (info["BundledNineRouterAPIKey"] as? String)
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        let autoRefresh = info["AutoRefreshModelsOnLaunch"] as? Bool ?? true
        let updateManifestURL = (info["UpdateManifestURL"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }

        return TeamPreset(
            routerTargetURL: routerTargetURL,
            bundledAPIKey: bundledAPIKey,
            autoRefreshModelsOnLaunch: autoRefresh,
            updateManifestURL: updateManifestURL
        )
    }
}
