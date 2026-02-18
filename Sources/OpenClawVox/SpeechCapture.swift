import Foundation
import Speech
import AVFoundation

final class SpeechCapture: NSObject, SFSpeechRecognizerDelegate {
    var onPartialText: ((String) -> Void)?
    var onFinalText: ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var lastNonEmptyTranscript: String = ""

    func start() async throws {
        ocvLog("STT", "start() called")
        lastNonEmptyTranscript = ""
        guard let recognizer, recognizer.isAvailable else {
            ocvLog("STT", "recognizer unavailable")
            throw NSError(domain: "Speech", code: 0, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable on this device/session"])
        }

        let speechAuth = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        ocvLog("STT", "speech auth status: \(speechAuth.rawValue)")
        guard speechAuth == .authorized else {
            throw NSError(domain: "Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "Speech recognition permission denied. Enable it in System Settings > Privacy & Security > Speech Recognition."])
        }

        let micAuth = await AVCaptureDevice.requestAccess(for: .audio)
        ocvLog("STT", "mic auth granted: \(micAuth)")
        guard micAuth else {
            throw NSError(domain: "Speech", code: 2, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied. Enable it in System Settings > Privacy & Security > Microphone."])
        }

        task?.cancel()
        task = nil

        request = SFSpeechAudioBufferRecognitionRequest()
        request?.shouldReportPartialResults = true

        guard let request else {
            throw NSError(domain: "Speech", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create recognition request"])
        }

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        try engine.start()
        ocvLog("STT", "audio engine started")

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let result {
                let raw = result.bestTranscription.formattedString
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

                if !text.isEmpty {
                    self?.lastNonEmptyTranscript = text
                    self?.onPartialText?(text)
                }

                if result.isFinal {
                    ocvLog("STT", "final transcription emitted")
                    self?.stop()
                    let finalText = text.isEmpty ? (self?.lastNonEmptyTranscript ?? "") : text
                    ocvLog("STT", "final transcription content: \(finalText.isEmpty ? "<empty>" : finalText)")
                    self?.onFinalText?(finalText)
                }
            } else if let error {
                ocvLog("STT", "recognition task error: \(error.localizedDescription)")
                self?.stop()
            }
        }
    }

    func latestTranscriptSnapshot() -> String {
        lastNonEmptyTranscript
    }

    func stop() {
        ocvLog("STT", "stop() called")
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }
}
