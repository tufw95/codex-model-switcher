import Foundation

public enum ModelCapabilitySource: String, Codable, Sendable {
    case codexCatalog
    case routerMetadata
    case conservative
}

public struct RouterReasoningLevel: Codable, Equatable, Sendable {
    public var effort: String
    public var description: String

    public init(effort: String, description: String) {
        self.effort = effort
        self.description = description
    }
}

public struct RouterServiceTier: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var description: String

    public init(id: String, name: String, description: String) {
        self.id = id
        self.name = name
        self.description = description
    }
}

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
    public var visibilityOverride: Bool?
    public var capabilitySource: ModelCapabilitySource?
    public var supportedReasoningLevels: [RouterReasoningLevel]?
    public var additionalSpeedTiers: [String]?
    public var serviceTiers: [RouterServiceTier]?

    public init(
        codexSlug: String,
        displayName: String,
        upstreamModel: String,
        aliases: [String] = [],
        visible: Bool = true,
        reasoningEffort: String = "xhigh",
        priority: Int = 100,
        notes: String? = nil,
        visibilityOverride: Bool? = nil,
        capabilitySource: ModelCapabilitySource? = nil,
        supportedReasoningLevels: [RouterReasoningLevel]? = nil,
        additionalSpeedTiers: [String]? = nil,
        serviceTiers: [RouterServiceTier]? = nil
    ) {
        self.codexSlug = codexSlug
        self.displayName = displayName
        self.upstreamModel = upstreamModel
        self.aliases = aliases
        self.visible = visible
        self.reasoningEffort = reasoningEffort
        self.priority = priority
        self.notes = notes
        self.visibilityOverride = visibilityOverride
        self.capabilitySource = capabilitySource
        self.supportedReasoningLevels = supportedReasoningLevels
        self.additionalSpeedTiers = additionalSpeedTiers
        self.serviceTiers = serviceTiers
    }

    public static let defaults: [RouterModel] = [
        RouterModel(
            codexSlug: "gpt-5.5",
            displayName: displayName(for: "gpt-5.5"),
            upstreamModel: "cx/gpt-5.5",
            aliases: ["openai/gpt-5.5"],
            priority: defaultPriority(for: "gpt-5.5")
        ),
        RouterModel(
            codexSlug: "gpt-5.4",
            displayName: displayName(for: "gpt-5.4"),
            upstreamModel: "cx/gpt-5.4",
            aliases: ["openai/gpt-5.4"],
            priority: defaultPriority(for: "gpt-5.4")
        ),
        RouterModel(
            codexSlug: "gpt-5.4-mini",
            displayName: displayName(for: "gpt-5.4-mini"),
            upstreamModel: "cx/gpt-5.4-mini",
            aliases: ["openai/gpt-5.4-mini"],
            priority: defaultPriority(for: "gpt-5.4-mini")
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
            visible: defaultVisibility(for: codexSlug),
            priority: defaultPriority(for: codexSlug)
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
        let normalized = normalizeSlug(slug)
        let clean = normalized.hasPrefix("cx/") ? String(normalized.dropFirst(3)) : normalized
        if clean == "codex" {
            return "Codex"
        }

        let parts = clean.split(separator: "-").map(String.init)
        var words: [String] = []
        var index = 0
        while index < parts.count {
            let part = parts[index]
            if part == "gpt" {
                if index + 1 < parts.count, parts[index + 1].contains(".") {
                    words.append(parts[index + 1])
                    index += 2
                    continue
                }
                words.append("GPT")
            } else {
                words.append(displayWord(for: part))
            }
            index += 1
        }
        return words.joined(separator: " ")
    }

    public static func defaultVisibility(for slug: String) -> Bool {
        let normalized = normalizeSlug(slug)
        let clean = normalized.hasPrefix("cx/") ? String(normalized.dropFirst(3)) : normalized
        if clean == "codex" || clean.contains("-review") {
            return false
        }
        if clean.hasPrefix("gpt-5.3-codex") {
            return false
        }
        return true
    }

    public static func defaultPriority(for slug: String) -> Int {
        let normalized = normalizeSlug(slug)
        let clean = normalized.hasPrefix("cx/") ? String(normalized.dropFirst(3)) : normalized
        if clean == "codex" {
            return 0
        }

        let reviewOffset = clean.contains("-review") ? 1 : 0
        let variantOffset: Int
        if clean.contains("-sol") {
            variantOffset = 0
        } else if clean.contains("-terra") {
            variantOffset = 2
        } else if clean.contains("-luna") {
            variantOffset = 4
        } else if clean.contains("-mini") {
            variantOffset = 8
        } else {
            variantOffset = 6
        }

        if let version = gptVersion(from: clean), version.major == 5 {
            let base: Int
            switch version.minor {
            case 6:
                base = 10
            case 5:
                base = 40
            case 4:
                base = 50
            case 3:
                base = 60
            case 7...:
                base = max(2, 10 - ((version.minor - 6) * 4))
            default:
                base = 80 + max(0, 3 - version.minor) * 10
            }
            return base + variantOffset + reviewOffset
        }

        return 200 + variantOffset + reviewOffset
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

    private static func displayWord(for part: String) -> String {
        switch part {
        case "mini":
            return "Mini"
        case "codex":
            return "Codex"
        case "review":
            return "Review"
        case "xhigh":
            return "X High"
        case "low":
            return "Low"
        case "medium":
            return "Medium"
        case "high":
            return "High"
        default:
            guard let first = part.first else { return part }
            return String(first).uppercased() + String(part.dropFirst())
        }
    }

    private static func gptVersion(from slug: String) -> (major: Int, minor: Int)? {
        guard slug.hasPrefix("gpt-") else {
            return nil
        }
        let suffix = slug.dropFirst("gpt-".count)
        guard let versionText = suffix.split(separator: "-", maxSplits: 1).first else {
            return nil
        }
        let parts = versionText.split(separator: ".")
        guard parts.count >= 2,
              let major = Int(parts[0]),
              let minor = Int(parts[1]) else {
            return nil
        }
        return (major, minor)
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
