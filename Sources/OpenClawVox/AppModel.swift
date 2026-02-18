import SwiftUI
import Foundation
import AppKit
import AVFoundation
import Carbon

struct AgentReply {
    let text: String
    let read: String
}

@MainActor
final class AppModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var transcript: String = ""
    @Published var replyText: String = ""
    @Published var messages: [ChatMessage] = []
    @Published var isRecording: Bool = false

    /// Non-nil while recording and the user has spoken recognizable words.
    var liveTranscript: String? {
        guard isRecording else { return nil }
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty || t == "Listening\u{2026}" { return nil }
        return t
    }
    @Published var isThinking: Bool = false
    @Published var statusText: String = "Idle"
    @Published var isTestingConnection: Bool = false
    @Published var connectionText: String = "Not tested"
    @Published var hotkeyBackendLabel: String = "initializing\u{2026}"
    @Published var inputMonitoringGranted: Bool = false

    @Published var agentName: String = "OpenClaw" {
        didSet { defaults.set(agentName, forKey: "ocv.agentName") }
    }
    @Published var autoSpeak: Bool = true {
        didSet { defaults.set(autoSpeak, forKey: "ocv.autoSpeak") }
    }
    @Published var sessionId: String = "agent:main:main" {
        didSet { defaults.set(sessionId, forKey: "ocv.sessionId") }
    }
    @Published var channelBaseURL: String = "" {
        didSet { defaults.set(channelBaseURL, forKey: "ocv.channelBaseURL") }
    }
    @Published var channelToken: String = "" {
        didSet { defaults.set(channelToken, forKey: "ocv.channelToken") }
    }

    private let defaults = UserDefaults.standard
    private let speaker = AVSpeechSynthesizer()
    private let speech = SpeechCapture()
    private var panelController: OverlayWindowController?
    private var hotkeyService: HotkeyService?
    private var wakeObserver: NSObjectProtocol?
    private var pushToTalkActive = false
    private var replyStreamTask: Task<Void, Never>?
    private var hideOverlayTask: Task<Void, Never>?
    private var didSendCurrentUtterance = false
    private var pendingAssistantMessageId: UUID?
    private var isSpeaking = false
    private var queuedSpeechChunks = 0
    private let preferredVoice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
        // Jamie Premium → Jamie Enhanced → any Premium → any Enhanced
        return voices.first(where: { $0.name.hasPrefix("Jamie") && $0.quality == .premium })
            ?? voices.first(where: { $0.name.hasPrefix("Jamie") && $0.quality == .enhanced })
            ?? voices.first(where: { $0.quality == .premium })
            ?? voices.first(where: { $0.quality == .enhanced })
    }()

    override init() {
        super.init()
        speaker.delegate = self
        if let saved = defaults.string(forKey: "ocv.agentName"), !saved.isEmpty {
            agentName = saved
        }
        if let saved = defaults.string(forKey: "ocv.sessionId"), !saved.isEmpty {
            sessionId = saved
        }
        if let saved = defaults.string(forKey: "ocv.channelBaseURL"), !saved.isEmpty {
            channelBaseURL = saved
        }
        if let saved = defaults.string(forKey: "ocv.channelToken") {
            channelToken = saved
        }
        if defaults.object(forKey: "ocv.autoSpeak") != nil {
            autoSpeak = defaults.bool(forKey: "ocv.autoSpeak")
        }

        // Configure speech + hotkey inline so @Published values are set before
        // SwiftUI begins observation (bootstrap() was too late when called from App.init).
        if let v = preferredVoice {
            ocvLog("App", "TTS voice: \(v.name) (\(v.quality == .premium ? "premium" : "enhanced"), \(v.language))")
        } else {
            ocvLog("App", "TTS voice: system default (download Premium voices in System Settings > Accessibility > Spoken Content)")
        }
        ocvLog("App", "init: configuring speech callbacks + global hotkey (\u{2303}\u{2325} Space)")
        speech.onPartialText = { [weak self] text in
            Task { @MainActor in
                ocvLog("App", "speech partial: \(text.prefix(80))")
                self?.transcript = text
                self?.refreshOverlayHeight()
            }
        }
        speech.onFinalText = { [weak self] text in
            Task { @MainActor in
                ocvLog("App", "speech final: \(text)")
                self?.transcript = text
                self?.sendIfNeeded(text: text)
            }
        }

        installWakeObserver()
        configureHotkeyService(reason: "init")
    }

    deinit {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    private func installWakeObserver() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                ocvLog("App", "wake notification: reconfiguring hotkey service")
                self?.configureHotkeyService(reason: "wake")
            }
        }
    }

    // MARK: - Hotkey

    func requestInputMonitoringAccess() {
        EventTapHotkeyService.requestAccessPrompt()
        configureHotkeyService(reason: "request-access")
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent, source: String) {
        ocvLog("App", "hotkey event=\(event.rawValue) source=\(source)")
        switch event {
        case .down:
            startPushToTalk()
        case .up:
            stopPushToTalk()
        }
    }

    private func configureHotkeyService(reason: String) {
        let keyCode = UInt32(kVK_Space)
        let modifiers = UInt32(controlKey | optionKey)

        hotkeyService = nil
        inputMonitoringGranted = EventTapHotkeyService.preflightAccess()

        if let eventTap = EventTapHotkeyService(keyCode: keyCode, modifiers: modifiers, onEvent: { [weak self] event, source in
            Task { @MainActor in self?.handleHotkeyEvent(event, source: source) }
        }) {
            hotkeyService = eventTap
            hotkeyBackendLabel = "eventTap (Input Monitoring: granted)"
            ocvLog("App", "hotkey backend selected=eventTap reason=\(reason)")
            return
        }

        hotkeyService = CarbonHotkeyService(keyCode: keyCode, modifiers: modifiers, onEvent: { [weak self] event, source in
            Task { @MainActor in self?.handleHotkeyEvent(event, source: source) }
        })
        hotkeyBackendLabel = inputMonitoringGranted ? "carbon fallback" : "carbon fallback (enable Input Monitoring for eventTap)"
        ocvLog("App", "hotkey backend selected=carbon reason=\(reason)")
    }

    // MARK: - Overlay

    func showOverlay() {
        if panelController == nil {
            panelController = OverlayWindowController(model: self)
        }
        cancelOverlayAutoHide()
        refreshOverlayHeight()
        panelController?.show()
    }

    func hideOverlay() {
        panelController?.hide()
    }

    /// Escape key: stop TTS, stop recording, and dismiss the overlay.
    func dismissOverlay() {
        ocvLog("App", "dismissOverlay (escape)")
        speaker.stopSpeaking(at: .immediate)
        queuedSpeechChunks = 0
        isSpeaking = false
        replyStreamTask?.cancel()
        if isRecording {
            isRecording = false
            statusText = "Idle"
            speech.stop()
            pushToTalkActive = false
        }
        cancelOverlayAutoHide()
        hideOverlay()
    }

    private func refreshOverlayHeight() {
        let contentHeight = measureContentHeight()
        // Chrome: header(~28) + footer(~28) + VStack spacing(8*2) + inner padding(10*2)
        //       + outer padding(6*2) + scroll padding(2)
        let chrome: CGFloat = 106
        panelController?.updateHeight(contentHeight: contentHeight + chrome)
    }

    private func measureContentHeight() -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11) // matches SwiftUI .subheadline
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        // Available text width: panel(~500) - outer padding(12) - inner padding(20)
        //   - scroll padding(4) - message h-padding(20) - spacer(24)
        let textWidth: CGFloat = 420

        var height: CGFloat = 0
        for msg in messages {
            let text = msg.text.isEmpty ? " " : msg.text
            let rect = (text as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            height += ceil(rect.height) + 16 + 8 // v-padding(8*2) + spacing(8)
        }

        // Include live transcript bubble while recording
        if let live = liveTranscript {
            let rect = (live as NSString).boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attributes
            )
            height += ceil(rect.height) + 16 + 8
        }

        return max(height, 30)
    }

    private func cancelOverlayAutoHide() {
        hideOverlayTask?.cancel()
        hideOverlayTask = nil
    }

    private func scheduleOverlayAutoHideIfIdle() {
        guard !isRecording && !isThinking && !isSpeaking else { return }
        cancelOverlayAutoHide()
        hideOverlayTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, !self.isRecording, !self.isThinking, !self.isSpeaking else { return }
            self.hideOverlay()
        }
    }

    // MARK: - Recording / Push-to-Talk

    func toggleRecording() {
        isRecording ? stopRecording() : startRecording()
    }

    private func startPushToTalk() {
        guard !pushToTalkActive else { return }
        ocvLog("App", "PTT start")
        pushToTalkActive = true

        // Cut any in-progress TTS so the mic is free and the user isn't talked over.
        if isSpeaking {
            ocvLog("App", "PTT interrupted TTS")
            speaker.stopSpeaking(at: .immediate)
            queuedSpeechChunks = 0
            isSpeaking = false
        }
        replyStreamTask?.cancel()

        if !isRecording { startRecording() }
    }

    private func stopPushToTalk() {
        guard pushToTalkActive else { return }
        ocvLog("App", "PTT stop")
        pushToTalkActive = false
        if isRecording { stopRecording() }
    }

    private func startRecording() {
        ocvLog("App", "startRecording")
        showOverlay()
        cancelOverlayAutoHide()
        transcript = "Listening\u{2026}"
        statusText = "Listening"
        isRecording = true
        didSendCurrentUtterance = false

        Task {
            do {
                try await speech.start()
                await MainActor.run { ocvLog("App", "speech.start success") }
            } catch {
                await MainActor.run {
                    ocvLog("App", "speech.start error: \(error.localizedDescription)")
                    self.isRecording = false
                    self.statusText = "Error"
                    self.replyText = "Mic/STT error: \(error.localizedDescription)"
                    self.scheduleOverlayAutoHideIfIdle()
                }
            }
        }
    }

    private func stopRecording() {
        ocvLog("App", "stopRecording")
        isRecording = false
        statusText = "Idle"
        speech.stop()

        // Fallback: Apple STT may not always emit a final callback in time when stop is
        // user-driven (hotkey up / tap Stop). Send latest transcript if we haven't already.
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard let self else { return }
            guard !self.didSendCurrentUtterance else { return }
            let modelTranscript = self.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            let sttTranscript = self.speech.latestTranscriptSnapshot().trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = (!modelTranscript.isEmpty && modelTranscript != "Listening\u{2026}") ? modelTranscript : sttTranscript
            guard !candidate.isEmpty else {
                ocvLog("App", "fallback send skipped (empty transcript)")
                return
            }
            ocvLog("App", "fallback send with transcript: \(candidate)")
            self.sendIfNeeded(text: candidate)
        }

        scheduleOverlayAutoHideIfIdle()
    }

    // MARK: - Send / Agent

    private func sendIfNeeded(text: String) {
        guard !didSendCurrentUtterance else {
            ocvLog("App", "sendIfNeeded skipped (already sent current utterance)")
            return
        }
        didSendCurrentUtterance = true
        ocvLog("App", "sendIfNeeded accepted")
        send(text: text)
    }

    private func send(text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else {
            ocvLog("App", "send skipped (empty)")
            didSendCurrentUtterance = false
            return
        }
        ocvLog("App", "send -> channel: \(clean)")

        showOverlay()
        cancelOverlayAutoHide()
        replyStreamTask?.cancel()
        isThinking = true
        statusText = "Thinking"

        messages.append(ChatMessage(role: .user, text: clean))
        let pending = ChatMessage(role: .assistant, text: "Thinking\u{2026}")
        messages.append(pending)
        pendingAssistantMessageId = pending.id
        refreshOverlayHeight()

        Task {
            do {
                let agentReply = try await runAgent(message: clean)
                await MainActor.run {
                    ocvLog("App", "reply received (text=\(agentReply.text.count) chars, read=\(agentReply.read.count) chars)")
                    self.streamReply(agentReply)
                }
            } catch {
                await MainActor.run {
                    ocvLog("App", "agent error: \(error.localizedDescription)")
                    if let id = self.pendingAssistantMessageId,
                       let idx = self.messages.firstIndex(where: { $0.id == id }) {
                        self.messages[idx].text = "Agent error: \(error.localizedDescription)"
                    } else {
                        self.messages.append(ChatMessage(role: .assistant, text: "Agent error: \(error.localizedDescription)"))
                    }
                    self.pendingAssistantMessageId = nil
                    self.isThinking = false
                    self.statusText = "Error"
                    self.scheduleOverlayAutoHideIfIdle()
                }
            }
        }
    }

    private func runAgent(message: String) async throws -> AgentReply {
        guard !channelToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "OpenClawVox", code: 401, userInfo: [NSLocalizedDescriptionKey: "Gateway token is empty"])
        }
        return try await runViaChannel(message: message)
    }

    private func runViaChannel(message: String) async throws -> AgentReply {
        guard let url = URL(string: channelBaseURL + "/api/channels/openclaw-vox/message") else {
            throw NSError(domain: "OpenClawVox", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid gateway URL"])
        }
        ocvLog("App", "channel request -> \(url.absoluteString) (session=\(sessionId), msgLen=\(message.count))")

        struct Req: Codable { let sessionId: String; let clientId: String; let message: String }
        struct Resp: Codable { let text: String?; let read: String?; let reply: String?; let error: String? }

        let token = channelToken.trimmingCharacters(in: .whitespacesAndNewlines)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(Req(sessionId: sessionId, clientId: Host.current().localizedName ?? "macbook", message: message))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "OpenClawVox", code: 500, userInfo: [NSLocalizedDescriptionKey: "No HTTP response from gateway"])
        }

        let decoded = try? JSONDecoder().decode(Resp.self, from: data)
        ocvLog("App", "channel response status=\(http.statusCode), bytes=\(data.count)")

        guard (200..<300).contains(http.statusCode) else {
            let msg = decoded?.error ?? String(data: data, encoding: .utf8) ?? "Channel request failed"
            throw NSError(domain: "OpenClawVox", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        // If bridge returns structured {text, read} directly, use them.
        // Otherwise the old bridge returns {reply} containing raw AI output —
        // which may itself be a JSON string with text/read fields.
        if let t = decoded?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
           let r = decoded?.read?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            return AgentReply(text: t, read: r)
        }

        // Old bridge: reply contains raw AI output — try to parse as JSON {text, read}
        struct StructuredReply: Codable { let text: String; let read: String }
        if let raw = decoded?.reply?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
           let innerData = raw.data(using: .utf8),
           let inner = try? JSONDecoder().decode(StructuredReply.self, from: innerData) {
            let t = inner.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let r = inner.read.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !r.isEmpty {
                return AgentReply(text: t, read: r)
            }
        }

        // Final fallback: plain text for both
        let plain = (decoded?.reply ?? decoded?.text)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return AgentReply(text: plain.isEmpty ? "(no reply)" : plain,
                          read: plain.isEmpty ? "(no reply)" : plain)
    }

    // MARK: - Connection test

    func testConnection() {
        guard !isTestingConnection else { return }
        ocvLog("App", "testConnection -> \(channelBaseURL)")
        isTestingConnection = true
        connectionText = "Testing\u{2026}"

        Task {
            do {
                guard let url = URL(string: channelBaseURL + "/api/channels/openclaw-vox/health") else {
                    throw NSError(domain: "OpenClawVox", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid gateway URL"])
                }
                var req = URLRequest(url: url)
                req.httpMethod = "GET"
                req.timeoutInterval = 10
                req.setValue("Bearer \(channelToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")

                let (_, response) = try await URLSession.shared.data(for: req)
                guard let http = response as? HTTPURLResponse else {
                    throw NSError(domain: "OpenClawVox", code: 500, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
                }
                guard (200..<300).contains(http.statusCode) else {
                    throw NSError(domain: "OpenClawVox", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Health endpoint returned \(http.statusCode)"])
                }
                await MainActor.run {
                    ocvLog("App", "testConnection success")
                    self.connectionText = "Connected \u{2705}"
                }
            } catch {
                await MainActor.run {
                    ocvLog("App", "testConnection failed: \(error.localizedDescription)")
                    self.connectionText = "Connection failed: \(error.localizedDescription)"
                }
            }
            await MainActor.run { self.isTestingConnection = false }
        }
    }

    // MARK: - TTS

    private func speak(_ text: String) {
        speaker.stopSpeaking(at: .immediate)
        queuedSpeechChunks = 0
        let clean = sanitizeForSpeech(text)
        guard !clean.isEmpty else {
            isSpeaking = false
            scheduleOverlayAutoHideIfIdle()
            return
        }
        enqueueSpeechChunk(clean)
    }

    private func enqueueSpeechChunk(_ text: String) {
        let clean = sanitizeForSpeech(text)
        guard !clean.isEmpty else { return }
        queuedSpeechChunks += 1
        isSpeaking = true
        let utt = AVSpeechUtterance(string: clean)
        utt.voice = preferredVoice
        utt.rate = 0.48
        speaker.speak(utt)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.queuedSpeechChunks = max(0, self.queuedSpeechChunks - 1)
            self.isSpeaking = self.queuedSpeechChunks > 0 || synthesizer.isSpeaking
            if !self.isSpeaking { self.scheduleOverlayAutoHideIfIdle() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.queuedSpeechChunks = max(0, self.queuedSpeechChunks - 1)
            self.isSpeaking = self.queuedSpeechChunks > 0 || synthesizer.isSpeaking
            if !self.isSpeaking { self.scheduleOverlayAutoHideIfIdle() }
        }
    }

    private func streamReply(_ agentReply: AgentReply) {
        replyStreamTask?.cancel()
        if autoSpeak {
            speaker.stopSpeaking(at: .immediate)
            queuedSpeechChunks = 0
            isSpeaking = false
        }

        // Immediately enqueue the short `read` summary for TTS —
        // the user hears a quick spoken answer while the full text types out.
        if autoSpeak {
            enqueueSpeechChunk(agentReply.read)
        }

        let fullText = agentReply.text

        replyStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard let id = self.pendingAssistantMessageId,
                  let idx = self.messages.firstIndex(where: { $0.id == id }) else {
                self.messages.append(ChatMessage(role: .assistant, text: fullText))
                self.refreshOverlayHeight()
                self.isThinking = false
                self.statusText = "Idle"
                self.scheduleOverlayAutoHideIfIdle()
                return
            }

            self.messages[idx].text = ""
            var charsSinceResize = 0

            for ch in fullText {
                if Task.isCancelled { return }
                self.messages[idx].text.append(ch)
                charsSinceResize += 1

                if charsSinceResize >= 8 {
                    self.refreshOverlayHeight()
                    charsSinceResize = 0
                }

                let delayMs: UInt64
                if ch == "." || ch == "!" || ch == "?" {
                    delayMs = 45
                } else if ch == "," || ch == ";" || ch == ":" {
                    delayMs = 30
                } else {
                    delayMs = 16
                }
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }

            self.pendingAssistantMessageId = nil
            self.refreshOverlayHeight()
            self.isThinking = false
            self.statusText = "Idle"
            self.scheduleOverlayAutoHideIfIdle()
        }
    }

    private func sanitizeForSpeech(_ text: String) -> String {
        let allowedPunctuation = CharacterSet(charactersIn: ".,!?;:'\"()[]{}-")
        var output = ""
        var previousWasSpace = false

        for scalar in text.unicodeScalars {
            if scalar.properties.isEmoji || scalar.properties.isEmojiPresentation {
                if !previousWasSpace {
                    output.append(" ")
                    previousWasSpace = true
                }
                continue
            }

            if CharacterSet.alphanumerics.contains(scalar) || allowedPunctuation.contains(scalar) {
                output.unicodeScalars.append(scalar)
                previousWasSpace = false
                continue
            }

            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                if !previousWasSpace {
                    output.append(" ")
                    previousWasSpace = true
                }
                continue
            }

            if !previousWasSpace {
                output.append(" ")
                previousWasSpace = true
            }
        }

        return output
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
