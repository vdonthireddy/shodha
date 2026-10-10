import Foundation

@MainActor
final class MCPClient: ObservableObject {
    @Published var isServerRunning: Bool = false
    @Published var discoveredTools: [[String: Any]] = []
    
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var requestId: Int = 1
    
    init() {
        startServer()
    }
    
    deinit {
        // Process pipes close automatically on deallocation
    }
    
    func startServer() {
        stopServer()
        
        let fileManager = FileManager.default
        var scriptPath = Bundle.main.path(forResource: "mcp_scheduler_server", ofType: "py") ?? "/Users/donthireddy/code/pa/EchoBuddy/Resources/mcp_scheduler_server.py"
        if !fileManager.fileExists(atPath: scriptPath) {
            scriptPath = "/Users/donthireddy/code/pa/EchoBuddy/Resources/mcp_scheduler_server.py"
        }
        
        guard fileManager.fileExists(atPath: scriptPath) else {
            print("[MCPClient] MCP server script not found at: \(scriptPath)")
            return
        }
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [scriptPath]
        
        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        
        do {
            try proc.run()
            self.process = proc
            self.stdinPipe = inPipe
            self.stdoutPipe = outPipe
            self.isServerRunning = true
            
            // Perform MCP Handshake
            Task {
                await self.handshake()
            }
        } catch {
            print("[MCPClient] Failed to run MCP process: \(error)")
            self.isServerRunning = false
        }
    }
    
    func stopServer() {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        isServerRunning = false
    }
    
    private func handshake() async {
        // 1. initialize
        let initReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:],
                "clientInfo": [
                    "name": "Shodha",
                    "version": "1.0.0"
                ]
            ]
        ]
        _ = sendAndReceive(initReq)
        
        // 2. notifications/initialized
        let notif: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "notifications/initialized"
        ]
        sendNotification(notif)
        
        // 3. tools/list
        await fetchTools()
    }
    
    func fetchTools() async {
        let listReq: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "tools/list",
            "params": [:]
        ]
        
        if let response = sendAndReceive(listReq),
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
        let req: [String: Any] = [
            "jsonrpc": "2.0",
            "id": nextId(),
            "method": "tools/call",
            "params": [
                "name": name,
                "arguments": arguments
            ]
        ]
        
        guard let response = sendAndReceive(req) else {
            return "Failed to communicate with MCP server."
        }
        
        if let result = response["result"] as? [String: Any],
           let contentList = result["content"] as? [[String: Any]],
           let first = contentList.first,
           let text = first["text"] as? String {
            return text
        } else if let error = response["error"] as? [String: Any],
                  let msg = error["message"] as? String {
            return "MCP Tool Error: \(msg)"
        }
        
        return "Tool executed with empty response."
    }
    
    private func nextId() -> Int {
        let cur = requestId
        requestId += 1
        return cur
    }
    
    private func sendNotification(_ dict: [String: Any]) {
        guard let pipe = stdinPipe,
              let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        pipe.fileHandleForWriting.write(data)
        pipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
    }
    
    private func sendAndReceive(_ dict: [String: Any]) -> [String: Any]? {
        guard let inPipe = stdinPipe,
              let outPipe = stdoutPipe,
              let data = try? JSONSerialization.data(withJSONObject: dict) else {
            return nil
        }
        
        // Write message
        inPipe.fileHandleForWriting.write(data)
        inPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
        
        // Read response line synchronously
        var lineData = Data()
        while true {
            let byte = outPipe.fileHandleForReading.readData(ofLength: 1)
            if byte.isEmpty || byte[0] == 10 { // newline
                break
            }
            lineData.append(byte)
        }
        
        guard !lineData.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else {
            return nil
        }
        
        return obj
    }
}
