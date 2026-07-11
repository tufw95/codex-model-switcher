import Foundation

public struct ShellResult: Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool {
        exitCode == 0
    }
}

public enum ShellError: Error, LocalizedError {
    case failed(command: String, args: [String], result: ShellResult)

    public var errorDescription: String? {
        switch self {
        case let .failed(command, args, result):
            let joined = ([command] + args).joined(separator: " ")
            let details = result.stderr.isEmpty ? result.stdout : result.stderr
            return "\(joined) failed with exit code \(result.exitCode). \(details)"
        }
    }
}

public enum Shell {
    @discardableResult
    public static func run(
        _ command: String,
        _ args: [String] = [],
        environment: [String: String]? = nil,
        requireSuccess: Bool = true
    ) throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = args
        if let environment {
            var merged = ProcessInfo.processInfo.environment
            for (key, value) in environment {
                merged[key] = value
            }
            process.environment = merged
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        let stdoutReader = PipeReader(pipe: stdoutPipe)
        let stderrReader = PipeReader(pipe: stderrPipe)
        stdoutReader.start()
        stderrReader.start()
        process.waitUntilExit()

        let stdout = String(data: stdoutReader.waitForData(), encoding: .utf8) ?? ""
        let stderr = String(data: stderrReader.waitForData(), encoding: .utf8) ?? ""
        let result = ShellResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)

        if requireSuccess && !result.succeeded {
            throw ShellError.failed(command: command, args: args, result: result)
        }
        return result
    }
}

private final class PipeReader: @unchecked Sendable {
    private let pipe: Pipe
    private let group = DispatchGroup()
    private let lock = NSLock()
    private var data = Data()

    init(pipe: Pipe) {
        self.pipe = pipe
    }

    func start() {
        group.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            let captured = pipe.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            data = captured
            lock.unlock()
            group.leave()
        }
    }

    func waitForData() -> Data {
        group.wait()
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}
