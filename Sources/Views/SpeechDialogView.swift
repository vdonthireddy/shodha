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
                    // Ollama status dot + EchoBuddy
                    HStack(spacing: 5) {
                        Circle()
                            .fill(appState.agent.isConnected ? Color.green : Color.orange)
                            .frame(width: 7, height: 7)
                            .help(appState.agent.isConnected ? "Ollama Connected" : "Ollama Offline / Checking")
                        
                        Text("Shodha")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                    }
                    
                    // Quick Model Switcher Dropdown
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
                        .help("Select LLM running in Ollama")
                    }
                }
                
                Spacer()
                
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
                .help(appState.activeTab == .settings ? "Return to Chat" : "Settings: Ollama, Reminders, Photos & Voice")
                
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
            
            // View Switcher: Chat vs Settings
            if appState.activeTab == .chat {
                chatContentView
            } else {
                settingsContentView
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .frame(width: 360, height: appState.activeTab == .chat ? 310 : 380, alignment: .top)
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
        VStack(spacing: 8) {
            // LLM Response Box
            VStack(alignment: .leading, spacing: 5) {
                // Top status of response card
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.cyan)
                    
                    Text(appState.agent.selectedModel)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Audio waveform indicator if speaking
                    if appState.isSpeaking && !appState.isMuted {
                        HStack(spacing: 2) {
                            ForEach(0..<5, id: \.self) { index in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom))
                                    .frame(width: 2.5, height: barHeight(for: index))
                            }
                        }
                    }
                    
                    // Copy button
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
                    .help("Copy response to clipboard (⌘C)")
                }
                
                // Content area
                if appState.agent.isGenerating {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking with \(appState.agent.selectedModel)...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if let error = appState.agent.errorMessage {
                    Text(error)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.red)
                        .padding(.vertical, 4)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView {
                        Text(appState.agent.lastResponse)
                            .font(.system(size: 12.5, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 78)
                }
                
                // Response Action Row: The "Say It" button!
                HStack {
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
                    .help(appState.isSpeaking ? "Stop speaking response" : "Read this response out loud")
                    .disabled(appState.agent.lastResponse.isEmpty || appState.agent.isGenerating)
                }
                .padding(.top, 1)
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
            
            // Next Upcoming Reminder Hint (if any)
            if let nextReminder = appState.reminderManager.upcomingReminders.first {
                HStack(spacing: 5) {
                    Image(systemName: "alarm.fill")
                        .font(.system(size: 9))
                        .foregroundColor(.yellow)
                    Text("Reminder set: \(nextReminder.text) (\(nextReminder.formatted_time ?? ""))")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 2)
            }
            
            // Expanded Multi-line User Prompt Area
            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    if appState.inputText.isEmpty {
                        Text("Ask or say: 'Remind me to call John at 3pm'...")
                            .font(.system(size: 12.5))
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
                .frame(minHeight: 48)
                .background(Color(nsColor: .textBackgroundColor).opacity(0.75))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                
                // Bottom Prompt Send Controls
                HStack(spacing: 6) {
                    Text("Return sends")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                    
                    // Paste shortcut button
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
    
    // MARK: - Settings View (Ollama LLM, Scheduler, Photos & Voice)
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
                    
                    // Selected Model Picker
                    HStack {
                        Text("Model:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
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
                    
                    // API Endpoint
                    HStack {
                        Text("Endpoint:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading)
                        
                        TextField("http://localhost:11434/v1", text: Binding(
                            get: { appState.agent.baseURL },
                            set: { appState.agent.setBaseURL($0) }
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
                
                // Section 2: MCP Scheduled Reminders
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
                    
                    if appState.reminderManager.upcomingReminders.isEmpty {
                        Text("No active reminders.\nAsk e.g. \"Remind me to call John at 3:00 PM\"")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 3)
                    } else {
                        VStack(spacing: 4) {
                            ForEach(appState.reminderManager.upcomingReminders) { rem in
                                HStack(spacing: 6) {
                                    Image(systemName: "alarm.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(.blue)
                                    
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(rem.text)
                                            .font(.system(size: 10.5, weight: .medium))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
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
                            // Cute Buddy Mascot Preset
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
                            
                            // Uploaded Custom Photos
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
                                    
                                    // Delete button
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
                
                // Section 4: Voice Modulation
                VStack(alignment: .leading, spacing: 6) {
                    Text("VOICE MODULATION")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    
                    // Pitch Presets
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
                    
                    // Speed Presets
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
                                Text("Test Voice")
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
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                .cornerRadius(10)
                
                // Done Button
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
