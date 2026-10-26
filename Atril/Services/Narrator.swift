import AVFoundation
import Observation

/// Lee en voz alta el texto de las escenas con una voz española del sistema.
@MainActor
@Observable
final class Narrator: NSObject {
    static let shared = Narrator()

    static let voiceKey = "narratorVoice"
    static let rateKey = "narratorRate"

    /// Identificador del texto que se está leyendo, para que cada botón sepa si es el suyo.
    private(set) var speakingID: String?
    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Voces en español, de mejor a peor calidad.
    static var spanishVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("es") }
            .sorted { ($0.quality.rawValue, $0.language == "es-ES" ? 1 : 0) > ($1.quality.rawValue, $1.language == "es-ES" ? 1 : 0) }
    }

    static var preferredVoice: AVSpeechSynthesisVoice? {
        if let id = UserDefaults.standard.string(forKey: voiceKey), let voice = AVSpeechSynthesisVoice(identifier: id) {
            return voice
        }
        return spanishVoices.first ?? AVSpeechSynthesisVoice(language: "es-ES")
    }

    /// Velocidad relativa: 1 es la normal del sistema; por defecto algo más pausada para narrar.
    static var rate: Float {
        let stored = UserDefaults.standard.object(forKey: rateKey) as? Double ?? 0.9
        return Float(stored)
    }

    func isSpeaking(_ id: String) -> Bool { speakingID == id }

    /// Empieza a leer, o para si ya se estaba leyendo ese mismo texto.
    func toggle(_ text: String, id: String) {
        if speakingID == id {
            stop()
        } else {
            speak(text, id: id)
        }
    }

    func speak(_ text: String, id: String) {
        synthesizer.stopSpeaking(at: .immediate)
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
        // Pausas un poco más largas entre frases: la narración gana atmósfera.
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Self.rate
        utterance.pitchMultiplier = 0.95
        utterance.postUtteranceDelay = 0.2
        speakingID = id
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        speakingID = nil
    }
}

extension Narrator: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingID = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synthesizer.isSpeaking { self.speakingID = nil }
        }
    }
}
