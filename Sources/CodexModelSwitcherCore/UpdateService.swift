import Foundation

public struct UpdateSettings: Codable, Equatable, Sendable {
    public var checkOnLaunch: Bool
    public var manifestURL: String

    public init(
        checkOnLaunch: Bool = true,
        manifestURL: String = "https://raw.githubusercontent.com/bigroll/codex-model-switcher/main/update.json"
    ) {
        self.checkOnLaunch = checkOnLaunch
        self.manifestURL = manifestURL
    }
}

public struct UpdateManifest: Codable, Equatable, Sendable {
    public var version: String
    public var build: String?
    public var downloadURL: String
    public var releaseNotesURL: String?
    public var minimumMacOS: String?
    public var message: String?

    enum CodingKeys: String, CodingKey {
        case version
        case build
        case downloadURL = "download_url"
        case releaseNotesURL = "release_notes_url"
        case minimumMacOS = "minimum_macos"
        case message
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case disabled
    case upToDate
    case available(UpdateManifest)
}

public final class UpdateService: @unchecked Sendable {
    private let paths: AppPaths

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
    }

    public func loadSettings() -> UpdateSettings {
        guard let data = try? Data(contentsOf: paths.updateSettings),
              let settings = try? JSONDecoder().decode(UpdateSettings.self, from: data) else {
            return UpdateSettings()
        }
        return settings
    }

    public func saveSettings(_ settings: UpdateSettings) throws {
        try paths.ensureBaseDirectories()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try data.write(to: paths.updateSettings, options: .atomic)
    }

    public func check(currentVersion: String, settings: UpdateSettings) async throws -> UpdateCheckResult {
        guard settings.checkOnLaunch else {
            return .disabled
        }
        guard let url = URL(string: settings.manifestURL), !settings.manifestURL.isEmpty else {
            return .disabled
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
        if Version(manifest.version) > Version(currentVersion) {
            return .available(manifest)
        }
        return .upToDate
    }
}

public struct Version: Comparable, Sendable {
    private let parts: [Int]
    private let raw: String

    public init(_ raw: String) {
        self.raw = raw
        self.parts = raw
            .split { character in
                character == "." || character == "-" || character == "_"
            }
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    public static func < (lhs: Version, rhs: Version) -> Bool {
        let count = max(lhs.parts.count, rhs.parts.count)
        for index in 0..<count {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right {
                return left < right
            }
        }
        return lhs.raw < rhs.raw
    }
}
