import CryptoKit
import Foundation

public struct UpdateInstallationPlan: Sendable {
    public let targetAppURL: URL
    public let stagedAppURL: URL
    public let currentAppURL: URL
    public let workingDirectory: URL
    public let installerScriptURL: URL
    public let logURL: URL
    public let requiresAdministratorPrivileges: Bool

    init(
        targetAppURL: URL,
        stagedAppURL: URL,
        currentAppURL: URL,
        workingDirectory: URL,
        installerScriptURL: URL,
        logURL: URL,
        requiresAdministratorPrivileges: Bool
    ) {
        self.targetAppURL = targetAppURL
        self.stagedAppURL = stagedAppURL
        self.currentAppURL = currentAppURL
        self.workingDirectory = workingDirectory
        self.installerScriptURL = installerScriptURL
        self.logURL = logURL
        self.requiresAdministratorPrivileges = requiresAdministratorPrivileges
    }
}

public enum UpdateInstallerError: Error, LocalizedError {
    case invalidDownloadURL
    case insecureDownloadURL
    case missingChecksum
    case downloadFailed
    case sizeMismatch(expected: Int64, actual: Int64)
    case checksumMismatch
    case appNotFound
    case invalidBundle
    case bundleIdentifierMismatch
    case versionMismatch(expected: String, actual: String)
    case buildMismatch(expected: String, actual: String)
    case invalidCodeSignature
    case installerLaunchFailed

    public var errorDescription: String? {
        switch self {
        case .invalidDownloadURL:
            return "The update download URL is invalid."
        case .insecureDownloadURL:
            return "Updates must be downloaded over HTTPS."
        case .missingChecksum:
            return "The update manifest is missing its SHA-256 checksum."
        case .downloadFailed:
            return "The update could not be downloaded."
        case let .sizeMismatch(expected, actual):
            return "The downloaded update has the wrong size (expected \(expected), got \(actual) bytes)."
        case .checksumMismatch:
            return "The update checksum does not match. Nothing was installed."
        case .appNotFound:
            return "The downloaded disk image does not contain Codex Model Switcher."
        case .invalidBundle:
            return "The downloaded app bundle is incomplete."
        case .bundleIdentifierMismatch:
            return "The downloaded app has the wrong bundle identifier."
        case let .versionMismatch(expected, actual):
            return "The downloaded app is version \(actual), not \(expected)."
        case let .buildMismatch(expected, actual):
            return "The downloaded app is build \(actual), not \(expected)."
        case .invalidCodeSignature:
            return "The downloaded app failed code-signature verification."
        case .installerLaunchFailed:
            return "The updater could not start. The current app was left unchanged."
        }
    }
}

public final class UpdateInstaller: @unchecked Sendable {
    private let paths: AppPaths
    private let fileManager: FileManager

    public init(paths: AppPaths = AppPaths(), fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func prepareInstallation(
        manifest: UpdateManifest,
        currentAppURL: URL,
        expectedBundleIdentifier: String
    ) async throws -> UpdateInstallationPlan {
        guard let downloadURL = URL(string: manifest.downloadURL) else {
            throw UpdateInstallerError.invalidDownloadURL
        }
        guard downloadURL.scheme?.lowercased() == "https" else {
            throw UpdateInstallerError.insecureDownloadURL
        }
        guard let expectedChecksum = manifest.sha256?.lowercased(), !expectedChecksum.isEmpty else {
            throw UpdateInstallerError.missingChecksum
        }

        let safeVersion = manifest.version.filter { $0.isLetter || $0.isNumber || ".-_".contains($0) }
        let workingDirectory = paths.updatesDirectory
            .appendingPathComponent("\(safeVersion)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        try? fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: workingDirectory.path)

        do {
            let dmgURL = workingDirectory.appendingPathComponent("update.dmg")
            try await downloadUpdate(from: downloadURL, to: dmgURL)
            try verifyDownload(at: dmgURL, manifest: manifest, expectedChecksum: expectedChecksum)

            let mountURL = workingDirectory.appendingPathComponent("mount", isDirectory: true)
            try fileManager.createDirectory(at: mountURL, withIntermediateDirectories: true)
            try Shell.run(
                "/usr/bin/hdiutil",
                ["attach", "-nobrowse", "-readonly", "-mountpoint", mountURL.path, dmgURL.path]
            )
            defer {
                _ = try? Shell.run("/usr/bin/hdiutil", ["detach", mountURL.path, "-quiet"], requireSuccess: false)
            }

            let sourceAppURL = try findApp(
                in: mountURL,
                expectedBundleIdentifier: expectedBundleIdentifier,
                manifest: manifest
            )
            try verifyCodeSignature(at: sourceAppURL)

            let stagedAppURL = workingDirectory
                .appendingPathComponent("staged", isDirectory: true)
                .appendingPathComponent(sourceAppURL.lastPathComponent, isDirectory: true)
            try fileManager.createDirectory(
                at: stagedAppURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Shell.run("/usr/bin/ditto", ["--norsrc", "--noextattr", sourceAppURL.path, stagedAppURL.path])
            _ = try? Shell.run("/usr/bin/xattr", ["-cr", stagedAppURL.path], requireSuccess: false)
            try verifyCodeSignature(at: stagedAppURL)

            let resolvedCurrentURL = currentAppURL.resolvingSymlinksInPath()
            let targetAppURL = installationTarget(
                currentAppURL: resolvedCurrentURL,
                appName: sourceAppURL.lastPathComponent
            )
            let targetParent = targetAppURL.deletingLastPathComponent()
            let requiresAdministratorPrivileges = !fileManager.isWritableFile(atPath: targetParent.path)
            let scriptURL = workingDirectory.appendingPathComponent("install-update.sh")
            let logURL = paths.updatesDirectory.appendingPathComponent("updater.log")
            try Self.installerScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)

            return UpdateInstallationPlan(
                targetAppURL: targetAppURL,
                stagedAppURL: stagedAppURL,
                currentAppURL: resolvedCurrentURL,
                workingDirectory: workingDirectory,
                installerScriptURL: scriptURL,
                logURL: logURL,
                requiresAdministratorPrivileges: requiresAdministratorPrivileges
            )
        } catch {
            try? fileManager.removeItem(at: workingDirectory)
            throw error
        }
    }

    public func launchInstallation(
        _ plan: UpdateInstallationPlan,
        currentProcessID: Int32,
        relaunch: Bool = true
    ) throws {
        let arguments = installerArguments(
            for: plan,
            currentProcessID: currentProcessID,
            relaunch: relaunch
        )

        if plan.requiresAdministratorPrivileges {
            let command = (["/usr/bin/nohup", "/bin/sh", plan.installerScriptURL.path] + arguments)
                .map(Self.shellQuote)
                .joined(separator: " ") + " >/dev/null 2>&1 &"
            let appleScript = "do shell script \(Self.appleScriptString(command)) with administrator privileges"
            let result = try Shell.run(
                "/usr/bin/osascript",
                ["-e", appleScript],
                requireSuccess: false
            )
            guard result.succeeded else {
                throw UpdateInstallerError.installerLaunchFailed
            }
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [plan.installerScriptURL.path] + arguments
        do {
            try process.run()
        } catch {
            throw UpdateInstallerError.installerLaunchFailed
        }
    }

    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty {
                break
            }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func downloadUpdate(from url: URL, to destinationURL: URL) async throws {
        var request = URLRequest(url: url)
        request.timeoutInterval = 300
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw UpdateInstallerError.downloadFailed
        }
        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private func verifyDownload(
        at url: URL,
        manifest: UpdateManifest,
        expectedChecksum: String
    ) throws {
        if let expectedSize = manifest.sizeBytes {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            let actualSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            guard actualSize == expectedSize else {
                throw UpdateInstallerError.sizeMismatch(expected: expectedSize, actual: actualSize)
            }
        }
        guard try Self.sha256(of: url) == expectedChecksum else {
            throw UpdateInstallerError.checksumMismatch
        }
    }

    private func findApp(
        in mountURL: URL,
        expectedBundleIdentifier: String,
        manifest: UpdateManifest
    ) throws -> URL {
        let candidates = try fileManager.contentsOfDirectory(
            at: mountURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension.lowercased() == "app" }

        for candidate in candidates {
            guard let metadata = bundleMetadata(at: candidate) else {
                continue
            }
            guard metadata.identifier == expectedBundleIdentifier else {
                continue
            }
            guard metadata.version == manifest.version else {
                throw UpdateInstallerError.versionMismatch(expected: manifest.version, actual: metadata.version)
            }
            if let expectedBuild = manifest.build, metadata.build != expectedBuild {
                throw UpdateInstallerError.buildMismatch(expected: expectedBuild, actual: metadata.build)
            }
            return candidate
        }

        if candidates.isEmpty {
            throw UpdateInstallerError.appNotFound
        }
        throw UpdateInstallerError.bundleIdentifierMismatch
    }

    private func bundleMetadata(at appURL: URL) -> (identifier: String, version: String, build: String)? {
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let info = object as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = info["CFBundleVersion"] as? String else {
            return nil
        }
        return (identifier, version, build)
    }

    private func verifyCodeSignature(at appURL: URL) throws {
        let result = try Shell.run(
            "/usr/bin/codesign",
            ["--verify", "--deep", "--strict", appURL.path],
            requireSuccess: false
        )
        guard result.succeeded else {
            throw UpdateInstallerError.invalidCodeSignature
        }
    }

    private func installationTarget(currentAppURL: URL, appName: String) -> URL {
        if currentAppURL.pathExtension.lowercased() == "app",
           !currentAppURL.path.hasPrefix("/Volumes/") {
            return currentAppURL
        }
        return URL(fileURLWithPath: "/Applications", isDirectory: true)
            .appendingPathComponent(appName, isDirectory: true)
    }

    private func installerArguments(
        for plan: UpdateInstallationPlan,
        currentProcessID: Int32,
        relaunch: Bool
    ) -> [String] {
        [
            String(currentProcessID),
            plan.targetAppURL.path,
            plan.stagedAppURL.path,
            plan.currentAppURL.path,
            plan.workingDirectory.path,
            plan.logURL.path,
            relaunch ? "1" : "0"
        ]
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static let installerScript = #"""
    #!/bin/sh
    set -u

    pid="$1"
    target="$2"
    staged="$3"
    fallback="$4"
    workdir="$5"
    log="$6"
    relaunch="$7"

    mkdir -p "$(dirname "$log")"
    exec >>"$log" 2>&1
    echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) Starting update"

    attempts=0
    while kill -0 "$pid" 2>/dev/null && [ "$attempts" -lt 300 ]; do
      sleep 0.1
      attempts=$((attempts + 1))
    done

    parent="$(dirname "$target")"
    name="$(basename "$target")"
    incoming="$parent/.$name.update.$$"
    backup="$parent/.$name.backup.$$"

    reopen_existing() {
      if [ "$relaunch" != "1" ]; then
        return
      fi
      if [ -d "$target" ]; then
        /usr/bin/open "$target" >/dev/null 2>&1 || true
      elif [ -d "$fallback" ]; then
        /usr/bin/open "$fallback" >/dev/null 2>&1 || true
      fi
    }

    rm -rf "$incoming" "$backup"
    if ! /usr/bin/ditto --norsrc --noextattr "$staged" "$incoming"; then
      echo "Failed to copy staged update"
      reopen_existing
      exit 1
    fi
    /usr/bin/xattr -cr "$incoming" >/dev/null 2>&1 || true
    if ! /usr/bin/codesign --verify --deep --strict "$incoming"; then
      echo "Copied update failed code-signature verification"
      rm -rf "$incoming"
      reopen_existing
      exit 1
    fi

    had_current=0
    if [ -e "$target" ]; then
      if ! /bin/mv "$target" "$backup"; then
        echo "Failed to move the current app aside"
        rm -rf "$incoming"
        reopen_existing
        exit 1
      fi
      had_current=1
    fi

    if /bin/mv "$incoming" "$target"; then
      echo "Update installed at $target"
      if [ "$relaunch" = "1" ]; then
        /usr/bin/open "$target" >/dev/null 2>&1 || true
      fi
      rm -rf "$backup" "$workdir"
      exit 0
    fi

    echo "Failed to place the new app; restoring the previous version"
    rm -rf "$incoming"
    if [ "$had_current" = "1" ] && [ -d "$backup" ]; then
      /bin/mv "$backup" "$target" || true
    fi
    reopen_existing
    exit 1
    """#
}
