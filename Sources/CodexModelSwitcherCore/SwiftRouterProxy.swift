import Foundation
import Network

public struct SwiftRouterProxyConfiguration: Sendable {
    public var host: String
    public var port: UInt16
    public var target: URL
    public var rewriteMap: [String: String]
    public var rewriteFrom: Set<String>
    public var rewriteTo: String
    public var rewriteOpenAIModels: Bool
    public var rewriteAllUnmapped: Bool
    public var modelCatalog: URL?
    public var fallbackModel: String?
    public var apiKeyFile: URL?

    public init(
        host: String = "127.0.0.1",
        port: UInt16 = 9783,
        target: URL = URL(string: "https://9router.bigroll.vn")!,
        rewriteMap: [String: String] = [:],
        rewriteFrom: Set<String> = [],
        rewriteTo: String,
        rewriteOpenAIModels: Bool = true,
        rewriteAllUnmapped: Bool = true,
        modelCatalog: URL? = nil,
        fallbackModel: String? = nil,
        apiKeyFile: URL? = nil
    ) {
        self.host = host
        self.port = port
        self.target = target
        self.rewriteMap = rewriteMap
        self.rewriteFrom = rewriteFrom
        self.rewriteTo = rewriteTo
        self.rewriteOpenAIModels = rewriteOpenAIModels
        self.rewriteAllUnmapped = rewriteAllUnmapped
        self.modelCatalog = modelCatalog
        self.fallbackModel = fallbackModel
        self.apiKeyFile = apiKeyFile
    }
}

public enum SwiftRouterProxyError: Error, LocalizedError {
    case missingValue(String)
    case invalidTarget(String)
    case invalidPort(String)
    case missingRouterAPIKey

    public var errorDescription: String? {
        switch self {
        case let .missingValue(flag):
            return "Missing value for \(flag)."
        case let .invalidTarget(value):
            return "Invalid target URL: \(value)"
        case let .invalidPort(value):
            return "Invalid port: \(value)"
        case .missingRouterAPIKey:
            return "The local 9Router API key file is missing or empty."
        }
    }
}

public final class SwiftRouterProxy: @unchecked Sendable {
    private let configuration: SwiftRouterProxyConfiguration
    private let queue = DispatchQueue(label: "codex-model-switcher.proxy")

    public init(configuration: SwiftRouterProxyConfiguration) {
        self.configuration = configuration
    }

    public static func runFromCommandLine(arguments: [String] = CommandLine.arguments) throws -> Never {
        let configuration = try parse(arguments: Array(arguments.dropFirst()))
        let server = SwiftRouterProxy(configuration: configuration)
        try server.start()
        dispatchMain()
    }

    public func start() throws {
        guard let port = NWEndpoint.Port(rawValue: configuration.port) else {
            throw SwiftRouterProxyError.invalidPort(String(configuration.port))
        }
        let listener = try NWListener(using: .tcp, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        print("swift proxy listening on \(configuration.host):\(configuration.port)")
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, accumulator: RequestAccumulator())
    }

    private func receive(on connection: NWConnection, accumulator: RequestAccumulator) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                accumulator.data.append(data)
                if let request = HTTPRequest.parse(accumulator.data) {
                    self.respond(to: request, on: connection)
                    return
                }
            }
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self.receive(on: connection, accumulator: accumulator)
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        Task {
            let response: Data
            do {
                response = try await buildResponse(for: request)
            } catch {
                let body = #"{"error":{"message":"9Router proxy error: \#(error.localizedDescription)"}}"#
                    .data(using: .utf8) ?? Data()
                response = HTTPResponse(status: 502, headers: ["Content-Type": "application/json"], body: body).serialized()
            }
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func buildResponse(for request: HTTPRequest) async throws -> Data {
        if request.method == "GET", request.path == "/health" {
            return HTTPResponse(status: 200, headers: ["Content-Type": "text/plain"], body: Data("ok\n".utf8)).serialized()
        }

        if request.method == "GET", isModelListPath(request.pathOnly), let catalog = configuration.modelCatalog,
           FileManager.default.fileExists(atPath: catalog.path) {
            let body = try Data(contentsOf: catalog)
            return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: body).serialized()
        }

        return try await forward(request)
    }

    private func forward(_ request: HTTPRequest) async throws -> Data {
        let primaryBody = maybeRewriteBody(request.body, headers: request.headers)
        var result = try await performUpstreamRequest(request, body: primaryBody)

        if isTransientStatus(result.status) {
            log("upstream returned \(result.status); retrying selected model")
            try? await Task.sleep(nanoseconds: 400_000_000)
            result = try await performUpstreamRequest(request, body: primaryBody)
        }

        if isTransientStatus(result.status),
           let fallbackModel = configuration.fallbackModel,
           let fallbackBody = bodyBySettingModel(request.body, headers: request.headers, model: fallbackModel),
           fallbackBody != primaryBody {
            log("upstream still returned \(result.status); falling back to \(fallbackModel)")
            result = try await performUpstreamRequest(request, body: fallbackBody)
        }

        var body = result.body
        let normalizeTitle = isSingleTitleSchemaRequest(request.body, headers: request.headers)
        if normalizeTitle, result.contentType.lowercased().contains("text/event-stream") {
            body = normalizeTitleSSE(body)
        }

        return HTTPResponse(status: result.status, headers: result.headers, body: body).serialized()
    }

    private func performUpstreamRequest(_ request: HTTPRequest, body outgoingBody: Data) async throws -> UpstreamResult {
        var urlRequest = URLRequest(url: upstreamURL(for: request.path))
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = outgoingBody.isEmpty ? nil : outgoingBody
        urlRequest.timeoutInterval = 300

        let routerAPIKey: String?
        if let apiKeyFile = configuration.apiKeyFile {
            guard let key = Self.readAPIKey(from: apiKeyFile) else {
                throw SwiftRouterProxyError.missingRouterAPIKey
            }
            routerAPIKey = key
        } else {
            routerAPIKey = nil
        }
        for (name, value) in Self.upstreamHeaders(
            from: request.headers,
            routerAPIKey: routerAPIKey
        ) {
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        if !outgoingBody.isEmpty {
            urlRequest.setValue(String(outgoingBody.count), forHTTPHeaderField: "Content-Length")
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        let contentType = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            guard let key = key as? String else { continue }
            let lower = key.lowercased()
            if ["transfer-encoding", "content-length", "connection"].contains(lower) {
                continue
            }
            headers[key] = "\(value)"
        }
        return UpstreamResult(
            status: http.statusCode,
            headers: headers,
            body: data,
            contentType: contentType
        )
    }

    private func upstreamURL(for path: String) -> URL {
        var components = URLComponents(url: configuration.target, resolvingAgainstBaseURL: false)!
        let targetPath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let requestPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let pathPart = requestPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        if targetPath.isEmpty {
            components.path = "/" + pathPart
        } else {
            components.path = "/" + targetPath + "/" + pathPart
        }
        if let query = requestPath.split(separator: "?", maxSplits: 1).dropFirst().first {
            components.percentEncodedQuery = String(query)
        }
        return components.url!
    }

    private func isModelListPath(_ path: String) -> Bool {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed == "models" || trimmed == "v1/models"
    }

    private func maybeRewriteBody(_ body: Data, headers: [String: String]) -> Data {
        guard !body.isEmpty, contentType(headers).contains("json"),
              let object = try? JSONSerialization.jsonObject(with: body),
              var payload = object as? [String: Any] else {
            return body
        }

        var changed = false
        if let model = payload["model"] as? String,
           let rewritten = rewrittenModel(model),
           rewritten != model {
            payload["model"] = rewritten
            changed = true
        }

        guard changed,
              let rewritten = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return body
        }
        return rewritten
    }

    private func bodyBySettingModel(_ body: Data, headers: [String: String], model: String) -> Data? {
        guard !body.isEmpty, contentType(headers).contains("json"),
              let object = try? JSONSerialization.jsonObject(with: body),
              var payload = object as? [String: Any] else {
            return nil
        }
        payload["model"] = model
        return try? JSONSerialization.data(withJSONObject: payload, options: [])
    }

    private func rewrittenModel(_ model: String) -> String? {
        if let mapped = configuration.rewriteMap[model] {
            return mapped
        }
        if model.hasPrefix("cx/") {
            return nil
        }
        if configuration.rewriteFrom.contains(model) {
            return configuration.rewriteTo
        }
        if configuration.rewriteOpenAIModels, model.hasPrefix("gpt-") || model.hasPrefix("openai/gpt-") {
            return configuration.rewriteTo
        }
        if configuration.rewriteAllUnmapped {
            return configuration.rewriteTo
        }
        return nil
    }

    private func contentType(_ headers: [String: String]) -> String {
        headers.first { $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame }?.value.lowercased() ?? ""
    }

    private func isTransientStatus(_ status: Int) -> Bool {
        status == 502 || status == 503 || status == 504
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("[Codex Switch] \(message)\n".utf8))
    }

    private func isSingleTitleSchemaRequest(_ body: Data, headers: [String: String]) -> Bool {
        guard !body.isEmpty, contentType(headers).contains("json"),
              let object = try? JSONSerialization.jsonObject(with: body),
              let payload = object as? [String: Any],
              let text = payload["text"] as? [String: Any],
              let format = text["format"] as? [String: Any],
              format["type"] as? String == "json_schema",
              let schema = format["schema"] as? [String: Any],
              schema["type"] as? String == "object",
              let props = schema["properties"] as? [String: Any],
              props["title"] is [String: Any],
              let required = schema["required"] as? [String],
              required == ["title"] else {
            return false
        }
        return true
    }

    private func normalizeTitleSSE(_ data: Data) -> Data {
        guard let text = String(data: data, encoding: .utf8) else {
            return data
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        let normalized = lines.map { line -> String in
            guard line.hasPrefix("data:") else {
                return String(line)
            }
            let payloadText = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard !payloadText.isEmpty, payloadText != "[DONE]",
                  let payloadData = payloadText.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: payloadData),
                  var event = object as? [String: Any] else {
                return String(line)
            }
            normalizeTitleEvent(&event)
            guard let out = try? JSONSerialization.data(withJSONObject: event, options: []),
                  let outText = String(data: out, encoding: .utf8) else {
                return String(line)
            }
            return "data: \(outText)"
        }.joined(separator: "\n")
        return Data(normalized.utf8)
    }

    private func normalizeTitleEvent(_ event: inout [String: Any]) {
        if event["type"] as? String == "response.output_text.done", let text = event["text"] as? String {
            event["text"] = titleJSONText(text)
            return
        }
        if event["type"] as? String == "response.output_item.done",
           var item = event["item"] as? [String: Any] {
            normalizeTitleOutputItem(&item)
            event["item"] = item
            return
        }
        if event["type"] as? String == "response.completed",
           var response = event["response"] as? [String: Any],
           var output = response["output"] as? [[String: Any]] {
            for index in output.indices {
                normalizeTitleOutputItem(&output[index])
            }
            response["output"] = output
            event["response"] = response
        }
    }

    private func normalizeTitleOutputItem(_ item: inout [String: Any]) {
        guard item["type"] as? String == "message",
              var content = item["content"] as? [[String: Any]] else {
            return
        }
        for index in content.indices {
            if content[index]["type"] as? String == "output_text",
               let text = content[index]["text"] as? String {
                content[index]["text"] = titleJSONText(text)
            }
        }
        item["content"] = content
    }

    private func titleJSONText(_ text: String) -> String {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else {
            return text
        }
        if let data = stripped.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let dict = object as? [String: Any],
           dict["title"] is String {
            return text
        }
        let object = ["title": stripped]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let json = String(data: data, encoding: .utf8) else {
            return text
        }
        return json
    }

    private static func parse(arguments: [String]) throws -> SwiftRouterProxyConfiguration {
        var host = "127.0.0.1"
        var port: UInt16 = 9783
        var target = URL(string: "https://9router.bigroll.vn")!
        var rewriteMap: [String: String] = [:]
        var rewriteFrom = Set<String>()
        var rewriteTo: String?
        var rewriteOpenAIModels = false
        var rewriteAllUnmapped = true
        var modelCatalog: URL?
        var fallbackModel: String?
        var apiKeyFile: URL?

        var index = 0
        while index < arguments.count {
            let arg = arguments[index]
            func value() throws -> String {
                guard index + 1 < arguments.count else {
                    throw SwiftRouterProxyError.missingValue(arg)
                }
                index += 1
                return arguments[index]
            }

            switch arg {
            case "--proxy":
                break
            case "--host":
                host = try value()
            case "--port":
                let raw = try value()
                guard let parsed = UInt16(raw) else { throw SwiftRouterProxyError.invalidPort(raw) }
                port = parsed
            case "--target":
                let raw = try value()
                guard let parsed = URL(string: raw) else { throw SwiftRouterProxyError.invalidTarget(raw) }
                target = parsed
            case "--rewrite-map":
                let raw = try value()
                let parts = raw.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    rewriteMap[parts[0]] = parts[1]
                }
            case "--rewrite-from":
                rewriteFrom.insert(try value())
            case "--rewrite-to":
                rewriteTo = try value()
            case "--rewrite-openai-models":
                rewriteOpenAIModels = true
            case "--no-rewrite-unmapped":
                rewriteAllUnmapped = false
            case "--model-catalog":
                modelCatalog = URL(fileURLWithPath: try value())
            case "--fallback-to":
                fallbackModel = try value()
            case "--api-key-file":
                apiKeyFile = URL(fileURLWithPath: try value())
            default:
                break
            }
            index += 1
        }

        return SwiftRouterProxyConfiguration(
            host: host,
            port: port,
            target: target,
            rewriteMap: rewriteMap,
            rewriteFrom: rewriteFrom,
            rewriteTo: rewriteTo ?? "cx/codex",
            rewriteOpenAIModels: rewriteOpenAIModels,
            rewriteAllUnmapped: rewriteAllUnmapped,
            modelCatalog: modelCatalog,
            fallbackModel: fallbackModel,
            apiKeyFile: apiKeyFile
        )
    }

    static func upstreamHeaders(
        from incomingHeaders: [String: String],
        routerAPIKey: String?
    ) -> [String: String] {
        var outgoing: [String: String] = [:]
        for (name, value) in incomingHeaders {
            let lower = name.lowercased()
            if ["host", "content-length", "transfer-encoding", "connection"].contains(lower) {
                continue
            }
            if routerAPIKey != nil && (
                lower == "authorization"
                || lower == "cookie"
                || lower.hasPrefix("chatgpt-")
                || lower.hasPrefix("x-openai-")
                || lower.hasPrefix("x-oai-")
            ) {
                continue
            }
            outgoing[name] = lower == "accept-encoding" ? "identity" : value
        }
        if let routerAPIKey {
            outgoing["Authorization"] = "Bearer \(routerAPIKey)"
        }
        return outgoing
    }

    static func readAPIKey(from url: URL) -> String? {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        for line in content.components(separatedBy: .newlines) {
            let lowered = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard lowered.hasPrefix("ninerouter_api_key")
                || lowered.hasPrefix("nine_router_api_key")
                || lowered.hasPrefix("9router_api_key")
                || lowered.hasPrefix("ninerouter_token")
                || lowered.hasPrefix("nine_router_token")
                || lowered.hasPrefix("export ninerouter_api_key") else {
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                continue
            }
            let value = String(line[line.index(after: equals)...])
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first
                .map(String.init) ?? ""
            let clean = value.trimmingCharacters(
                in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'"))
            )
            if !clean.isEmpty {
                return clean
            }
        }
        return nil
    }
}

private struct UpstreamResult {
    var status: Int
    var headers: [String: String]
    var body: Data
    var contentType: String
}

private struct HTTPRequest {
    var method: String
    var path: String
    var pathOnly: String
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        let headerData = data[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            return nil
        }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard requestParts.count >= 2 else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = String(line[..<colon])
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }

        let contentLength = headers.first { $0.key.caseInsensitiveCompare("Content-Length") == .orderedSame }
            .flatMap { Int($0.value) } ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else {
            return nil
        }
        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        let path = requestParts[1]
        let pathOnly = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        return HTTPRequest(method: requestParts[0], path: path, pathOnly: pathOnly, headers: headers, body: body)
    }
}

private final class RequestAccumulator: @unchecked Sendable {
    var data = Data()
}

private struct HTTPResponse {
    var status: Int
    var headers: [String: String]
    var body: Data

    func serialized() -> Data {
        var data = Data()
        data.append(Data("HTTP/1.1 \(status) \(reasonPhrase)\r\n".utf8))
        var outputHeaders = headers
        outputHeaders["Content-Length"] = String(body.count)
        outputHeaders["Connection"] = "close"
        for (key, value) in outputHeaders {
            data.append(Data("\(key): \(value)\r\n".utf8))
        }
        data.append(Data("\r\n".utf8))
        data.append(body)
        return data
    }

    private var reasonPhrase: String {
        switch status {
        case 200: "OK"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        default: "OK"
        }
    }
}
