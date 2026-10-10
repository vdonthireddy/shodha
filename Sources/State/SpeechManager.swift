import Foundation
import AVFoundation

@MainActor
final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()
    
    var onSpeechStarted: (@MainActor () -> Void)?
    var onSpeechFinished: (@MainActor () -> Void)?
    
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    
    func speak(text: String, pitch: Float = 1.2, rate: Float = 0.5, isMuted: Bool = false) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        // Stop any currently ongoing speech
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        
        if isMuted {
            // Still trigger visual speaking state briefly for silent mode
            onSpeechStarted?()
            let duration = max(1.5, Double(text.count) * 0.08)
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                self?.onSpeechFinished?()
            }
            return
        }
        
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = min(max(rate, 0.2), 0.8)
        utterance.pitchMultiplier = min(max(pitch, 0.5), 1.8)
        
        // Prefer natural English voice if available
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        synthesizer.speak(utterance)
    }
    
    func stop() {
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
