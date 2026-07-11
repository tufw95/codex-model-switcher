import XCTest
@testable import CodexModelSwitcherCore

final class CodexModelSwitcherCoreTests: XCTestCase {
    func testModelInferenceNormalizesFriendlyNames() {
        let model = RouterModel.inferred(from: "gpt 5.6")
        XCTAssertEqual(model.codexSlug, "gpt-5.6")
        XCTAssertEqual(model.upstreamModel, "cx/gpt-5.6")
        XCTAssertEqual(model.displayName, "5.6")
        XCTAssertTrue(model.aliases.contains("openai/gpt-5.6"))
    }

    func testRouterDisplayNamesAndPrioritiesMatchOfficialPicker() {
        XCTAssertEqual(RouterModel.displayName(for: "cx/codex"), "Codex")
        XCTAssertEqual(RouterModel.displayName(for: "gpt-5.6-sol"), "5.6 Sol")
        XCTAssertEqual(RouterModel.displayName(for: "gpt-5.4-mini"), "5.4 Mini")
        XCTAssertLessThan(RouterModel.defaultPriority(for: "codex"), RouterModel.defaultPriority(for: "gpt-5.6-sol"))
        XCTAssertLessThan(RouterModel.defaultPriority(for: "gpt-5.6-sol"), RouterModel.defaultPriority(for: "gpt-5.5"))
        XCTAssertFalse(RouterModel.defaultVisibility(for: "gpt-5.6-sol-review"))
        XCTAssertFalse(RouterModel.defaultVisibility(for: "gpt-5.3-codex"))
        XCTAssertTrue(RouterModel.defaultVisibility(for: "gpt-5.4-mini"))
    }

    func testRouterRefreshModelsReplaceStaleLocalPriorities() throws {
        let combo = try XCTUnwrap(ModelRegistryStore.model(fromRouterItem: [
            "id": "Codex",
            "owned_by": "combo"
        ]))
        let sol = try XCTUnwrap(ModelRegistryStore.model(fromRouterItem: [
            "id": "cx/gpt-5.6-sol",
            "display_name": "GPT-5.6-SOL"
        ]))
        let legacy = try XCTUnwrap(ModelRegistryStore.model(fromRouterItem: [
            "id": "cx/gpt-5.5",
            "display_name": "GPT-5.5"
        ]))

        let staleLocalModel = RouterModel(
            codexSlug: "gpt-5.5",
            displayName: "GPT-5.5",
            upstreamModel: "cx/gpt-5.5",
            priority: 0
        )
        let merged = ModelRegistryStore().merge(
            routerModels: [legacy, sol, combo],
            localModels: [staleLocalModel]
        )

        XCTAssertEqual(
            merged.map(\.codexSlug),
            ["codex", "gpt-5.6-sol", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini"]
        )
        XCTAssertEqual(combo.displayName, "Codex")
        XCTAssertEqual(combo.upstreamModel, "Codex")
        XCTAssertFalse(combo.visible)
        XCTAssertEqual(combo.notes, "9Router Combo")
        XCTAssertEqual(sol.displayName, "5.6 Sol")
    }

    func testVisibleRouterModelsMatchOfficialPickerOrder() {
        let items: [[String: Any]] = [
            ["id": "Codex", "owned_by": "combo"],
            ["id": "cx/gpt-5.6-luna-review", "owned_by": "cx"],
            ["id": "cx/gpt-5.4-mini", "owned_by": "cx"],
            ["id": "cx/gpt-5.5", "owned_by": "cx"],
            ["id": "cx/gpt-5.6-terra", "owned_by": "cx"],
            ["id": "cx/gpt-5.6-sol", "owned_by": "cx"],
            ["id": "cx/gpt-5.6-luna", "owned_by": "cx"]
        ]

        let staleLocalModel = RouterModel(
            codexSlug: "gpt-5.3-codex",
            displayName: "GPT-5.3-CODEX",
            upstreamModel: "cx/gpt-5.3-codex",
            visible: true
        )
        let merged = ModelRegistryStore().merge(
            routerModels: items.compactMap(ModelRegistryStore.model(fromRouterItem:)),
            localModels: [staleLocalModel]
        )
        let visibleNames = merged
            .filter(\.visible)
            .sorted { $0.priority < $1.priority }
            .map(\.displayName)

        XCTAssertEqual(visibleNames, ["5.6 Sol", "5.6 Terra", "5.6 Luna", "5.5", "5.4", "5.4 Mini"])
    }

    func testConfigRewritePreservesUnrelatedSections() {
        let existing = """
        model_provider = "Old"
        model = "old-model"
        approval_policy = "never"

        [projects."/tmp"]
        trust_level = "trusted"

        [model_providers.NineRouter]
        name = "old"
        base_url = "old"
        """

        let rewritten = CodexConfigRewriter.rewriteModelConfig(
            existing: existing,
            profile: .nineRouter,
            model: RouterModel.inferred(from: "gpt 5.6"),
            catalogPath: "/Users/example/.codex/9router-model-catalog.json",
            proxyBaseURL: "http://127.0.0.1:9783/v1"
        )

        XCTAssertTrue(rewritten.contains("model_provider = \"NineRouter\""))
        XCTAssertTrue(rewritten.contains("model = \"gpt-5.6\""))
        XCTAssertTrue(rewritten.contains("approval_policy = \"never\""))
        XCTAssertTrue(rewritten.contains("[projects.\"/tmp\"]"))
        XCTAssertEqual(rewritten.components(separatedBy: "[model_providers.NineRouter]").count, 2)
    }

    func testAuthenticConfigRemovesNineRouterProvider() {
        let existing = """
        model_provider = "NineRouter"
        model = "codex"
        model_catalog_json = "/Users/example/.codex/9router-model-catalog.json"

        [model_providers.NineRouter]
        name = "9Router"
        base_url = "http://127.0.0.1:9783/v1"

        [projects."/tmp"]
        trust_level = "trusted"
        """

        let rewritten = CodexConfigRewriter.rewriteModelConfig(
            existing: existing,
            profile: .authenticCodex,
            model: RouterModel.inferred(from: "gpt-5.5"),
            catalogPath: "/Users/example/.codex/9router-model-catalog.json",
            proxyBaseURL: "http://127.0.0.1:9783/v1"
        )

        XCTAssertFalse(rewritten.contains("model_provider = \"NineRouter\""))
        XCTAssertFalse(rewritten.contains("model_catalog_json"))
        XCTAssertFalse(rewritten.contains("[model_providers.NineRouter]"))
        XCTAssertTrue(rewritten.contains("model = \"gpt-5.5\""))
        XCTAssertTrue(rewritten.contains("[projects.\"/tmp\"]"))
    }

    func testCatalogBuilderSynthesizesCustomModel() throws {
        let models = [
            RouterModel.inferred(from: "gpt 5.6")
        ]

        let data = try CodexModelCatalog.buildData(
            models: models,
            existingCatalogURL: nil,
            codexCLI: nil
        )
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let catalogModels = json?["models"] as? [[String: Any]]
        XCTAssertEqual(catalogModels?.first?["slug"] as? String, "gpt-5.6")
        XCTAssertEqual(catalogModels?.first?["display_name"] as? String, "5.6")
        XCTAssertEqual(catalogModels?.first?["visibility"] as? String, "list")
    }
}
