import Foundation

public struct PreflightReport: Equatable, Sendable {
    public var checks: [PreflightCheck]

    public init(checks: [PreflightCheck]) {
        self.checks = checks
    }

    public var canSwitch: Bool {
        checks.allSatisfy { $0.status != .failed }
    }

    public var summary: String {
        let failed = checks.filter { $0.status == .failed }
        if failed.isEmpty {
            return "Preflight checks passed."
        }
        return failed.map(\.message).joined(separator: "\n")
    }
}

public struct PreflightCheck: Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        case passed
        case warning
        case failed
    }

    public var title: String
    public var message: String
    public var status: Status

    public init(title: String, message: String, status: Status) {
        self.title = title
        self.message = message
        self.status = status
    }
}

public enum PreflightError: Error, LocalizedError {
    case failed(PreflightReport)

    public var errorDescription: String? {
        switch self {
        case let .failed(report):
            return report.summary
        }
    }
}
