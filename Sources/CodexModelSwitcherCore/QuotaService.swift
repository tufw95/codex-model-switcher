import Foundation

public struct CodexQuotaWindow: Codable, Equatable, Identifiable, Sendable {
    public var id: String { key }
    public let key: String
    public let used: Double
    public let total: Double
    public let remaining: Double
    public let resetAt: String?
    public let unlimited: Bool

    public init(
        key: String,
        used: Double,
        total: Double,
        remaining: Double,
        resetAt: String?,
        unlimited: Bool
    ) {
        self.key = key
        self.used = used
        self.total = total
        self.remaining = remaining
        self.resetAt = resetAt
        self.unlimited = unlimited
    }
}

public struct CodexQuotaAccount: Codable, Equatable, Identifiable, Sendable {
    public struct ResetCredits: Codable, Equatable, Sendable {
        public let availableCount: Int
    }

    public let id: String
    public let provider: String
    public let label: String
    public let plan: String
    public let limitReached: Bool
    public let quotas: [CodexQuotaWindow]
    public let resetCredits: ResetCredits
    public let status: String
    public let errorCode: String?

    public var primaryQuota: CodexQuotaWindow? {
        quotas.first(where: { $0.key == "session" }) ?? quotas.first
    }
}

public struct CodexQuotaSummary: Codable, Equatable, Sendable {
    public let accounts: Int
    public let availableAccounts: Int
    public let unavailableAccounts: Int
    public let lowestRemaining: Double?
}

public struct CodexQuotaResponse: Codable, Equatable, Sendable {
    public let object: String
    public let generatedAt: String
    public let summary: CodexQuotaSummary
    public let data: [CodexQuotaAccount]
}

public enum QuotaServiceError: Error, LocalizedError, Equatable {
    case unsupported
    case unauthorized
    case invalidResponse
    case serverError(Int)

    public var errorDescription: String? {
        switch self {
        case .unsupported:
            return "This 9Router server does not provide quota tracking yet."
        case .unauthorized:
            return "The 9Router API key could not access quota data."
        case .invalidResponse:
            return "9Router returned an invalid quota response."
        case let .serverError(statusCode):
            return "9Router quota is temporarily unavailable (HTTP \(statusCode))."
        }
    }
}

public final class QuotaService: @unchecked Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(
        apiKey: String,
        targetBaseURL: URL,
        forceRefresh: Bool = false
    ) async throws -> CodexQuotaResponse {
        let safeBaseURL = try RouterEndpoint.normalizedURL(from: targetBaseURL.absoluteString)
        var components = URLComponents(
            url: Self.quotaURL(from: safeBaseURL),
            resolvingAgainstBaseURL: false
        )
        if forceRefresh {
            components?.queryItems = [URLQueryItem(name: "refresh", value: "1")]
        }
        guard let url = components?.url else {
            throw QuotaServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 25

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaServiceError.invalidResponse
        }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw QuotaServiceError.unauthorized
        case 404, 405:
            throw QuotaServiceError.unsupported
        default:
            throw QuotaServiceError.serverError(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(CodexQuotaResponse.self, from: data)
        } catch {
            throw QuotaServiceError.invalidResponse
        }
    }

    public static func quotaURL(from baseURL: URL) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = (components?.path ?? "")
            .split(separator: "/")
            .map(String.init)
            .joined(separator: "/")
        components?.path = basePath.isEmpty ? "/v1/quota" : "/\(basePath)/v1/quota"
        components?.query = nil
        components?.fragment = nil
        return components?.url ?? baseURL.appendingPathComponent("v1/quota")
    }
}
