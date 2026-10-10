import Foundation
import Combine

struct OpenAIModelsResponse: Codable {
    struct ModelObj: Codable {
        let id: String
    }
    let data: [ModelObj]
}

struct OpenAIChatResponse: Codable {
    struct Choice: Codable {
        struct Message: Codable {
            let role: String?
            let content: String?
            let tool_calls: [ToolCall]?
            
            struct ToolCall: Codable {
                let id: String
                let type: String
                let function: FunctionCall
                
                struct FunctionCall: Codable {
                    let name: String
                    let arguments: String
                }
            }
        }
        let message: Message
    }
    let choices: [Choice]
}

struct OpenAIErrorResponse: Codable {
    struct ErrorObj: Codable {
        let message: String?
    }
    let error: ErrorObj?
}

@MainActor
final class OllamaAgent: ObservableObject {
    @Published var baseURL: String = "http://localhost:11434/v1"
    @Published var apiKey: String = ""
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = "mistral:latest"
    @Published var isConnected: Bool = false
    @Published var isGenerating: Bool = false
    @Published var lastResponse: String = "Hi! I am connected to your local Ollama LLM and MCP scheduler. Ask me anything or say 'remind me to...'!"
    @Published var errorMessage: String? = nil
    
    let mcpClient = MCPClient()
    var onReminderScheduled: (() -> Void)?
    
    private var cancellables = Set<AnyCancellable>()
    private let baseURLKey = "Shodha.Ollama.BaseURL"
    private let selectedModelKey = "Shodha.Ollama.SelectedModel"
    private let apiKeyKey = "Shodha.Ollama.ApiKey"
    
    init() {
        let savedBaseURL = UserDefaults.standard.string(forKey: baseURLKey) ?? UserDefaults.standard.string(forKey: "EchoBuddy.Ollama.BaseURL")
        if let savedBaseURL = savedBaseURL, !savedBaseURL.isEmpty {
            self.baseURL = savedBaseURL
        }
        let savedModel = UserDefaults.standard.string(forKey: selectedModelKey) ?? UserDefaults.standard.string(forKey: "EchoBuddy.Ollama.SelectedModel")
        if let savedModel = savedModel, !savedModel.isEmpty {
            self.selectedModel = savedModel
        }
        let savedKey = UserDefaults.standard.string(forKey: apiKeyKey) ?? UserDefaults.standard.string(forKey: "EchoBuddy.Ollama.ApiKey")
        if let savedKey = savedKey {
            self.apiKey = savedKey
        }
        
        mcpClient.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
        
        fetchModels()
    }
    
    func setBaseURL(_ url: String) {
        baseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        fetchModels()
    }
    
    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: selectedModelKey)
    }
    
    func fetchModels() {
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models"
        guard let url = URL(string: endpoint) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
                    let models = decoded.data.map { $0.id }.sorted()
                    self.availableModels = models
                    self.isConnected = true
                    self.errorMessage = nil
                    
                    if !models.isEmpty {
                        // Keep selected if available, or prefer mistral / qwen
                        if !models.contains(self.selectedModel) {
                            if models.contains("mistral:latest") {
                                self.setModel("mistral:latest")
                            } else if models.contains("qwen3.8:latest") {
                                self.setModel("qwen3.8:latest")
                            } else if let first = models.first {
                                self.setModel(first)
                            }
                        }
                    }
                } else {
                    self.isConnected = false
                }
            } catch {
                self.isConnected = false
            }
        }
    }
    
    func sendPrompt(_ prompt: String) async -> String? {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return nil }
        
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            errorMessage = "Invalid API URL: \(baseURL)"
            return nil
        }
        
        isGenerating = true
        errorMessage = nil
        
        // Prepare current date and time context
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a (zzzz)"
        let nowHuman = dateFormatter.string(from: now)
        
        let isoFormatter = ISO8601DateFormatter()
        let nowISO = isoFormatter.string(from: now)
        
        let systemPrompt = """
        Current date and time: \(nowHuman) [ISO: \(nowISO)].
        You are Shodha, a smart desktop companion with access to MCP tools.
        When the user asks to be reminded about something (e.g., at a specific time or in a duration):
        - You MUST call the 'schedule_reminder' tool.
        - Calculate the exact date/time in 'target_time' (ISO format YYYY-MM-DDTHH:MM:SS or relative e.g. 'in 15 minutes').
        - Pass the user's task in 'reminder'.
        - If the user asks what reminders they have, call 'list_reminders'.
        - If the user asks to cancel a reminder, call 'cancel_reminder'.
        Keep your responses clear and concise.
        """
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": cleanPrompt]
        ]
        
        var payload: [String: Any] = [
            "model": selectedModel,
            "messages": messages
        ]
        
        // Include MCP tools if server is running
        let tools = mcpClient.openAIToolsPayload
        if !tools.isEmpty {
            payload["tools"] = tools
            
            let lower = cleanPrompt.lowercased()
            if lower.contains("remind") || lower.contains("alarm") {
                if lower.contains("list") || lower.contains("show") || lower.contains("what") {
                    payload["tool_choice"] = [
                        "type": "function",
                        "function": ["name": "list_reminders"]
                    ]
                } else if lower.contains("cancel") || lower.contains("delete") || lower.contains("remove") {
                    payload["tool_choice"] = [
                        "type": "function",
                        "function": ["name": "cancel_reminder"]
                    ]
                } else {
                    payload["tool_choice"] = [
                        "type": "function",
                        "function": ["name": "schedule_reminder"]
                    ]
                }
            }
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120.0
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            isGenerating = false
            errorMessage = "Failed to encode prompt request."
            return nil
        }
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
                
                guard let choice = decoded.choices.first else {
                    isGenerating = false
                    errorMessage = "Empty choices from LLM."
                    return nil
                }
                
                // Check if the LLM called an MCP Tool!
                if let toolCalls = choice.message.tool_calls, !toolCalls.isEmpty {
                    var toolOutputTexts: [String] = []
                    
                    for call in toolCalls {
                        let fnName = call.function.name
                        let argsJson = call.function.arguments
                        let argsData = argsJson.data(using: .utf8) ?? Data()
                        let argsDict = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]
                        
                        let toolResult = await mcpClient.callTool(name: fnName, arguments: argsDict)
                        
                        // Parse friendly message if JSON returned
                        if let resData = toolResult.data(using: .utf8),
                           let resObj = (try? JSONSerialization.jsonObject(with: resData)) as? [String: Any],
                           let msg = resObj["message"] as? String {
                            toolOutputTexts.append(msg)
                        } else {
                            toolOutputTexts.append(toolResult)
                        }
                    }
                    
                    isGenerating = false
                    self.onReminderScheduled?()
                    
                    let finalAnswer = toolOutputTexts.joined(separator: "\n")
                    self.lastResponse = "⏰ " + finalAnswer
                    self.errorMessage = nil
                    return self.lastResponse
                } else if let content = choice.message.content {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                    let lower = cleanPrompt.lowercased()
                    
                    // Fallback: If LLM returned text or hallucinated [TOOL_CALLS] without structured tool_calls:
                    if lower.contains("remind") && !lower.contains("list") && !lower.contains("cancel") {
                        if let scheduled = await scheduleReminderFallback(from: cleanPrompt) {
                            isGenerating = false
                            self.onReminderScheduled?()
                            self.lastResponse = "⏰ " + scheduled
                            self.errorMessage = nil
                            return self.lastResponse
                        }
                    }
                    
                    isGenerating = false
                    self.lastResponse = trimmed
                    self.errorMessage = nil
                    return trimmed
                } else {
                    isGenerating = false
                    errorMessage = "Received empty response from LLM."
                    return nil
                }
            } else {
                isGenerating = false
                if let errDecoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
                   let msg = errDecoded.error?.message {
                    self.errorMessage = "LLM Error: \(msg)"
                } else if let rawStr = String(data: data, encoding: .utf8) {
                    self.errorMessage = "Error: \(rawStr)"
                } else {
                    self.errorMessage = "Server error (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 500))."
                }
                return nil
            }
        } catch {
            isGenerating = false
            self.errorMessage = "Connection error: \(error.localizedDescription)"
            return nil
        }
    }
    
    private func scheduleReminderFallback(from prompt: String) async -> String? {
        let pattern1 = #"(?i)remind\s+(?:me\s+)?(?:to\s+|about\s+|that\s+)?(.+?)\s+(at\s+.+|in\s+.+|on\s+.+|after\s+.+|tomorrow.*|\d+\s*(?:sec|second|seconds|min|minute|minutes|hr|hour|hours).*)"#
        let pattern2 = #"(?i)remind\s+(?:me\s+)?(?:at\s+|in\s+|after\s+|on\s+)(.+?)\s+(?:to\s+|about\s+|that\s+)(.+)"#
        
        var task: String = prompt
        var timeStr: String = "in 5 minutes"
        
        let nsPrompt = prompt as NSString
        let fullRange = NSRange(location: 0, length: nsPrompt.length)
        
        if let regex2 = try? NSRegularExpression(pattern: pattern2, options: []),
           let match2 = regex2.firstMatch(in: prompt, options: [], range: fullRange),
           match2.numberOfRanges >= 3 {
            timeStr = nsPrompt.substring(with: match2.range(at: 1))
            task = nsPrompt.substring(with: match2.range(at: 2))
        } else if let regex1 = try? NSRegularExpression(pattern: pattern1, options: []),
                  let match1 = regex1.firstMatch(in: prompt, options: [], range: fullRange),
                  match1.numberOfRanges >= 3 {
            task = nsPrompt.substring(with: match1.range(at: 1))
            timeStr = nsPrompt.substring(with: match1.range(at: 2))
        }
        
        let toolResult = await mcpClient.callTool(
            name: "schedule_reminder",
            arguments: [
                "reminder": task.trimmingCharacters(in: .whitespacesAndNewlines).capitalized,
                "target_time": timeStr.trimmingCharacters(in: .whitespacesAndNewlines)
            ]
        )
        
        if let resData = toolResult.data(using: .utf8),
           let resObj = (try? JSONSerialization.jsonObject(with: resData)) as? [String: Any],
           let msg = resObj["message"] as? String {
            return msg
        }
        return toolResult
    }
}
