import Foundation

public struct RouterModel: Codable, Equatable, Identifiable, Sendable {
    public var id: String { codexSlug }
    public var codexSlug: String
    public var displayName: String
    public var upstreamModel: String
    public var aliases: [String]
    public var visible: Bool
    public var reasoningEffort: String
    public var priority: Int
    public var notes: String?

    public init(
        codexSlug: String,
        displayName: String,
        upstreamModel: String,
        aliases: [String] = [],
        visible: Bool = true,
        reasoningEffort: String = "xhigh",
        priority: Int = 100,
        notes: String? = nil
    ) {
        self.codexSlug = codexSlug
        self.displayName = displayName
        self.upstreamModel = upstreamModel
        self.aliases = aliases
        self.visible = visible
        self.reasoningEffort = reasoningEffort
        self.priority = priority
        self.notes = notes
    }

    public static let defaults: [RouterModel] = [
        RouterModel(
            codexSlug: "gpt-5.5",
            displayName: "GPT-5.5",
            upstreamModel: "cx/gpt-5.5",
            aliases: ["openai/gpt-5.5"],
            priority: 0
        ),
        RouterModel(
            codexSlug: "gpt-5.4",
            displayName: "GPT-5.4",
            upstreamModel: "cx/gpt-5.4",
            aliases: ["openai/gpt-5.4"],
            priority: 10
        ),
        RouterModel(
            codexSlug: "gpt-5.4-mini",
            displayName: "GPT-5.4 Mini",
            upstreamModel: "cx/gpt-5.4-mini",
            aliases: ["openai/gpt-5.4-mini"],
            visible: false,
            priority: 20
        )
    ]

    public static func inferred(from rawValue: String) -> RouterModel {
        let cleaned = normalizeSlug(rawValue)
        let codexSlug = cleaned.hasPrefix("cx/") ? String(cleaned.dropFirst(3)) : cleaned
        let upstream = cleaned.hasPrefix("cx/") ? cleaned : "cx/\(codexSlug)"
        return RouterModel(
            codexSlug: codexSlug,
            displayName: displayName(for: codexSlug),
            upstreamModel: upstream,
            aliases: ["openai/\(codexSlug)"],
            priority: 100
        )
    }

    public static func normalizeSlug(_ rawValue: String) -> String {
        var value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: " ", with: "-")

        while value.contains("--") {
            value = value.replacingOccurrences(of: "--", with: "-")
        }

        if value.hasPrefix("openai/") {
            value = String(value.dropFirst("openai/".count))
        }

        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
        if value.hasPrefix("cx/") {
            let suffix = String(value.dropFirst(3)).trimmingCharacters(in: CharacterSet(charactersIn: "-/"))
            return "cx/\(suffix)"
        }
        return value
    }

    public static func displayName(for slug: String) -> String {
        slug
            .split(separator: "-")
            .map { part in
                if part == "gpt" { return "GPT" }
                if part == "mini" { return "Mini" }
                return String(part).uppercased()
            }
            .joined(separator: "-")
            .replacingOccurrences(of: "-Mini", with: " Mini")
    }

    public var rewriteInputs: [String] {
        var values = [codexSlug, "openai/\(codexSlug)"] + aliases
        values.append(upstreamModel)
        var seen = Set<String>()
        return values.filter { value in
            guard !value.isEmpty, !seen.contains(value) else { return false }
            seen.insert(value)
            return true
        }
    }
}

public struct ModelRegistryFile: Codable, Sendable {
    public var version: Int
    public var models: [RouterModel]

    public init(version: Int = 1, models: [RouterModel]) {
        self.version = version
        self.models = models
    }
}
