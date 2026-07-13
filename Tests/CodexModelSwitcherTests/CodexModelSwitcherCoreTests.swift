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

    func testRegistryDecodesLegacyModelsWithoutCapabilityMetadata() throws {
        let data = Data("""
        {
          "version": 1,
          "models": [{
            "codexSlug": "gpt-5.6-sol",
            "displayName": "5.6 Sol",
            "upstreamModel": "cx/gpt-5.6-sol",
            "aliases": ["openai/gpt-5.6-sol"],
            "visible": true,
            "reasoningEffort": "xhigh",
            "priority": 10
          }]
        }
        """.utf8)

        let file = try JSONDecoder().decode(ModelRegistryFile.self, from: data)
        let model = try XCTUnwrap(file.models.first)
        XCTAssertEqual(model.codexSlug, "gpt-5.6-sol")
        XCTAssertNil(model.capabilitySource)
        XCTAssertNil(model.supportedReasoningLevels)
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

    func testRouterRefreshRemovesStaleAutomaticModels() throws {
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
            ["codex", "gpt-5.6-sol", "gpt-5.5"]
        )
        XCTAssertEqual(combo.displayName, "Codex")
        XCTAssertEqual(combo.upstreamModel, "Codex")
        XCTAssertFalse(combo.visible)
        XCTAssertEqual(combo.notes, "9Router Combo")
        XCTAssertEqual(sol.displayName, "GPT-5.6-SOL")
    }

    func testRouterRefreshKeepsCachedOfficialMetadataWhenRouterHasOnlyIDs() throws {
        let routerModel = try XCTUnwrap(ModelRegistryStore.model(fromRouterItem: [
            "id": "cx/gpt-5.6-sol"
        ]))
        let cached = RouterModel(
            codexSlug: "gpt-5.6-sol",
            displayName: "GPT-5.6-Sol",
            upstreamModel: "cx/gpt-5.6-sol",
            reasoningEffort: "xhigh",
            priority: 1,
            capabilitySource: .codexCatalog,
            supportedReasoningLevels: [
                RouterReasoningLevel(effort: "xhigh", description: "Extra High")
            ],
            additionalSpeedTiers: ["fast"]
        )

        let merged = ModelRegistryStore().merge(
            routerModels: [routerModel],
            localModels: [cached]
        )
        let model = try XCTUnwrap(merged.first)
        XCTAssertEqual(model.displayName, "GPT-5.6-Sol")
        XCTAssertEqual(model.priority, 1)
        XCTAssertEqual(model.capabilitySource, .codexCatalog)
        XCTAssertEqual(model.supportedReasoningLevels?.map(\.effort), ["xhigh"])
        XCTAssertEqual(model.additionalSpeedTiers, ["fast"])
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

        XCTAssertEqual(visibleNames, ["5.6 Sol", "5.6 Terra", "5.6 Luna", "5.5", "5.4 Mini"])
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
        XCTAssertTrue(rewritten.contains("requires_openai_auth = true"))
        XCTAssertFalse(rewritten.contains("env_key = \"NINEROUTER_API_KEY\""))
        XCTAssertTrue(rewritten.contains("approval_policy = \"never\""))
        XCTAssertTrue(rewritten.contains("[projects.\"/tmp\"]"))
        XCTAssertEqual(rewritten.components(separatedBy: "[model_providers.NineRouter]").count, 2)
    }

    func testNineRouterConfigFallsBackToAPIKeyAuthWithoutChatGPTLogin() {
        let rewritten = CodexConfigRewriter.rewriteModelConfig(
            existing: "",
            profile: .nineRouter,
            model: RouterModel.inferred(from: "gpt-5.6-sol"),
            catalogPath: "/Users/example/.codex/9router-model-catalog.json",
            proxyBaseURL: "http://127.0.0.1:9783/v1",
            useChatGPTAuthentication: false
        )

        XCTAssertTrue(rewritten.contains("env_key = \"NINEROUTER_API_KEY\""))
        XCTAssertFalse(rewritten.contains("requires_openai_auth"))
    }

    func testProxyReplacesOpenAIAuthenticationWithLocalRouterKey() {
        let headers = SwiftRouterProxy.upstreamHeaders(
            from: [
                "Authorization": "Bearer openai-account-token",
                "ChatGPT-Account-ID": "account-123",
                "X-OpenAI-Attestation": "private-attestation",
                "Cookie": "private-cookie",
                "Content-Type": "application/json",
                "Accept-Encoding": "gzip"
            ],
            routerAPIKey: "router-secret"
        )

        XCTAssertEqual(headers["Authorization"], "Bearer router-secret")
        XCTAssertEqual(headers["Content-Type"], "application/json")
        XCTAssertEqual(headers["Accept-Encoding"], "identity")
        XCTAssertFalse(headers.keys.contains { $0.caseInsensitiveCompare("ChatGPT-Account-ID") == .orderedSame })
        XCTAssertFalse(headers.keys.contains { $0.caseInsensitiveCompare("X-OpenAI-Attestation") == .orderedSame })
        XCTAssertFalse(headers.keys.contains { $0.caseInsensitiveCompare("Cookie") == .orderedSame })
    }

    func testProxyReadsRouterKeyFromLocalEnvFile() throws {
        let envURL = try temporaryFile(
            named: ".env",
            contents: "NINEROUTER_API_KEY=\"router-secret\" # local only\n"
        )
        XCTAssertEqual(SwiftRouterProxy.readAPIKey(from: envURL), "router-secret")
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

    func testShellDrainsLargeStandardOutputAndErrorWithoutDeadlocking() throws {
        let result = try Shell.run(
            "/bin/sh",
            [
                "-c",
                """
                i=0
                while [ "$i" -lt 10000 ]; do
                  printf 'catalog-data\\n'
                  printf 'diagnostic-data\\n' >&2
                  i=$((i + 1))
                done
                """
            ]
        )

        XCTAssertGreaterThan(result.stdout.utf8.count, 65_536)
        XCTAssertGreaterThan(result.stderr.utf8.count, 65_536)
    }

    func testUpdateManifestDecodesInstallationIntegrityFields() throws {
        let data = Data(
            """
            {
              "version": "1.2.3",
              "build": "42",
              "download_url": "https://example.com/update.dmg",
              "sha256": "abcdef",
              "size_bytes": 123456
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        XCTAssertEqual(manifest.sha256, "abcdef")
        XCTAssertEqual(manifest.sizeBytes, 123456)
    }

    func testUpdateInstallerComputesSHA256() throws {
        let fileURL = try temporaryFile(named: "checksum.txt", contents: "Codex Switch OTA")
        XCTAssertEqual(
            try UpdateInstaller.sha256(of: fileURL),
            "6f63fc6c9dcf86a5d644f56651973752bd881b4ef0e33a4a893f778e8ff699c0"
        )
    }

    func testUpdateInstallerReplacesSignedAppBundle() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexModelSwitcherUpdateTests-\(UUID().uuidString)", isDirectory: true)
        let targetURL = root.appendingPathComponent("Installed/Codex Model Switcher.app", isDirectory: true)
        let stagedURL = root.appendingPathComponent("Working/staged/Codex Model Switcher.app", isDirectory: true)
        let workingURL = root.appendingPathComponent("Working", isDirectory: true)
        let scriptURL = workingURL.appendingPathComponent("install-update.sh")
        let logURL = root.appendingPathComponent("updater.log")
        try makeSignedTestApp(at: targetURL, marker: "old")
        try makeSignedTestApp(at: stagedURL, marker: "new")
        try UpdateInstaller.installerScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let plan = UpdateInstallationPlan(
            targetAppURL: targetURL,
            stagedAppURL: stagedURL,
            currentAppURL: targetURL,
            workingDirectory: workingURL,
            installerScriptURL: scriptURL,
            logURL: logURL,
            requiresAdministratorPrivileges: false
        )
        try UpdateInstaller().launchInstallation(
            plan,
            currentProcessID: Int32.max,
            relaunch: false
        )

        let markerURL = targetURL.appendingPathComponent("Contents/Resources/marker.txt")
        let deadline = Date().addingTimeInterval(5)
        var marker = ""
        while Date() < deadline {
            marker = (try? String(contentsOf: markerURL, encoding: .utf8)) ?? ""
            if marker == "new", !FileManager.default.fileExists(atPath: workingURL.path) {
                break
            }
            Thread.sleep(forTimeInterval: 0.05)
        }

        XCTAssertEqual(marker, "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: workingURL.path))
        XCTAssertTrue(
            try Shell.run(
                "/usr/bin/codesign",
                ["--verify", "--deep", "--strict", targetURL.path],
                requireSuccess: false
            ).succeeded
        )
    }

    func testCatalogBuilderPrefersFreshBundledMetadataOverExistingCatalog() throws {
        let existingCatalogURL = try temporaryFile(
            named: "existing-catalog.json",
            contents: """
            {
              "models": [{
                "slug": "gpt-5.6-sol",
                "display_name": "Old Sol",
                "supported_reasoning_levels": [
                  {"effort": "low", "description": "Low"},
                  {"effort": "xhigh", "description": "Extra High"}
                ]
              }]
            }
            """
        )
        let fakeCLI = try temporaryExecutable(
            named: "codex",
            output: """
            {
              "models": [{
                "slug": "gpt-5.6-sol",
                "display_name": "GPT-5.6-SOL",
                "supported_reasoning_levels": [
                  {"effort": "low", "description": "Low"},
                  {"effort": "medium", "description": "Medium"},
                  {"effort": "high", "description": "High"},
                  {"effort": "xhigh", "description": "Extra High"},
                  {"effort": "max", "description": "Max"},
                  {"effort": "ultra", "description": "Ultra"}
                ],
                "additional_speed_tiers": ["fast"],
                "service_tiers": [{
                  "id": "priority",
                  "name": "Fast",
                  "description": "1.5x speed, increased usage"
                }]
              }]
            }
            """
        )

        let data = try CodexModelCatalog.buildData(
            models: [RouterModel.inferred(from: "gpt-5.6-sol")],
            existingCatalogURL: existingCatalogURL,
            codexCLI: fakeCLI
        )
        let model = try XCTUnwrap(catalogModel(from: data, slug: "gpt-5.6-sol"))
        let levels = try XCTUnwrap(model["supported_reasoning_levels"] as? [[String: Any]])
        XCTAssertEqual(levels.compactMap { $0["effort"] as? String }, ["low", "medium", "high", "xhigh", "max", "ultra"])
        XCTAssertEqual(model["additional_speed_tiers"] as? [String], ["fast"])
        XCTAssertEqual((model["service_tiers"] as? [[String: Any]])?.first?["id"] as? String, "priority")
    }

    func testCatalogBuilderKeepsCustomMetadataButUsesConservativeCapabilities() throws {
        let existingCatalogURL = try temporaryFile(
            named: "custom-catalog.json",
            contents: """
            {
              "models": [{
                "slug": "gpt-5.7-team",
                "display_name": "Old Team Name",
                "supported_reasoning_levels": [
                  {"effort": "low", "description": "Low"},
                  {"effort": "high", "description": "High"}
                ],
                "custom_router_capability": true
              }]
            }
            """
        )
        let fakeCLI = try temporaryExecutable(
            named: "codex",
            output: """
            {
              "models": [{
                "slug": "gpt-5.6-sol",
                "display_name": "GPT-5.6-SOL"
              }]
            }
            """
        )

        let data = try CodexModelCatalog.buildData(
            models: [RouterModel.inferred(from: "gpt-5.7-team")],
            existingCatalogURL: existingCatalogURL,
            codexCLI: fakeCLI
        )
        let model = try XCTUnwrap(catalogModel(from: data, slug: "gpt-5.7-team"))
        XCTAssertEqual(model["display_name"] as? String, "5.7 Team")
        XCTAssertEqual(model["custom_router_capability"] as? Bool, true)
        let levels = try XCTUnwrap(model["supported_reasoning_levels"] as? [[String: Any]])
        XCTAssertEqual(levels.compactMap { $0["effort"] as? String }, ["medium"])
    }

    func testCatalogBuilderRepairsExistingTemplateMissingBaseInstructions() throws {
        let existingCatalogURL = try temporaryFile(
            named: "broken-catalog.json",
            contents: """
            {
              "models": [{
                "slug": "codex",
                "display_name": "Codex",
                "supported_reasoning_levels": [
                  {"effort": "medium", "description": "Medium"}
                ]
              }]
            }
            """
        )
        let fakeCLI = try temporaryExecutable(
            named: "codex",
            output: """
            {
              "models": [{
                "slug": "gpt-5.6-sol",
                "display_name": "GPT-5.6-SOL",
                "base_instructions": "Bundled instructions",
                "model_messages": {
                  "instructions_template": "Bundled instructions",
                  "instructions_variables": {}
                },
                "supported_reasoning_levels": [
                  {"effort": "medium", "description": "Medium"}
                ],
                "shell_type": "shell_command",
                "supports_reasoning_summaries": true,
                "default_reasoning_summary": "none",
                "support_verbosity": true,
                "default_verbosity": "low"
              }]
            }
            """
        )
        let combo = RouterModel(
            codexSlug: "codex",
            displayName: "Codex",
            upstreamModel: "Codex",
            visible: false,
            reasoningEffort: "medium",
            priority: 0,
            notes: "9Router Combo"
        )

        let data = try CodexModelCatalog.buildData(
            models: [combo],
            existingCatalogURL: existingCatalogURL,
            codexCLI: fakeCLI
        )
        let model = try XCTUnwrap(catalogModel(from: data, slug: "codex"))
        XCTAssertEqual(model["base_instructions"] as? String, "Bundled instructions")
        XCTAssertNotNil(model["model_messages"] as? [String: Any])
        XCTAssertEqual(model["visibility"] as? String, "hide")
    }

    func testOfficialMetadataControlsNameOrderAndKeepsOfficialUltraUI() throws {
        let fakeCLI = try temporaryExecutable(
            named: "codex",
            output: """
            {
              "models": [{
                "slug": "gpt-5.7-team",
                "display_name": "GPT-5.7-Team",
                "priority": 2,
                "visibility": "list",
                "default_reasoning_level": "low",
                "supported_reasoning_levels": [
                  {"effort": "low", "description": "Low"},
                  {"effort": "medium", "description": "Medium"},
                  {"effort": "xhigh", "description": "Extra High"},
                  {"effort": "max", "description": "Max"},
                  {"effort": "ultra", "description": "Unsupported"}
                ],
                "additional_speed_tiers": ["fast"],
                "service_tiers": [{
                  "id": "priority",
                  "name": "Fast",
                  "description": "Higher throughput"
                }]
              }]
            }
            """
        )

        let enriched = CodexModelCatalog.applyingOfficialMetadata(
            to: [RouterModel.inferred(from: "gpt-5.7-team")],
            codexCLI: fakeCLI
        )
        let model = try XCTUnwrap(enriched.first)
        XCTAssertEqual(model.displayName, "GPT-5.7-Team")
        XCTAssertEqual(model.priority, 2)
        XCTAssertEqual(model.reasoningEffort, "xhigh")
        XCTAssertEqual(model.supportedReasoningLevels?.map(\.effort), ["low", "medium", "xhigh", "max", "ultra"])
        XCTAssertEqual(model.additionalSpeedTiers, ["fast"])
        XCTAssertEqual(model.serviceTiers?.map(\.id), ["priority"])
    }

    func testRouterCapabilitiesAreIntersectedWithOfficialCatalog() throws {
        let fakeCLI = try temporaryExecutable(
            named: "codex",
            output: """
            {
              "models": [{
                "slug": "gpt-5.7-team",
                "display_name": "GPT-5.7-Team",
                "priority": 2,
                "visibility": "list",
                "default_reasoning_level": "medium",
                "supported_reasoning_levels": [
                  {"effort": "low", "description": "Low"},
                  {"effort": "medium", "description": "Medium"},
                  {"effort": "high", "description": "High"},
                  {"effort": "xhigh", "description": "Extra High"},
                  {"effort": "max", "description": "Max"},
                  {"effort": "ultra", "description": "Unsupported"}
                ],
                "additional_speed_tiers": ["fast"],
                "service_tiers": [{"id":"priority","name":"Fast","description":"Fast"}]
              }]
            }
            """
        )
        let routerModel = RouterModel(
            codexSlug: "gpt-5.7-team",
            displayName: "Team",
            upstreamModel: "cx/gpt-5.7-team",
            reasoningEffort: "ultra",
            capabilitySource: .routerMetadata,
            supportedReasoningLevels: [
                RouterReasoningLevel(effort: "high", description: "High"),
                RouterReasoningLevel(effort: "xhigh", description: "Extra High"),
                RouterReasoningLevel(effort: "ultra", description: "Unsupported")
            ],
            additionalSpeedTiers: [],
            serviceTiers: []
        )

        let model = try XCTUnwrap(CodexModelCatalog.applyingOfficialMetadata(
            to: [routerModel],
            codexCLI: fakeCLI
        ).first)
        XCTAssertEqual(model.supportedReasoningLevels?.map(\.effort), ["high", "xhigh", "ultra"])
        XCTAssertEqual(model.reasoningEffort, "ultra")
        XCTAssertNil(model.additionalSpeedTiers)
        XCTAssertNil(model.serviceTiers)
    }

    func testProxyReloadsDynamicRoutingWithoutRestart() throws {
        let registryURL = try temporaryFile(
            named: "models.json",
            contents: String(data: try JSONEncoder().encode(ModelRegistryFile(models: [
                RouterModel.inferred(from: "gpt-5.6-sol")
            ])), encoding: .utf8) ?? ""
        )

        let first = SwiftRouterProxy.dynamicRouting(from: registryURL)
        XCTAssertEqual(first.rewriteMap["gpt-5.6-sol"], "cx/gpt-5.6-sol")
        XCTAssertNil(first.rewriteMap["gpt-5.7-team"])

        let updated = ModelRegistryFile(models: [
            RouterModel.inferred(from: "gpt-5.7-team"),
            RouterModel(
                codexSlug: "codex",
                displayName: "Codex",
                upstreamModel: "Codex",
                visible: false,
                notes: "9Router Combo"
            )
        ])
        try JSONEncoder().encode(updated).write(to: registryURL, options: .atomic)

        let second = SwiftRouterProxy.dynamicRouting(from: registryURL)
        XCTAssertNil(second.rewriteMap["gpt-5.6-sol"])
        XCTAssertEqual(second.rewriteMap["gpt-5.7-team"], "cx/gpt-5.7-team")
        XCTAssertEqual(second.fallbackModel, "Codex")
    }

    func testProxyNormalizesUnsupportedBackendEffortWithoutRemovingDelegationFields() {
        var payload: [String: Any] = [
            "reasoning": [
                "effort": "ultra",
                "summary": "auto"
            ],
            "reasoning_effort": "max",
            "delegation": ["enabled": true]
        ]

        XCTAssertTrue(SwiftRouterProxy.normalizeUnsupportedReasoningEffort(in: &payload))
        XCTAssertEqual((payload["reasoning"] as? [String: Any])?["effort"] as? String, "xhigh")
        XCTAssertEqual((payload["reasoning"] as? [String: Any])?["summary"] as? String, "auto")
        XCTAssertEqual(payload["reasoning_effort"] as? String, "xhigh")
        XCTAssertEqual((payload["delegation"] as? [String: Any])?["enabled"] as? Bool, true)
    }

    func testLiveRouterSyncWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["RUN_LIVE_ROUTER_SYNC_TEST"] == "1" else {
            throw XCTSkip("Live 9Router sync test is opt-in.")
        }
        let apiKey = try XCTUnwrap(ProcessInfo.processInfo.environment["LIVE_NINEROUTER_API_KEY"])
        let cliPath = try XCTUnwrap(ProcessInfo.processInfo.environment["LIVE_CODEX_CLI_PATH"])
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexModelSwitcherLiveSync-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: root)
        }

        let paths = AppPaths(home: root)
        let store = ModelRegistryStore(paths: paths)
        let routerModels = try await store.refreshFromRouter(
            apiKey: apiKey,
            targetBaseURL: try XCTUnwrap(URL(string: "https://9router.bigroll.vn"))
        )
        let models = CodexModelCatalog.applyingOfficialMetadata(
            to: routerModels,
            codexCLI: URL(fileURLWithPath: cliPath)
        )
        try store.save(models)
        try CodexModelCatalog.write(
            models: models,
            to: paths.generatedModelCatalog,
            codexCLI: URL(fileURLWithPath: cliPath)
        )

        let data = try Data(contentsOf: paths.generatedModelCatalog)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let catalogModels = try XCTUnwrap(json["models"] as? [[String: Any]])
        XCTAssertEqual(catalogModels.count, models.count)
        XCTAssertFalse(catalogModels.isEmpty)
        XCTAssertEqual(
            catalogModels.filter {
                $0["base_instructions"] == nil
                    || $0["model_messages"] == nil
                    || $0["supported_reasoning_levels"] == nil
                    || $0["shell_type"] == nil
            }.count,
            0
        )
        let sol = try XCTUnwrap(catalogModels.first { $0["slug"] as? String == "gpt-5.6-sol" })
        let solEfforts = (sol["supported_reasoning_levels"] as? [[String: Any]] ?? [])
            .compactMap { $0["effort"] as? String }
        XCTAssertTrue(solEfforts.contains("ultra"))

        let routing = SwiftRouterProxy.dynamicRouting(from: paths.modelRegistry)
        for model in models where model.notes != "9Router Combo" {
            XCTAssertEqual(routing.rewriteMap[model.codexSlug], model.upstreamModel)
        }
    }

    private func catalogModel(from data: Data, slug: String) throws -> [String: Any]? {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]]
        return models?.first { $0["slug"] as? String == slug }
    }

    private func temporaryFile(named name: String, contents: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexModelSwitcherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return url
    }

    private func temporaryExecutable(named name: String, output: String) throws -> URL {
        let escapedOutput = output.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\nprintf '%s' '\(escapedOutput)'\n"
        let url = try temporaryFile(named: name, contents: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func makeSignedTestApp(at appURL: URL, marker: String) throws {
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        let executableURL = macOSURL.appendingPathComponent("TestApp")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executableURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)
        try Data(marker.utf8).write(to: resourcesURL.appendingPathComponent("marker.txt"))

        let info: [String: Any] = [
            "CFBundleExecutable": "TestApp",
            "CFBundleIdentifier": "vn.bigroll.codex-model-switcher.test",
            "CFBundleName": "Codex Model Switcher Test",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "1"
        ]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: contentsURL.appendingPathComponent("Info.plist"))
        try Shell.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", appURL.path])
    }
}
