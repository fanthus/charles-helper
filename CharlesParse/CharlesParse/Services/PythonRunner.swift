import Foundation

enum PythonRunnerError: LocalizedError {
    case pythonNotFound
    case scriptNotFound
    case processFailed(String)
    case invalidJSON(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return """
            未找到 python3。请安装 Python 3（推荐：brew install python），\
            或设置环境变量 CHARLES_PARSE_PYTHON 指向解释器路径。
            """
        case .scriptNotFound:
            return "未在 App 资源中找到 chls_gzip.py。"
        case .processFailed(let message):
            return message
        case .invalidJSON(let detail):
            return "解析 JSON 失败：\(detail)"
        }
    }
}

struct PythonRunner {
    static func parse(chlsURL: URL) async throws -> ChlsParseResponse {
        let python = try resolvePythonExecutable()
        let script = try resolveScriptPath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        process.arguments = [script, "--json", chlsURL.path]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrText = String(data: stderrData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let message = stderrText.isEmpty
                ? "解析失败（退出码 \(process.terminationStatus)）"
                : stderrText
            throw PythonRunnerError.processFailed(message)
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(ChlsParseResponse.self, from: stdoutData)
        } catch {
            let preview = String(data: stdoutData.prefix(200), encoding: .utf8) ?? ""
            throw PythonRunnerError.invalidJSON("\(error.localizedDescription)\n\(preview)")
        }
    }

    private static func resolvePythonExecutable() throws -> String {
        if let custom = ProcessInfo.processInfo.environment["CHARLES_PARSE_PYTHON"],
           !custom.isEmpty,
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }

        var candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        if let home = ProcessInfo.processInfo.environment["HOME"], !home.isEmpty {
            candidates.append("\(home)/.pyenv/shims/python3")
        }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }

        throw PythonRunnerError.pythonNotFound
    }

    private static func resolveScriptPath() throws -> String {
        if let bundled = Bundle.main.path(forResource: "chls_gzip", ofType: "py") {
            return bundled
        }

        let devPath = Bundle.main.bundlePath
            .replacingOccurrences(of: "/CharlesParse.app", with: "")
        let repoScript = (devPath as NSString)
            .deletingLastPathComponent
            .appending("/chls_gzip.py")
        if FileManager.default.fileExists(atPath: repoScript) {
            return repoScript
        }

        throw PythonRunnerError.scriptNotFound
    }
}
