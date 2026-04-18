import AVFoundation
import Foundation
import SwiftUI
import Combine

final class ChatSpeechHelper: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    @Published private var speakingMessageID: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func toggle(text: String, id: UUID) {
        if speakingMessageID == id {
            synthesizer.stopSpeaking(at: .immediate)
            speakingMessageID = nil
            return
        }
        speakingMessageID = id
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func isSpeaking(_ id: UUID) -> Bool {
        speakingMessageID == id && synthesizer.isSpeaking
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        speakingMessageID = nil
    }
}
