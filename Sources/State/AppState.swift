import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Combine

struct CustomAvatarItem: Identifiable, Equatable {
    let id: String
    let image: NSImage

    static func == (lhs: CustomAvatarItem, rhs: CustomAvatarItem) -> Bool {
        lhs.id == rhs.id
    }
}

enum DialogTab: Equatable {
    case chat
    case settings
}

@MainActor
final class AppState: ObservableObject {
    @Published var inputText: String = ""
    @Published var lastUserPrompt: String = ""
    @Published var lastSpokenText: String = "Hi! I am your AI agent. Ask me anything and click 'Say It' to hear my response!"
    @Published var isSpeaking: Bool = false
    @Published var isDialogVisible: Bool = false
    @Published var isMuted: Bool = false {
        didSet {
            UserDefaults.standard.set(isMuted, forKey: mutedKey)
            if isMuted && isSpeaking {
                speechManager.stop()
            }
        }
    }
    @Published var autoSpeak: Bool = false {
        didSet {
            UserDefaults.standard.set(autoSpeak, forKey: autoSpeakKey)
        }
    }
    @Published var globalHotkeyEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(globalHotkeyEnabled, forKey: hotkeyEnabledKey)
            onHotkeySettingChanged?(globalHotkeyEnabled)
        }
    }
    @Published var isCopiedFeedback: Bool = false

    // Navigation Tab (Chat vs Settings)
    @Published var activeTab: DialogTab = .chat
    @Published var isPickingPhoto: Bool = false
    @Published var quickReminderText: String = ""
    @Published var quickReminderMinutes: Int = 15

    // Voice Modulation Settings
    @Published var voicePitch: Float = 1.25
    @Published var voiceRate: Float = 0.48

    // Multi-photo gallery state
    @Published var savedAvatars: [CustomAvatarItem] = []
    @Published var selectedAvatarId: String? = nil // nil = Cute Mascot

    // UI Animation States
    @Published var isBlinking: Bool = false
    @Published var isHovering: Bool = false
    @Published var wavePhase: CGFloat = 0.0

    // Local Ollama / OpenAI Agent & MCP Reminder Scheduler
    @Published var agent = OllamaAgent()
    let reminderManager = ReminderManager()
    let speechManager = SpeechManager()
    var onRequestShowDialog: (() -> Void)?
    var onHotkeySettingChanged: ((Bool) -> Void)?

    nonisolated(unsafe) private var blinkTimer: Timer?
    nonisolated(unsafe) private var waveTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let selectedAvatarKey = "Shodha.SelectedAvatarId"
    private let voicePitchKey = "Shodha.VoicePitch"
    private let voiceRateKey = "Shodha.VoiceRate"
    private let mutedKey = "Shodha.IsMuted"
    private let autoSpeakKey = "Shodha.AutoSpeak"
    private let hotkeyEnabledKey = "Shodha.GlobalHotkeyEnabled"

    private let appSupportURL: URL = {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Shodha", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

        // Seamlessly migrate legacy EchoBuddy files if present
        let oldDir = appSupport.appendingPathComponent("EchoBuddy", isDirectory: true)
        if fileManager.fileExists(atPath: oldDir.path) {
            let files = (try? fileManager.contentsOfDirectory(atPath: oldDir.path)) ?? []
            for file in files {
                let src = oldDir.appendingPathComponent(file)
                let dst = dir.appendingPathComponent(file)
                if !fileManager.fileExists(atPath: dst.path) {
                    try? fileManager.copyItem(at: src, to: dst)
                }
            }
        }
        return dir
    }()

    private var avatarsDirectoryURL: URL {
        let dir = appSupportURL.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    init() {
        speechManager.onSpeechStarted = { [weak self] in
            self?.isSpeaking = true
        }
        speechManager.onSpeechFinished = { [weak self] in
            self?.isSpeaking = false
        }

        agent.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        reminderManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        speechManager.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        reminderManager.onReminderTriggered = { [weak self] reminder in
            guard let self = self else { return }
            self.agent.appendReminderNotificationMessage(reminder.text)
            self.lastSpokenText = "Reminder: \(reminder.text)"
            self.activeTab = .chat
            self.onRequestShowDialog?()
            self.speechManager.speak(
                text: "Reminder: \(reminder.text)",
                pitch: self.voicePitch,
                rate: self.voiceRate,
                isMuted: self.isMuted
            )
        }

        agent.onReminderScheduled = { [weak self] in
            self?.reminderManager.reload()
        }

        loadSavedSettings()
        migrateLegacyAvatarIfNeeded()
        loadSavedAvatars()
        syncCurrentAvatarFile()
        startTimers()
    }

    deinit {
        blinkTimer?.invalidate()
        waveTimer?.invalidate()
    }

    func shutdown() {
        blinkTimer?.invalidate()
        waveTimer?.invalidate()
        speechManager.stop()
        agent.cancelGeneration()
        agent.mcpClient.stopServer()
    }

    var activeAvatarImage: NSImage? {
        guard let id = selectedAvatarId else { return nil }
        return savedAvatars.first(where: { $0.id == id })?.image
    }

    var isCuteMascotSelected: Bool {
        selectedAvatarId == nil
    }

    func toggleTab() {
        activeTab = (activeTab == .chat ? .settings : .chat)
    }

    func showCopiedFeedback() {
        isCopiedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.isCopiedFeedback = false
        }
    }

    func copyTextToClipboard(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(trimmed, forType: .string)
        showCopiedFeedback()
    }

    func copyResponseToClipboard() {
        copyTextToClipboard(agent.lastResponse)
    }

    func pasteIntoInput() {
        if let str = NSPasteboard.general.string(forType: .string), !str.isEmpty {
            inputText += str
        }
    }

    private func startTimers() {
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 3.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.isBlinking = true
                try? await Task.sleep(nanoseconds: 140_000_000)
                self?.isBlinking = false
            }
        }

        waveTimer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isSpeaking else { return }
                self.wavePhase = self.wavePhase == 0 ? 1.0 : 0.0
            }
        }
    }

    func sendPromptToLLM() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        lastUserPrompt = text
        inputText = ""

        Task {
            if let response = await agent.sendPrompt(text) {
                self.lastSpokenText = response
                if self.autoSpeak && !self.isMuted {
                    self.speechManager.speak(
                        text: response,
                        pitch: self.voicePitch,
                        rate: self.voiceRate,
                        isMuted: false
                    )
                }
            }
        }
    }

    func toggleSpeechForResponse() {
        if isSpeaking {
            speechManager.stop()
        } else {
            let textToSay = agent.lastResponse.isEmpty ? lastSpokenText : agent.lastResponse
            guard !textToSay.isEmpty else { return }
            speechManager.speak(text: textToSay, pitch: voicePitch, rate: voiceRate, isMuted: isMuted)
        }
    }

    func replayLastText() {
        toggleSpeechForResponse()
    }

    func testVoiceSample() {
        let sample = "Hello! This is a test of my modulated voice."
        speechManager.speak(text: sample, pitch: voicePitch, rate: voiceRate, isMuted: isMuted)
    }

    func setPitch(_ pitch: Float) {
        voicePitch = pitch
        UserDefaults.standard.set(pitch, forKey: voicePitchKey)
    }

    func setRate(_ rate: Float) {
        voiceRate = rate
        UserDefaults.standard.set(rate, forKey: voiceRateKey)
    }

    func selectAvatar(id: String?) {
        selectedAvatarId = id
        UserDefaults.standard.set(id, forKey: selectedAvatarKey)
        syncCurrentAvatarFile()
    }

    func syncCurrentAvatarFile() {
        let currentAvatarURL = appSupportURL.appendingPathComponent("current_avatar.png")
        if let id = selectedAvatarId {
            let customURL = avatarsDirectoryURL.appendingPathComponent("\(id).png")
            if FileManager.default.fileExists(atPath: customURL.path) {
                try? FileManager.default.removeItem(at: currentAvatarURL)
                try? FileManager.default.copyItem(at: customURL, to: currentAvatarURL)
                if let img = NSImage(contentsOf: customURL) {
                    NSApp.applicationIconImage = img
                    AppState.updateAppBundleIcon(from: img, sourceURL: customURL, isDefault: false)
                }
                return
            }
        }

        var defaultMascotPath: String?
        if let bundlePath = Bundle.main.path(forResource: "default_mascot", ofType: "png"),
           FileManager.default.fileExists(atPath: bundlePath) {
            defaultMascotPath = bundlePath
        } else {
            let relativePaths = [
                "Resources/default_mascot.png",
                "../Resources/default_mascot.png",
                "../../Resources/default_mascot.png"
            ]
            let cwd = FileManager.default.currentDirectoryPath
            for rel in relativePaths {
                let candidate = (cwd as NSString).appendingPathComponent(rel)
                if FileManager.default.fileExists(atPath: candidate) {
                    defaultMascotPath = candidate
                    break
                }
            }
        }
        if let path = defaultMascotPath, FileManager.default.fileExists(atPath: path) {
            let sourceURL = URL(fileURLWithPath: path)
            try? FileManager.default.removeItem(at: currentAvatarURL)
            try? FileManager.default.copyItem(at: sourceURL, to: currentAvatarURL)
            if let img = NSImage(contentsOf: sourceURL) {
                NSApp.applicationIconImage = img
                AppState.updateAppBundleIcon(from: img, sourceURL: sourceURL, isDefault: true)
            }
        }
    }

    private static func updateAppBundleIcon(from image: NSImage?, sourceURL: URL, isDefault: Bool) {
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else { return }

        let resourcesURL = URL(fileURLWithPath: bundlePath).appendingPathComponent("Contents/Resources")
        guard FileManager.default.isWritableFile(atPath: resourcesURL.path) else { return }

        let appIconURL = resourcesURL.appendingPathComponent("AppIcon.icns")
        let defaultIconURL = resourcesURL.appendingPathComponent("AppIcon_default.icns")

        let fm = FileManager.default
        let appliedKey = "Shodha.IconAppliedFor"
        let tag = isDefault ? "default" : sourceURL.lastPathComponent
        let currentData = fm.contents(atPath: appIconURL.path)
        let defaultData = fm.contents(atPath: defaultIconURL.path)
        let isCurrentlyDefault = currentData != nil && currentData == defaultData
        if isDefault ? isCurrentlyDefault : (UserDefaults.standard.string(forKey: appliedKey) == tag && currentData != nil && !isCurrentlyDefault) {
            UserDefaults.standard.set(tag, forKey: appliedKey)
            return
        }

        if isDefault {
            if fm.fileExists(atPath: defaultIconURL.path) {
                do {
                    if fm.fileExists(atPath: appIconURL.path) {
                        try fm.removeItem(at: appIconURL)
                    }
                    try fm.copyItem(at: defaultIconURL, to: appIconURL)
                    UserDefaults.standard.set(tag, forKey: appliedKey)
                    refreshLaunchServices(bundlePath: bundlePath)
                } catch {
                    print("[AppState] Failed restoring default icon: \(error)")
                }
            }
        } else if image != nil {
            Task.detached(priority: .utility) {
                if generateAndReplaceIcns(sourceURL: sourceURL, targetURL: appIconURL) {
                    await MainActor.run {
                        UserDefaults.standard.set(tag, forKey: appliedKey)
                    }
                    refreshLaunchServices(bundlePath: bundlePath)
                }
            }
        }
    }

    @discardableResult
    nonisolated private static func generateAndReplaceIcns(sourceURL: URL, targetURL: URL) -> Bool {
        guard let image = NSImage(contentsOf: sourceURL) else { return false }
        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let iconsetDir = tempDir.appendingPathComponent("icon.iconset")
        defer { try? fm.removeItem(at: tempDir) }

        do {
            try fm.createDirectory(at: iconsetDir, withIntermediateDirectories: true)
            let sizes: [(String, CGFloat)] = [
                ("icon_16x16.png", 16),
                ("icon_16x16@2x.png", 32),
                ("icon_32x32.png", 32),
                ("icon_32x32@2x.png", 64),
                ("icon_128x128.png", 128),
                ("icon_128x128@2x.png", 256),
                ("icon_256x256.png", 256),
                ("icon_256x256@2x.png", 512),
                ("icon_512x512.png", 512),
                ("icon_512x512@2x.png", 1024)
            ]

            for (filename, size) in sizes {
                let targetSize = NSSize(width: size, height: size)
                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: Int(size),
                    pixelsHigh: Int(size),
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .deviceRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 0
                ) else { continue }
                rep.size = targetSize

                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image.draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1.0)
                NSGraphicsContext.restoreGraphicsState()

                if let pngData = rep.representation(using: .png, properties: [:]) {
                    try pngData.write(to: iconsetDir.appendingPathComponent(filename))
                }
            }

            let tempIcns = tempDir.appendingPathComponent("AppIcon.icns")
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
            proc.arguments = ["-c", "icns", iconsetDir.path, "-o", tempIcns.path]
            try proc.run()
            proc.waitUntilExit()

            if proc.terminationStatus == 0 && fm.fileExists(atPath: tempIcns.path) {
                try? fm.removeItem(at: targetURL)
                try fm.copyItem(at: tempIcns, to: targetURL)
                return true
            }
        } catch {
            print("[AppState] Error generating ICNS: \(error)")
        }
        return false
    }

    nonisolated private static func refreshLaunchServices(bundlePath: String) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: bundlePath)
        let lsregister = "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
        if FileManager.default.fileExists(atPath: lsregister) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: lsregister)
            p.arguments = ["-f", bundlePath]
            try? p.run()
            p.waitUntilExit()
        }
    }

    func promptChoosePhotos() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Photos for Your Avatar"
        openPanel.prompt = "Add Photos"
        openPanel.allowsMultipleSelection = true
        openPanel.canChooseDirectories = false
        openPanel.canCreateDirectories = false
        openPanel.canChooseFiles = true

        var allowedTypes: [UTType] = [.image, .png, .jpeg, .tiff]
        if let heic = UTType(filenameExtension: "heic") {
            allowedTypes.append(heic)
        }
        if let webp = UTType(filenameExtension: "webp") {
            allowedTypes.append(webp)
        }
        openPanel.allowedContentTypes = allowedTypes

        let picturesURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first
        openPanel.directoryURL = picturesURL ?? FileManager.default.homeDirectoryForCurrentUser

        NSApp.activate(ignoringOtherApps: true)

        isPickingPhoto = true
        openPanel.begin { [weak self] response in
            guard let self = self else { return }
            self.isPickingPhoto = false
            guard response == .OK else { return }
            self.importPhotos(from: openPanel.urls)
        }
    }

    func importPhotos(from urls: [URL]) {
        var lastAddedId: String? = nil

        for url in urls {
            guard let sourceImage = NSImage(contentsOf: url) else { continue }
            let targetSize = NSSize(width: 256, height: 256)
            guard let pngData = squareCropAndResizePNG(image: sourceImage, targetSize: targetSize),
                  let squareImage = NSImage(data: pngData) else { continue }

            let id = UUID().uuidString
            let fileURL = avatarsDirectoryURL.appendingPathComponent("\(id).png")

            try? pngData.write(to: fileURL, options: .atomic)
            savedAvatars.append(CustomAvatarItem(id: id, image: squareImage))
            lastAddedId = id
        }

        if let newId = lastAddedId {
            selectAvatar(id: newId)
        }
    }

    func deleteAvatar(id: String) {
        let fileURL = avatarsDirectoryURL.appendingPathComponent("\(id).png")
        try? FileManager.default.removeItem(at: fileURL)

        savedAvatars.removeAll { $0.id == id }

        if selectedAvatarId == id {
            selectAvatar(id: nil)
        } else {
            syncCurrentAvatarFile()
        }
    }

    private func loadSavedSettings() {
        var savedPitch = UserDefaults.standard.float(forKey: voicePitchKey)
        if savedPitch <= 0 {
            savedPitch = UserDefaults.standard.float(forKey: "EchoBuddy.VoicePitch")
        }
        if savedPitch > 0 {
            voicePitch = savedPitch
        }
        var savedRate = UserDefaults.standard.float(forKey: voiceRateKey)
        if savedRate <= 0 {
            savedRate = UserDefaults.standard.float(forKey: "EchoBuddy.VoiceRate")
        }
        if savedRate > 0 {
            voiceRate = savedRate
        }
        isMuted = UserDefaults.standard.bool(forKey: mutedKey)
        autoSpeak = UserDefaults.standard.bool(forKey: autoSpeakKey)
        if UserDefaults.standard.object(forKey: hotkeyEnabledKey) != nil {
            globalHotkeyEnabled = UserDefaults.standard.bool(forKey: hotkeyEnabledKey)
        } else {
            globalHotkeyEnabled = true
        }
    }

    private func loadSavedAvatars() {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: avatarsDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }

        var loaded: [CustomAvatarItem] = []
        for file in files where file.pathExtension.lowercased() == "png" {
            let id = file.deletingPathExtension().lastPathComponent
            if let img = NSImage(contentsOf: file) {
                loaded.append(CustomAvatarItem(id: id, image: img))
            }
        }
        self.savedAvatars = loaded

        var savedId = UserDefaults.standard.string(forKey: selectedAvatarKey)
        if savedId == nil {
            savedId = UserDefaults.standard.string(forKey: "EchoBuddy.SelectedAvatarId")
        }
        if let savedId = savedId, loaded.contains(where: { $0.id == savedId }) {
            self.selectedAvatarId = savedId
        } else {
            self.selectedAvatarId = nil
        }
    }

    private func migrateLegacyAvatarIfNeeded() {
        let legacyFile = appSupportURL.appendingPathComponent("custom_avatar.png")
        if FileManager.default.fileExists(atPath: legacyFile.path) {
            let id = UUID().uuidString
            let newFile = avatarsDirectoryURL.appendingPathComponent("\(id).png")
            try? FileManager.default.moveItem(at: legacyFile, to: newFile)
            UserDefaults.standard.set(id, forKey: selectedAvatarKey)
        }
    }

    private func squareCropAndResizePNG(image: NSImage, targetSize: NSSize) -> Data? {
        let size = image.size
        let minDimension = min(size.width, size.height)
        guard minDimension > 0 else { return nil }

        let cropRect = NSRect(
            x: (size.width - minDimension) / 2.0,
            y: (size.height - minDimension) / 2.0,
            width: minDimension,
            height: minDimension
        )

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        let ctx = NSGraphicsContext(bitmapImageRep: rep)
        ctx?.imageInterpolation = .high
        NSGraphicsContext.current = ctx
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: cropRect,
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }
}
