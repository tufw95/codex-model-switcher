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
