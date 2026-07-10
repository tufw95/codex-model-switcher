import XCTest
@testable import CodexModelSwitcherCore

final class CodexModelSwitcherCoreTests: XCTestCase {
    func testModelInferenceNormalizesFriendlyNames() {
        let model = RouterModel.inferred(from: "gpt 5.6")
        XCTAssertEqual(model.codexSlug, "gpt-5.6")
        XCTAssertEqual(model.upstreamModel, "cx/gpt-5.6")
        XCTAssertEqual(model.displayName, "GPT-5.6")
        XCTAssertTrue(model.aliases.contains("openai/gpt-5.6"))
    }

    func testRouterDisplayNamesAndPrioritiesPreferComboAndLatestModels() {
        XCTAssertEqual(RouterModel.displayName(for: "cx/codex"), "Codex (9Router Combo)")
        XCTAssertEqual(RouterModel.displayName(for: "gpt-5.6-sol-review"), "GPT-5.6 Sol Review")
        XCTAssertLessThan(RouterModel.defaultPriority(for: "codex"), RouterModel.defaultPriority(for: "gpt-5.6-sol"))
        XCTAssertLessThan(RouterModel.defaultPriority(for: "gpt-5.6-sol"), RouterModel.defaultPriority(for: "gpt-5.5"))
    }

    func testRouterRefreshModelsReplaceStaleLocalPriorities() throws {
        let combo = try XCTUnwrap(ModelRegistryStore.model(fromRouterItem: [
            "id": "cx/codex",
            "display_name": "CODEX"
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

        XCTAssertEqual(merged.map(\.codexSlug), ["codex", "gpt-5.6-sol", "gpt-5.5"])
        XCTAssertEqual(combo.displayName, "Codex (9Router Combo)")
        XCTAssertEqual(sol.displayName, "GPT-5.6 Sol")
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
        XCTAssertEqual(catalogModels?.first?["display_name"] as? String, "GPT-5.6")
        XCTAssertEqual(catalogModels?.first?["visibility"] as? String, "list")
    }
}
