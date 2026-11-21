import SwiftUI
import AppKit

struct SpeechDialogView: View {
    @ObservedObject var appState: AppState
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // Header Bar
            HStack(alignment: .center, spacing: 6) {
                if appState.activeTab == .settings {
                    Button(action: {
                        appState.activeTab = .chat
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .bold))
                            Text("Back")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color.accentColor)
                    }
                    .buttonStyle(.plain)

                    Text("Settings")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                } else {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(appState.agent.isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                            .help(appState.agent.isConnected ? "LLM Connected" : "LLM Offline / Checking")

                        Text("Shodha")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }

                    if !appState.agent.availableModels.isEmpty {
                        Menu {
                            ForEach(appState.agent.availableModels, id: \.self) { model in
                                Button(model) {
                                    appState.agent.setModel(model)
                                }
                            }
                            Divider()
                            Button("🔄 Refresh Models") {
                                appState.agent.fetchModels()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(appState.agent.selectedModel)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundColor(.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(5)
                        }
                        .menuStyle(.borderlessButton)
                        .help("Select LLM model")
                    }
                }

                Spacer()

                if appState.activeTab == .chat {
                    Button(action: {
                        appState.agent.clearChat()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(5)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Clear chat history")
                }

                // Settings Gear Button
                Button(action: {
                    appState.toggleTab()
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(appState.activeTab == .settings ? .white : .primary)
                        .padding(5)
                        .background(
                            appState.activeTab == .settings
                                ? Color.blue
                                : Color.secondary.opacity(0.12)
                        )
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(appState.activeTab == .settings ? "Return to Chat" : "Settings: LLM, Reminders, Photos & Voice")

                // Mute / Unmute Toggle
                Button(action: {
                    appState.isMuted.toggle()
                }) {
                    Image(systemName: appState.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(appState.isMuted ? .secondary : .primary)
                        .padding(5)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(appState.isMuted ? "Unmute voice" : "Mute voice")

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(5)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Close popup (Avatar remains on screen)")
            }
            .padding(.top, 1)

            if appState.activeTab == .chat {
                chatContentView
            } else {
                settingsContentView
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(
            width: SpeechDialogPanel.dialogWidth,
            height: appState.activeTab == .chat ? SpeechDialogPanel.chatHeight : SpeechDialogPanel.settingsHeight,
            alignment: .top
        )
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 15, x: 0, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.3), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
    }

    // MARK: - Chat / LLM Content View
    private var chatContentView: some View {
        VStack(spacing: 7) {
            // Conversation Thread Card
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.cyan)

                    Text(appState.agent.selectedModel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    if appState.agent.mcpClient.isServerRunning {
                        Text("• \(appState.agent.mcpClient.discoveredTools.count) tools")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.8))
                    }

                    Spacer()

                    if appState.isSpeaking && !appState.isMuted {
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 2.5, height: barHeight(for: index))
                            }
                        }
                    }

                    Button(action: {
                        appState.copyResponseToClipboard()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: appState.isCopiedFeedback ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            if appState.isCopiedFeedback {
                                Text("Copied!")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .foregroundColor(appState.isCopiedFeedback ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy latest response to clipboard (⌘C)")
                }

                // Scrollable Chat Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(appState.agent.messages) { msg in
                                chatBubble(for: msg)
                                    .id(msg.id)
                            }

                            if appState.agent.isGenerating {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(appState.agent.activeToolStatus ?? "Thinking with \(appState.agent.selectedModel)...")
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Button("Stop") {
                                        appState.agent.cancelGeneration()
                                    }
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.red)
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(8)
                                .id("generating_indicator")
                            }

                            if let error = appState.agent.errorMessage {
                                Text(error)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.red)
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.08))
                                    .cornerRadius(6)
                                    .id("error_indicator")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(maxHeight: 190)
                    .onChange(of: appState.agent.messages.count) { _ in
                        if let last = appState.agent.messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: appState.agent.isGenerating) { generating in
                        if generating {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("generating_indicator", anchor: .bottom)
                            }
                        }
                    }
                }

                // Response Action Row: Say It button
                HStack {
                    if appState.globalHotkeyEnabled {
                        Text("⌥Space to toggle")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.75))
                    }

                    Spacer()

                    Button(action: {
                        appState.toggleSpeechForResponse()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: appState.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text(appState.isSpeaking ? "Stop" : "Say It")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(appState.isSpeaking ? .white : .primary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            appState.isSpeaking
                                ? Color.red.opacity(0.85)
                                : Color.secondary.opacity(0.15)
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .help(appState.isSpeaking ? "Stop speaking response" : "Read latest response out loud")
                    .disabled(appState.agent.lastResponse.isEmpty || appState.agent.isGenerating)
                }
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.65))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Next Upcoming Reminder Hint
            if let nextReminder = appState.reminderManager.upcomingReminders.first {
                HStack(spacing: 5) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.orange)
                    Text("Next: \(nextReminder.text) (\(nextReminder.formatted_time ?? ""))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button(action: {
                        appState.reminderManager.cancelReminder(id: nextReminder.id)
                    }) {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Dismiss this reminder")
                }
                .padding(.horizontal, 2)
            }

            // Prompt Area
            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if appState.inputText.isEmpty {
                        Text("Ask anything, search the web, calculate, or say 'Remind me...'")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary.opacity(0.65))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 8)
                    }

                    TextField("", text: $appState.inputText, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .lineLimit(2...3)
                        .padding(8)
                        .onSubmit {
                            appState.sendPromptToLLM()
                        }
                }
                .frame(minHeight: 46)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                HStack(spacing: 6) {
                    Text("Return sends")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)

                    Button(action: {
                        appState.pasteIntoInput()
                    }) {
                        HStack(spacing: 2.5) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 8.5))
                            Text("Paste (⌘V)")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Paste clipboard text into prompt (or press Cmd+V)")

                    Spacer()

                    Button(action: {
                        appState.sendPromptToLLM()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 10))
                            Text("Send")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.purple],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.agent.isGenerating)
                }
            }
        }
    }

    @ViewBuilder
    private func chatBubble(for msg: ChatMessage) -> some View {
        switch msg.role {
        case .user:
            HStack {
                Spacer(minLength: 36)
                Text(msg.text)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        LinearGradient(colors: [Color.blue.opacity(0.88), Color.purple.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
        case .reminder:
            HStack(alignment: .top, spacing: 6) {
                Text(msg.text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(Color.orange.opacity(0.18))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 1)
            )
        case .assistant:
            VStack(alignment: .leading, spacing: 4) {
                if let badge = msg.badge {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 8))
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.cyan.opacity(0.12))
                    .cornerRadius(4)
                }

                markdownText(msg.text)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            .padding(8)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .cornerRadius(9)
            .contextMenu {
                Button("Copy Message") {
                    appState.copyTextToClipboard(msg.text)
                }
                Button("Read Aloud") {
                    appState.speechManager.speak(
                        text: msg.text,
                        pitch: appState.voicePitch,
                        rate: appState.voiceRate,
                        isMuted: appState.isMuted
                    )
                }
            }
        }
    }

    private func markdownText(_ raw: String) -> Text {
        if let attr = try? AttributedString(
            markdown: raw,
            options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attr)
        }
        return Text(raw)
    }

    // MARK: - Settings View
    private var settingsContentView: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                // Section 1: Ollama / OpenAI Compatible LLM
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("OLLAMA / OPENAI LLM")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("🔄 Refresh Models") {
                            appState.agent.fetchModels()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Text("Model:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 58, alignment: .leading)

                        if appState.agent.availableModels.isEmpty {
                            Text("No models detected. Is Ollama running?")
                                .font(.system(size: 10.5))
                                .foregroundColor(.orange)
                        } else {
                            Picker("", selection: Binding(
                                get: { appState.agent.selectedModel },
                                set: { appState.agent.setModel($0) }
                            )) {
                                ForEach(appState.agent.availableModels, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    HStack {
                        Text("Endpoint:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 58, alignment: .leading)

                        TextField("http://localhost:11434/v1", text: Binding(
                            get: { appState.agent.baseURL },
                            set: { appState.agent.setBaseURL($0, debounced: true) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                        .cornerRadius(4)
                    }

                    HStack {
                        Text("API Key:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 58, alignment: .leading)

                        SecureField("Optional (for OpenAI / cloud)", text: Binding(
                            get: { appState.agent.apiKey },
                            set: { appState.agent.setAPIKey($0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                        .cornerRadius(4)
                    }

                    HStack {
                        Text("Persona:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 58, alignment: .leading)

                        TextField("Optional style (e.g. 'Reply in bullet points')", text: Binding(
                            get: { appState.agent.customPersona },
                            set: { appState.agent.setCustomPersona($0) }
                        ))
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                        .cornerRadius(4)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .cornerRadius(10)

                // Section 2: MCP Scheduled Reminders + Quick Add
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("⏰ SCHEDULED REMINDERS (\(appState.reminderManager.upcomingReminders.count))")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button("Refresh") {
                            appState.reminderManager.reload()
                        }
                        .font(.system(size: 10))
                        .buttonStyle(.plain)
                    }

                    // Inline quick reminder creator
                    HStack(spacing: 4) {
                        TextField("Quick reminder...", text: $appState.quickReminderText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 10.5))
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
                            .cornerRadius(4)

                        Picker("", selection: $appState.quickReminderMinutes) {
                            Text("5m").tag(5)
                            Text("15m").tag(15)
                            Text("30m").tag(30)
                            Text("1h").tag(60)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 56)

                        Button("Add") {
                            let text = appState.quickReminderText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !text.isEmpty else { return }
                            let target = Date().addingTimeInterval(TimeInterval(appState.quickReminderMinutes * 60))
                            appState.reminderManager.addReminder(text: text, targetDate: target)
                            appState.quickReminderText = ""
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(4)
                        .buttonStyle(.plain)
                        .disabled(appState.quickReminderText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if appState.reminderManager.upcomingReminders.isEmpty {
                        Text("No active reminders.\nAsk e.g. \"Remind me to stretch every day at 3pm\"")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 2)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(appState.reminderManager.upcomingReminders) { rem in
                                HStack(spacing: 6) {
                                    Image(systemName: "alarm.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)

                                    VStack(alignment: .leading, spacing: 1) {
                                        HStack(spacing: 4) {
                                            Text(rem.text)
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)
                                            if let rec = rem.recurrence, rec != "none" {
                                                Text(rec)
                                                    .font(.system(size: 8.5, weight: .semibold))
                                                    .foregroundColor(.blue)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.blue.opacity(0.12))
                                                    .cornerRadius(3)
                                            }
                                        }
                                        if let time = rem.formatted_time {
                                            Text(time)
                                                .font(.system(size: 9))
                                                .foregroundColor(.secondary)
                                        }
                                    }

                                    Spacer()

                                    Button(action: {
                                        appState.reminderManager.cancelReminder(id: rem.id)
                                    }) {
                                        Image(systemName: "trash")
                                            .font(.system(size: 9.5))
                                            .foregroundColor(.red.opacity(0.85))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Cancel reminder")
                                }
                                .padding(4)
                                .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
                                .cornerRadius(5)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .cornerRadius(10)

                // Section 3: Avatar Photos
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("AVATARS (CLICK TO TRY)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: {
                            appState.promptChoosePhotos()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Upload Photos")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .foregroundColor(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            Button(action: {
                                appState.selectAvatar(id: nil)
                            }) {
                                VStack(spacing: 3) {
                                    ZStack {
                                        CuteMascotView(appState: appState)
                                            .frame(width: 34, height: 34)

                                        Circle()
                                            .strokeBorder(
                                                appState.isCuteMascotSelected ? Color.blue : Color.white.opacity(0.3),
                                                lineWidth: appState.isCuteMascotSelected ? 2.5 : 1.0
                                            )
                                            .frame(width: 36, height: 36)
                                    }
                                    Text("Cute Buddy")
                                        .font(.system(size: 9, weight: appState.isCuteMascotSelected ? .bold : .regular))
                                        .foregroundColor(appState.isCuteMascotSelected ? .primary : .secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            ForEach(appState.savedAvatars) { avatar in
                                let isSelected = appState.selectedAvatarId == avatar.id
                                ZStack(alignment: .topTrailing) {
                                    Button(action: {
                                        appState.selectAvatar(id: avatar.id)
                                    }) {
                                        VStack(spacing: 3) {
                                            Image(nsImage: avatar.image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 34, height: 34)
                                                .clipShape(Circle())
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(
                                                            isSelected ? Color.blue : Color.white.opacity(0.3),
                                                            lineWidth: isSelected ? 2.5 : 1.0
                                                        )
                                                )
                                            Text("Photo")
                                                .font(.system(size: 9, weight: isSelected ? .bold : .regular))
                                                .foregroundColor(isSelected ? .primary : .secondary)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: {
                                        appState.deleteAvatar(id: avatar.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color(nsColor: .secondaryLabelColor))
                                            .background(Color(nsColor: .windowBackgroundColor).clipShape(Circle()))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 3, y: -3)
                                }
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 2)
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .cornerRadius(10)

                // Section 4: Voice & Preferences
                VStack(alignment: .leading, spacing: 6) {
                    Text("VOICE & SHORTCUTS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    if !appState.speechManager.availableVoices.isEmpty {
                        HStack(spacing: 5) {
                            Text("Voice:")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .leading)

                            Picker("", selection: Binding(
                                get: { appState.speechManager.selectedVoiceId },
                                set: { appState.speechManager.setVoice(identifier: $0) }
                            )) {
                                Text("System Default").tag("")
                                ForEach(appState.speechManager.availableVoices) { voice in
                                    Text("\(voice.name) (\(voice.language))").tag(voice.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }

                    HStack(spacing: 5) {
                        Text("Pitch:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)

                        VoiceSettingChip(title: "Cute", isSelected: abs(appState.voicePitch - 1.35) < 0.08) {
                            appState.setPitch(1.35)
                        }
                        VoiceSettingChip(title: "Normal", isSelected: abs(appState.voicePitch - 1.0) < 0.08) {
                            appState.setPitch(1.0)
                        }
                        VoiceSettingChip(title: "Deep", isSelected: abs(appState.voicePitch - 0.75) < 0.08) {
                            appState.setPitch(0.75)
                        }
                        VoiceSettingChip(title: "Chipmunk", isSelected: abs(appState.voicePitch - 1.6) < 0.08) {
                            appState.setPitch(1.6)
                        }
                    }

                    HStack(spacing: 5) {
                        Text("Speed:")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 40, alignment: .leading)

                        VoiceSettingChip(title: "Relaxed", isSelected: abs(appState.voiceRate - 0.38) < 0.05) {
                            appState.setRate(0.38)
                        }
                        VoiceSettingChip(title: "Normal", isSelected: abs(appState.voiceRate - 0.48) < 0.05) {
                            appState.setRate(0.48)
                        }
                        VoiceSettingChip(title: "Fast", isSelected: abs(appState.voiceRate - 0.60) < 0.05) {
                            appState.setRate(0.60)
                        }

                        Spacer()

                        Button(action: {
                            appState.testVoiceSample()
                        }) {
                            HStack(spacing: 3) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 8))
                                Text("Test")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.blue)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }

                    Toggle("Auto-speak new responses", isOn: $appState.autoSpeak)
                        .font(.system(size: 10.5))
                        .toggleStyle(.checkbox)

                    Toggle("Global shortcut (⌥Space) to toggle Shodha", isOn: $appState.globalHotkeyEnabled)
                        .font(.system(size: 10.5))
                        .toggleStyle(.checkbox)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .cornerRadius(10)

                Button(action: {
                    appState.activeTab = .chat
                }) {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let patternA: [CGFloat] = [12, 7, 15, 9, 13]
        let patternB: [CGFloat] = [5, 12, 8, 14, 6]
        return appState.wavePhase == 1.0 ? patternA[index] : patternB[index]
    }
}

private struct VoiceSettingChip: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Text(title)
                .font(.system(size: 9.5, weight: isSelected ? .bold : .regular))
                .foregroundColor(isSelected ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(isSelected ? Color.blue : Color.secondary.opacity(0.12))
                .cornerRadius(5)
        }
        .buttonStyle(.plain)
    }
}
