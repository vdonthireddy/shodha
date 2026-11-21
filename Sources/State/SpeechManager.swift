import Foundation
@preconcurrency import AVFoundation

struct VoiceOption: Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
}

@MainActor
final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var mutedWorkItem: DispatchWorkItem?

    @Published var selectedVoiceId: String = ""
    @Published var availableVoices: [VoiceOption] = []

    var onSpeechStarted: (@MainActor () -> Void)?
    var onSpeechFinished: (@MainActor () -> Void)?

    private let voiceIdKey = "Shodha.VoiceIdentifier"

    override init() {
        super.init()
        synthesizer.delegate = self
        loadVoices()
        if let saved = UserDefaults.standard.string(forKey: voiceIdKey),
           availableVoices.contains(where: { $0.id == saved }) {
            selectedVoiceId = saved
        }
    }

    func setVoice(identifier: String) {
        selectedVoiceId = identifier
        UserDefaults.standard.set(identifier, forKey: voiceIdKey)
    }

    private func loadVoices() {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality.rawValue > rhs.quality.rawValue
                }
                return lhs.name < rhs.name
            }
        self.availableVoices = voices.map {
            VoiceOption(id: $0.identifier, name: $0.name, language: $0.language)
        }
    }

    func speak(text: String, pitch: Float = 1.2, rate: Float = 0.5, isMuted: Bool = false) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        mutedWorkItem?.cancel()
        mutedWorkItem = nil

        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        if isMuted {
            onSpeechStarted?()
            let duration = min(6.0, max(1.5, Double(cleanText.count) * 0.06))
            let item = DispatchWorkItem { [weak self] in
                self?.onSpeechFinished?()
            }
            mutedWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
            return
        }

        let utterance = AVSpeechUtterance(string: cleanText)
        utterance.rate = min(max(rate, 0.2), 0.8)
        utterance.pitchMultiplier = min(max(pitch, 0.5), 1.8)

        if !selectedVoiceId.isEmpty, let voice = AVSpeechSynthesisVoice(identifier: selectedVoiceId) {
            utterance.voice = voice
        } else if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }

        synthesizer.speak(utterance)
    }

    func stop() {
        mutedWorkItem?.cancel()
        mutedWorkItem = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        onSpeechFinished?()
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onSpeechStarted?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onSpeechFinished?()
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.onSpeechFinished?()
        }
    }
}
