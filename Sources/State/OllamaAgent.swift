import Foundation
import Combine

enum ChatRole: Equatable, Sendable {
    case user
    case assistant
    case reminder
}

struct ChatMessage: Identifiable, Equatable, Sendable {
    let id: UUID
    let role: ChatRole
    let text: String
    let timestamp: Date
    let badge: String?

    init(id: UUID = UUID(), role: ChatRole, text: String, timestamp: Date = Date(), badge: String? = nil) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
        self.badge = badge
    }
}

struct OpenAIModelsResponse: Codable, Sendable {
    struct ModelObj: Codable, Sendable {
        let id: String
    }
    let data: [ModelObj]
}

struct OpenAIChatResponse: Codable, Sendable {
    struct Choice: Codable, Sendable {
        struct Message: Codable, Sendable {
            let role: String?
            let content: String?
            let tool_calls: [ToolCall]?

            struct ToolCall: Codable, Sendable {
                let id: String?
                let type: String?
                let function: FunctionCall

                struct FunctionCall: Codable, Sendable {
                    let name: String
                    let arguments: String
                }
            }
        }
        let message: Message
    }
    let choices: [Choice]
}

struct OpenAIErrorResponse: Codable, Sendable {
    struct ErrorObj: Codable, Sendable {
        let message: String?
    }
    let error: ErrorObj?
}

@MainActor
final class OllamaAgent: ObservableObject {
    @Published var baseURL: String = "http://localhost:11434/v1"
    @Published var apiKey: String = ""
    @Published var customPersona: String = ""
    @Published var availableModels: [String] = []
    @Published var selectedModel: String = "mistral:latest"
    @Published var isConnected: Bool = false
    @Published var isGenerating: Bool = false
    @Published var lastResponse: String = "Hi! I am Shodha, connected to your local LLM and MCP tools. Ask me anything, search the web, save notes, calculate, or set reminders!"
    @Published var messages: [ChatMessage] = []
    @Published var errorMessage: String? = nil
    @Published var activeToolStatus: String? = nil

    let mcpClient = MCPClient()
    var onReminderScheduled: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var fetchModelsTask: Task<Void, Never>?
    private var activeGenerationTask: Task<String?, Never>?

    private let baseURLKey = "Shodha.Ollama.BaseURL"
    private let selectedModelKey = "Shodha.Ollama.SelectedModel"
    private let apiKeyKey = "Shodha.Ollama.ApiKey"
    private let personaKey = "Shodha.Ollama.CustomPersona"

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
        if let savedPersona = UserDefaults.standard.string(forKey: personaKey) {
            self.customPersona = savedPersona
        }

        self.messages = [
            ChatMessage(role: .assistant, text: self.lastResponse)
        ]

        mcpClient.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        fetchModels()
    }

    func setBaseURL(_ url: String, debounced: Bool = true) {
        baseURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(baseURL, forKey: baseURLKey)
        fetchModels(debounced: debounced)
    }

    func setAPIKey(_ key: String) {
        apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(apiKey, forKey: apiKeyKey)
    }

    func setModel(_ model: String) {
        selectedModel = model
        UserDefaults.standard.set(model, forKey: selectedModelKey)
    }

    func setCustomPersona(_ persona: String) {
        customPersona = persona
        UserDefaults.standard.set(persona, forKey: personaKey)
    }

    func clearChat() {
        cancelGeneration()
        errorMessage = nil
        let greeting = "Chat cleared. How can I help you?"
        lastResponse = greeting
        messages = [ChatMessage(role: .assistant, text: greeting)]
    }

    func appendReminderNotificationMessage(_ text: String) {
        let formatted = "⏰ REMINDER: \(text)"
        lastResponse = formatted
        messages.append(ChatMessage(role: .reminder, text: formatted, badge: "Reminder"))
        trimMessagesIfNeeded()
    }

    func cancelGeneration() {
        activeGenerationTask?.cancel()
        activeGenerationTask = nil
        isGenerating = false
        activeToolStatus = nil
    }

    func fetchModels(debounced: Bool = false) {
        fetchModelsTask?.cancel()
        let currentBaseURL = baseURL
        let currentKey = apiKey

        fetchModelsTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if Task.isCancelled { return }
            }

            let endpoint = currentBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models"
            guard let url = URL(string: endpoint) else {
                self?.isConnected = false
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 6.0
            if !currentKey.isEmpty {
                request.setValue("Bearer \(currentKey)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if Task.isCancelled { return }
                guard let self = self else { return }

                if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                    let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
                    let models = decoded.data.map { $0.id }.sorted()
                    self.availableModels = models
                    self.isConnected = true
                    self.errorMessage = nil

                    if !models.isEmpty && !models.contains(self.selectedModel) {
                        if models.contains("mistral:latest") {
                            self.setModel("mistral:latest")
                        } else if let qwen = models.first(where: { $0.lowercased().hasPrefix("qwen") }) {
                            self.setModel(qwen)
                        } else if let first = models.first {
                            self.setModel(first)
                        }
                    }
                } else {
                    self.isConnected = false
                }
            } catch {
                if !Task.isCancelled {
                    self?.isConnected = false
                }
            }
        }
    }

    func sendPrompt(_ prompt: String) async -> String? {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return nil }

        cancelGeneration()

        messages.append(ChatMessage(role: .user, text: cleanPrompt))
        trimMessagesIfNeeded()

        let task = Task<String?, Never> { [weak self] in
            guard let self = self else { return nil }
            return await self.performPromptExecution(cleanPrompt)
        }
        activeGenerationTask = task
        let result = await task.value
        activeGenerationTask = nil
        return result
    }

    private func performPromptExecution(_ cleanPrompt: String) async -> String? {
        let endpoint = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        guard let url = URL(string: endpoint) else {
            errorMessage = "Invalid API URL: \(baseURL)"
            return nil
        }

        isGenerating = true
        errorMessage = nil
        activeToolStatus = nil

        let systemPrompt = buildSystemPrompt()
        var apiMessages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt]
        ]

        // Include recent conversation turns (excluding the initial static greeting if it's the first item)
        let historySlice = messages.suffix(13)
        for msg in historySlice {
            switch msg.role {
            case .user:
                apiMessages.append(["role": "user", "content": msg.text])
            case .assistant:
                if msg.text != "Chat cleared. How can I help you?" {
                    apiMessages.append(["role": "assistant", "content": msg.text])
                }
            case .reminder:
                break
            }
        }

        let tools = mcpClient.openAIToolsPayload
        var allowTools = !tools.isEmpty
        var usedBadges: [String] = []
        var sawWebSearch = false
        var sawReminderAction = false

        let maxToolRounds = 4
        for round in 0..<maxToolRounds {
            if Task.isCancelled {
                isGenerating = false
                activeToolStatus = nil
                return nil
            }

            var payload: [String: Any] = [
                "model": selectedModel,
                "messages": apiMessages
            ]
            if allowTools {
                payload["tools"] = tools
                payload["tool_choice"] = "auto"
            }

            let responseResult = await postChatCompletion(url: url, payload: payload)

            // If model/backend rejects tools parameter, retry once without tools
            if case .failure(let err) = responseResult, allowTools,
               err.localized.lowercased().contains("tool") {
                allowTools = false
                var fallbackPayload = payload
                fallbackPayload.removeValue(forKey: "tools")
                fallbackPayload.removeValue(forKey: "tool_choice")
                let retryResult = await postChatCompletion(url: url, payload: fallbackPayload)
                return await handleFinalOrFallbackResult(retryResult, cleanPrompt: cleanPrompt, badges: usedBadges)
            }

            switch responseResult {
            case .failure(let err):
                isGenerating = false
                activeToolStatus = nil
                errorMessage = err.localized
                return nil

            case .success(let choice):
                if let toolCalls = choice.message.tool_calls, !toolCalls.isEmpty {
                    // Record assistant tool_calls message in OpenAI format
                    let serializedCalls: [[String: Any]] = toolCalls.enumerated().map { idx, call in
                        [
                            "id": call.id ?? "call_\(round)_\(idx)",
                            "type": call.type ?? "function",
                            "function": [
                                "name": call.function.name,
                                "arguments": call.function.arguments
                            ]
                        ]
                    }
                    var assistantMsg: [String: Any] = [
                        "role": "assistant",
                        "tool_calls": serializedCalls
                    ]
                    if let content = choice.message.content, !content.isEmpty {
                        assistantMsg["content"] = content
                    }
                    apiMessages.append(assistantMsg)

                    var directShortcutOutput: [String] = []

                    for (idx, call) in toolCalls.enumerated() {
                        if Task.isCancelled {
                            isGenerating = false
                            activeToolStatus = nil
                            return nil
                        }

                        let fnName = call.function.name
                        let callId = call.id ?? "call_\(round)_\(idx)"
                        activeToolStatus = statusLabel(for: fnName)
                        if !usedBadges.contains(fnName) {
                            usedBadges.append(fnName)
                        }

                        let argsData = call.function.arguments.data(using: .utf8) ?? Data()
                        var argsDict = (try? JSONSerialization.jsonObject(with: argsData)) as? [String: Any] ?? [:]

                        if fnName == "search_internet" {
                            sawWebSearch = true
                            if (argsDict["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                                argsDict["query"] = extractSearchQuery(from: cleanPrompt)
                            }
                        } else if fnName == "schedule_reminder" || fnName == "cancel_reminder" {
                            sawReminderAction = true
                        }

                        let toolResult = await mcpClient.callTool(name: fnName, arguments: argsDict)

                        var contentForModel = toolResult
                        if let resData = toolResult.data(using: .utf8),
                           let resObj = (try? JSONSerialization.jsonObject(with: resData)) as? [String: Any] {
                            if fnName == "search_internet", let summary = resObj["summary"] as? String, !summary.isEmpty {
                                contentForModel = """
                                \(summary)

                                STRICT GROUNDING RULES:
                                - Rely ONLY on facts, scores, dates, and numbers present in the search results above.
                                - Do NOT invent or assume missing scores or details. Mention relevant links when previews are incomplete.
                                """
                            } else if let msg = resObj["message"] as? String, !msg.isEmpty {
                                directShortcutOutput.append(msg)
                            }
                        }

                        apiMessages.append([
                            "role": "tool",
                            "tool_call_id": callId,
                            "content": contentForModel
                        ])
                    }

                    if sawReminderAction {
                        onReminderScheduled?()
                    }

                    // For simple single-turn reminder confirmations, if the model loop produces a clean reply on next round we use it;
                    // if follow-up fails we can fall back to directShortcutOutput.
                    continue
                }

                // Model returned final text content
                if let content = choice.message.content {
                    let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)

                    // On round 0 with no tool calls, check if the user issued an explicit reminder/search command
                    // that a smaller local model ignored.
                    if round == 0, let fallbackReply = await maybeExecuteExplicitFallback(cleanPrompt: cleanPrompt) {
                        isGenerating = false
                        activeToolStatus = nil
                        return finishAssistantResponse(fallbackReply.text, badge: fallbackReply.badge)
                    }

                    isGenerating = false
                    activeToolStatus = nil
                    let prefix = sawWebSearch ? "🌐 " : (sawReminderAction ? "⏰ " : "")
                    let finalText = (prefix.isEmpty || trimmed.hasPrefix(prefix)) ? trimmed : (prefix + trimmed)
                    return finishAssistantResponse(finalText, badge: usedBadges.first)
                }

                isGenerating = false
                activeToolStatus = nil
                errorMessage = "Received empty response from LLM."
                return nil
            }
        }

        isGenerating = false
        activeToolStatus = nil
        errorMessage = "Tool execution exceeded maximum steps."
        return nil
    }

    private func handleFinalOrFallbackResult(
        _ result: Result<OpenAIChatResponse.Choice, LLMCallError>,
        cleanPrompt: String,
        badges: [String]
    ) async -> String? {
        switch result {
        case .failure(let err):
            isGenerating = false
            activeToolStatus = nil
            errorMessage = err.localized
            return nil
        case .success(let choice):
            if let fallbackReply = await maybeExecuteExplicitFallback(cleanPrompt: cleanPrompt) {
                isGenerating = false
                activeToolStatus = nil
                return finishAssistantResponse(fallbackReply.text, badge: fallbackReply.badge)
            }
            let text = (choice.message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            isGenerating = false
            activeToolStatus = nil
            guard !text.isEmpty else {
                errorMessage = "Received empty response from LLM."
                return nil
            }
            return finishAssistantResponse(text, badge: badges.first)
        }
    }

    private func finishAssistantResponse(_ text: String, badge: String?) -> String {
        self.lastResponse = text
        self.errorMessage = nil
        self.messages.append(ChatMessage(role: .assistant, text: text, badge: badge))
        self.trimMessagesIfNeeded()
        return text
    }

    private func trimMessagesIfNeeded() {
        if messages.count > 40 {
            messages.removeFirst(messages.count - 40)
        }
    }

    private enum LLMCallError: Error {
        case message(String)
        var localized: String {
            switch self {
            case .message(let m): return m
            }
        }
    }

    private func postChatCompletion(url: URL, payload: [String: Any]) async -> Result<OpenAIChatResponse.Choice, LLMCallError> {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 120.0

        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return .failure(.message("Failed to encode prompt request."))
        }
        request.httpBody = httpBody

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 {
                let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: data)
                if let choice = decoded.choices.first {
                    self.isConnected = true
                    return .success(choice)
                }
                return .failure(.message("Empty choices from LLM."))
            } else {
                if let errDecoded = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data),
                   let msg = errDecoded.error?.message {
                    return .failure(.message("LLM Error: \(msg)"))
                } else if let rawStr = String(data: data, encoding: .utf8), !rawStr.isEmpty {
                    return .failure(.message("Error: \(rawStr)"))
                } else {
                    return .failure(.message("Server error (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 500))."))
                }
            }
        } catch {
            if (error as NSError).code == NSURLErrorCancelled || Task.isCancelled {
                return .failure(.message("Cancelled."))
            }
            return .failure(.message("Connection error: \(error.localizedDescription)"))
        }
    }

    private func buildSystemPrompt() -> String {
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm:ss a (zzzz)"
        let nowHuman = dateFormatter.string(from: now)

        let isoFormatter = ISO8601DateFormatter()
        let nowISO = isoFormatter.string(from: now)

        let extraPersona = customPersona.trimmingCharacters(in: .whitespacesAndNewlines)
        let personaLine = extraPersona.isEmpty ? "" : "\nUser style preference: \(extraPersona)\n"

        return """
        Current date and time: \(nowHuman) [ISO: \(nowISO)].
        You are Shodha, a helpful, concise macOS desktop companion with MCP tools.
        \(personaLine)
        Available tools:
        - 'search_internet': Live web search for news, facts, weather, docs, sports, prices.
        - 'fetch_webpage': Read text from a specific http/https URL.
        - 'schedule_reminder': Schedule one-time or recurring ('hourly', 'daily', 'weekdays', 'weekly') reminders.
        - 'list_reminders' / 'cancel_reminder': View or cancel scheduled reminders.
        - 'calculate': Exact math expression evaluator.
        - 'get_current_time': Exact current local time & timezone.
        - 'save_note' / 'list_notes' / 'delete_note': Manage local scratchpad notes.

        Keep responses clear, accurate, and concise.
        """
    }

    private func statusLabel(for toolName: String) -> String {
        switch toolName {
        case "search_internet": return "Searching the web..."
        case "fetch_webpage": return "Reading webpage..."
        case "schedule_reminder": return "Scheduling reminder..."
        case "list_reminders": return "Checking reminders..."
        case "cancel_reminder": return "Cancelling reminder..."
        case "calculate": return "Calculating..."
        case "get_current_time": return "Checking time..."
        case "save_note", "list_notes", "delete_note": return "Updating notes..."
        default: return "Running \(toolName)..."
        }
    }

    private func extractSearchQuery(from prompt: String) -> String {
        var q = prompt
        for prefix in ["search for", "search internet for", "search the web for", "search web for", "google", "search"] {
            if let range = q.range(of: prefix, options: [.caseInsensitive, .anchored]) {
                q = String(q[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        return q.isEmpty ? prompt : q
    }

    private func maybeExecuteExplicitFallback(cleanPrompt: String) async -> (text: String, badge: String)? {
        let lower = cleanPrompt.lowercased()

        // Explicit reminder creation command (avoid triggering on questions like "what does remind mean?")
        let isExplicitReminder = (lower.hasPrefix("remind me") || lower.hasPrefix("set a reminder") || lower.hasPrefix("set reminder"))
            && !lower.contains("list") && !lower.contains("cancel")
        if isExplicitReminder {
            if let scheduled = await scheduleReminderFallback(from: cleanPrompt) {
                self.onReminderScheduled?()
                return ("⏰ " + scheduled, "schedule_reminder")
            }
        }

        // Explicit web search command
        let isExplicitSearch = lower.hasPrefix("search ") || lower.hasPrefix("google ")
            || lower.contains("search the web for") || lower.contains("search internet for")
        if isExplicitSearch {
            let queryParam = extractSearchQuery(from: cleanPrompt)
            let toolResult = await mcpClient.callTool(name: "search_internet", arguments: ["query": queryParam])
            if let resData = toolResult.data(using: .utf8),
               let resObj = (try? JSONSerialization.jsonObject(with: resData)) as? [String: Any],
               let summary = resObj["summary"] as? String, !summary.isEmpty {
                return ("🌐 Live Web Results for \"\(queryParam)\":\n\n" + summary, "search_internet")
            }
        }

        return nil
    }

    private func scheduleReminderFallback(from prompt: String) async -> String? {
        let pattern1 = #"(?i)remind\s+(?:me\s+)?(?:to\s+|about\s+|that\s+)?(.+?)\s+(at\s+.+|in\s+.+|on\s+.+|after\s+.+|tomorrow.*|noon|midnight|\d+\s*(?:sec|second|seconds|min|minute|minutes|hr|hour|hours).*)"#
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
