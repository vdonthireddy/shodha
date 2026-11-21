import Foundation

/// Thread-safe stdio transport for communicating with the Python MCP server off the main thread.
private final class MCPTransport: @unchecked Sendable {
    private let ioQueue = DispatchQueue(label: "com.shodha.mcp.io", qos: .userInitiated)
    private var process: Process?
    private var stdinHandle: FileHandle?
    private var stdoutHandle: FileHandle?
    private var readBuffer = Data()
    private var isStopped = false

    var onTerminated: (@Sendable () -> Void)?

    func start(scriptPath: String) -> Bool {
        return ioQueue.sync {
            stopLocked()
            isStopped = false
            readBuffer.removeAll(keepingCapacity: false)

            guard let pythonPath = Self.resolvePythonExecutable() else {
                print("[MCPClient] Python 3 not found. Install Xcode Command Line Tools or Homebrew Python 3.")
                return false
            }

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: pythonPath)
            proc.arguments = [scriptPath]

            let inPipe = Pipe()
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardInput = inPipe
            proc.standardOutput = outPipe
            proc.standardError = errPipe

            // Drain stderr asynchronously so the child never blocks on a full stderr buffer
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                _ = handle.availableData
            }

            proc.terminationHandler = { [weak self] _ in
                errPipe.fileHandleForReading.readabilityHandler = nil
                self?.onTerminated?()
            }

            do {
                try proc.run()
                self.process = proc
                self.stdinHandle = inPipe.fileHandleForWriting
                self.stdoutHandle = outPipe.fileHandleForReading
                return true
            } catch {
                print("[MCPClient] Failed to run MCP process: \(error)")
                return false
            }
        }
    }

    func stop() {
        ioQueue.sync {
            stopLocked()
        }
    }

    private func stopLocked() {
        isStopped = true
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinHandle = nil
        stdoutHandle = nil
        readBuffer.removeAll(keepingCapacity: false)
    }

    var isRunning: Bool {
        ioQueue.sync {
            process?.isRunning ?? false
        }
    }

    private static func resolvePythonExecutable() -> String? {
        let fm = FileManager.default
        let directCandidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
            "/Library/Developer/CommandLineTools/usr/bin/python3",
            "/Applications/Xcode.app/Contents/Developer/usr/bin/python3"
        ]
        for path in directCandidates where fm.isExecutableFile(atPath: path) {
            return path
        }
        // Only fall back to /usr/bin/python3 shim if developer tools are configured (avoids OS install popup)
        let check = Process()
        check.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
        check.arguments = ["-p"]
        check.standardOutput = Pipe()
        check.standardError = Pipe()
        if (try? check.run()) != nil {
            check.waitUntilExit()
            if check.terminationStatus == 0 && fm.isExecutableFile(atPath: "/usr/bin/python3") {
                return "/usr/bin/python3"
            }
        }
        return nil
    }

    func sendNotification(_ jsonData: Data) {
        ioQueue.async { [weak self] in
            guard let self = self, !self.isStopped, let inHandle = self.stdinHandle else { return }
            var payload = jsonData
            payload.append(0x0A)
            do {
                try inHandle.write(contentsOf: payload)
            } catch {
                print("[MCPClient] Failed writing notification: \(error)")
            }
        }
    }

    func sendRequest(_ jsonData: Data, timeout: TimeInterval = 25.0) async -> Data? {
        return await withCheckedContinuation { continuation in
            ioQueue.async { [weak self] in
                guard let self = self,
                      !self.isStopped,
                      let proc = self.process, proc.isRunning,
                      let inHandle = self.stdinHandle,
                      let outHandle = self.stdoutHandle else {
                    continuation.resume(returning: nil)
                    return
                }

                var payload = jsonData
                payload.append(0x0A)
                do {
                    try inHandle.write(contentsOf: payload)
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                let deadline = Date().addingTimeInterval(timeout)
                let lineData = self.readLineLocked(from: outHandle, deadline: deadline)
                continuation.resume(returning: lineData)
            }
        }
    }

    private func readLineLocked(from handle: FileHandle, deadline: Date) -> Data? {
        let fd = handle.fileDescriptor

        while true {
            if let newlineIdx = readBuffer.firstIndex(of: 0x0A) {
                let line = readBuffer.subdata(in: 0..<newlineIdx)
                readBuffer.removeSubrange(0...newlineIdx)
                return line
            }

            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 || isStopped {
                return nil
            }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let waitMs = Int32(min(max(remaining * 1000.0, 1.0), 500.0))
            let pollRes = Darwin.poll(&pfd, 1, waitMs)
            if pollRes < 0 {
                if errno == EINTR { continue }
                return nil
            }
            if pollRes == 0 {
                continue
            }

            let chunk = handle.availableData
            if chunk.isEmpty {
                // EOF
                return nil
            }
            readBuffer.append(chunk)
        }
    }
}

@MainActor
final class MCPClient: ObservableObject {
    @Published var isServerRunning: Bool = false
    @Published var discoveredTools: [[String: Any]] = []

    private let transport = MCPTransport()
    private var requestId: Int = 1
    private var activeScriptPath: String?
    private var startupTask: Task<Void, Never>?

    init() {
        transport.onTerminated = { [weak self] in
            Task { @MainActor in
                self?.isServerRunning = false
            }
        }
        startServer()
    }

    deinit {
        transport.stop()
    }

    func startServer() {
        startupTask?.cancel()
        stopServer()

        guard let validScriptPath = resolveScriptPath() else {
            print("[MCPClient] MCP server script not found in bundle or relative paths.")
            return
        }
        activeScriptPath = validScriptPath

        if transport.start(scriptPath: validScriptPath) {
            isServerRunning = true
            startupTask = Task { [weak self] in
                await self?.handshake()
            }
        } else {
            isServerRunning = false
        }
    }

    func stopServer() {
        startupTask?.cancel()
        startupTask = nil
        transport.stop()
        isServerRunning = false
    }

    private func resolveScriptPath() -> String? {
        let fileManager = FileManager.default

        if let bundleRes = Bundle.main.path(forResource: "mcp_scheduler_server", ofType: "py"),
           fileManager.fileExists(atPath: bundleRes) {
            return bundleRes
        }

        let relativePaths = [
            "Resources/mcp_scheduler_server.py",
            "../Resources/mcp_scheduler_server.py",
            "../../Resources/mcp_scheduler_server.py"
        ]

        let cwd = fileManager.currentDirectoryPath
        for rel in relativePaths {
            let candidate = (cwd as NSString).appendingPathComponent(rel)
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
        }

        let execURL = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let execDir = execURL.deletingLastPathComponent().path
        for rel in relativePaths {
            let candidate = (execDir as NSString).appendingPathComponent(rel)
            if fileManager.fileExists(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func ensureReady() async -> Bool {
        if !transport.isRunning {
            startServer()
        }
        if let task = startupTask {
            await task.value
        }
        return transport.isRunning
    }

    private func handshake() async {
        let initReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": [
                    "name": "Shodha",
                    "version": "1.1.0"
                ]
            ]
        ]
        _ = await sendAndReceive(initReq, timeout: 5.0)

        let notif: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        ]
        if let notifData = try? JSONSerialization.data(withJSONObject: notif) {
            transport.sendNotification(notifData)
        }

        await fetchTools()
    }

    func fetchTools() async {
        let listReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "tools/list",
            "params": [:]
        ]

        if let response = await sendAndReceive(listReq, timeout: 5.0),
           let result = response["result"] as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            self.discoveredTools = tools
            print("[MCPClient] Discovered \(tools.count) MCP tools: \(tools.compactMap { $0["name"] as? String })")
        }
    }

    var openAIToolsPayload: [[String: Any]] {
        return discoveredTools.compactMap { tool in
            guard let name = tool["name"] as? String,
                  let desc = tool["description"] as? String,
                  let schema = tool["inputSchema"] as? [String: Any] else {
                return nil
            }
            return [
                "type": "function",
                "function": [
                    "name": name,
                    "description": desc,
                    "parameters": schema
                ]
            ]
        }
    }

    func callTool(name: String, arguments: [String: Any]) async -> String {
        guard await ensureReady() else {
            return "{\"error\": \"MCP server is not running.\"}"
        }

        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments
            ]
        ]

        let timeout: TimeInterval = (name == "search_internet" || name == "fetch_webpage") ? 25.0 : 10.0
        guard let response = await sendAndReceive(req, timeout: timeout) else {
            return "{\"error\": \"Timed out or failed communicating with MCP server.\"}"
        }

        if let result = response["result"] as? [String: Any],
           let contentList = result["content"] as? [[String: Any]],
           let first = contentList.first,
           let text = first["text"] as? String {
            return text
        } else if let error = response["error"] as? [String: Any],
                  let msg = error["message"] as? String {
            return "{\"error\": \"MCP Tool Error: \(msg)\"}"
        }

        return "{\"error\": \"Tool executed with empty response.\"}"
    }

    private func nextId() -> Int {
        let cur = requestId
        requestId += 1
        return cur
    }

    private func sendAndReceive(_ dict: [String: Any], timeout: TimeInterval) async -> [String: Any]? {
        guard let reqData = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        guard let lineData = await transport.sendRequest(reqData, timeout: timeout),
              !lineData.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return nil
        }
        return obj
    }
}
