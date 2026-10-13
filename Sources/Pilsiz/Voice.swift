import AppKit
import AVFoundation
import Speech
import SwiftUI

/// Türkçe, cihaz içi konuşma tanıma. Mikrofon sesi Mac'ten dışarı çıkmaz.
@MainActor
final class VoiceListener {
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private var session: SpeechSession?
    private var silenceTask: Task<Void, Never>?
    private var latest = ""
    private var finalContinuation: CheckedContinuation<String, Never>?

    var isListening: Bool { session != nil }

    /// Mikrofon ve konuşma tanıma izinleri; ilk kullanımda macOS sorar.
    static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
        }
        let microphone = await AVCaptureDevice.requestAccess(for: .audio)
        return speech && microphone
    }

    /// Dinlemeye başlar. `onSilence`: konuşma bitince (kısa sessizlik) çağrılır.
    func start(onText: @escaping @MainActor (String) -> Void, onSilence: @escaping @MainActor () -> Void) throws {
        guard let recognizer, recognizer.isAvailable else { throw VoiceError.unavailable }
        latest = ""
        let session = SpeechSession()
        try session.start(recognizer: recognizer) { [weak self] text, isFinal in
            Task { @MainActor in
                guard let self else { return }
                if !text.isEmpty {
                    self.latest = text
                    onText(text)
                    self.restartSilenceTimer(onSilence)
                }
                if isFinal { self.deliverFinal() }
            }
        }
        self.session = session
        // Hiç konuşulmazsa 8 sn sonra, konuşma uzarsa 15 sn sonra bitir.
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            if self?.latest.isEmpty == true { onSilence() }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            if self?.session === session { onSilence() }
        }
    }

    /// Dinlemeyi bitirir ve son metni döndürür.
    func stop() async -> String {
        guard let session else { return latest }
        silenceTask?.cancel()
        session.finishAudio()
        let text = await withCheckedContinuation { continuation in
            finalContinuation = continuation
            // Kesin sonuç gecikirse eldeki metinle devam edilir.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(1.2))
                self?.deliverFinal()
            }
        }
        session.cancel()
        self.session = nil
        return text
    }

    private func restartSilenceTimer(_ onSilence: @escaping @MainActor () -> Void) {
        silenceTask?.cancel()
        silenceTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            if !Task.isCancelled { onSilence() }
        }
    }

    private func deliverFinal() {
        finalContinuation?.resume(returning: latest)
        finalContinuation = nil
    }

    enum VoiceError: LocalizedError {
        case unavailable
        var errorDescription: String? { "Türkçe konuşma tanıma şu an kullanılamıyor." }
    }
}

/// Ses motoru ve tanıma isteği; ses iş parçacığından erişildiği için ayrı tutulur.
private final class SpeechSession: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let request = SFSpeechAudioBufferRecognitionRequest()
    private var task: SFSpeechRecognitionTask?

    func start(recognizer: SFSpeechRecognizer, onResult: @escaping @Sendable (String, Bool) -> Void) throws {
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = false
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { [self] buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()
        task = recognizer.recognitionTask(with: request) { result, error in
            if let result {
                onResult(result.bestTranscription.formattedString, result.isFinal)
            } else if error != nil {
                onResult("", true)
            }
        }
    }

    func finishAudio() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request.endAudio()
    }

    func cancel() {
        task?.cancel()
    }
}

// MARK: - Ekranın üstündeki kapsül

/// Konuşurken ve cevap gelince ekranın üstünde beliren, tıklanamayan kapsül.
@MainActor
final class VoiceHUD {
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?

    init(tv: TVController) {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 220),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let host = NSHostingView(rootView: VoiceHUDView().environment(tv))
        host.sizingOptions = []
        panel.contentView = host
    }

    func show() {
        hideTask?.cancel()
        guard let screen = NSScreen.main else { return }
        let frame = panel.frame
        let origin = NSPoint(x: screen.frame.midX - frame.width / 2,
                             y: screen.visibleFrame.maxY - frame.height - 8)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
    }

    /// Cevaptan sonra okunacak kadar bekleyip gizlenir.
    func hide(after seconds: Double, then completion: @escaping @MainActor () -> Void = {}) {
        hideTask?.cancel()
        hideTask = Task { [panel] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 0 }
            panel.orderOut(nil)
            completion()
        }
    }
}

private struct VoiceHUDView: View {
    @Environment(TVController.self) private var tv

    var body: some View {
        VStack {
            AssistantBubble(assistant: tv.assistant)
                .frame(width: 440)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .environment(\.colorScheme, .dark)
    }
}

/// Asistanın o anki durumu: dinleniyor, düşünülüyor ya da cevap. Kapsülde ve panelde kullanılır.
struct AssistantBubble: View {
    let assistant: Assistant
    var onItem: ((AssistantReply.Item) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.accent.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    if assistant.phase == .listening || !assistant.transcript.isEmpty {
                        Text(assistant.transcript.isEmpty ? "Dinliyorum…" : "“\(assistant.transcript)”")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if let reply = assistant.reply {
                        Text(reply.text)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(reply.success ? Color.primary : Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if assistant.phase == .thinking {
                        Text("Düşünüyorum…").font(.system(size: 13.5, weight: .semibold))
                    }
                }
                Spacer(minLength: 0)
            }
            if let items = assistant.reply?.items, !items.isEmpty {
                VStack(spacing: 4) {
                    ForEach(items) { item in
                        HStack(spacing: 8) {
                            ChannelLogo(name: item.channel.name, height: 14).frame(width: 36)
                            if let programme = item.programme {
                                Text((Calendar.current.isDateInToday(programme.start) ? "" : dayLabel(programme.start) + " ") + clock(programme.start))
                                    .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                                Text(programme.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            } else {
                                Text(item.channel.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            }
                            Spacer(minLength: 4)
                            if onItem != nil {
                                Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.06)))
                        .contentShape(Rectangle())
                        .onTapGesture { onItem?(item) }
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.ultraThinMaterial))
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.background.opacity(0.75)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Theme.accent.opacity(0.35)))
        .animation(.snappy(duration: 0.2), value: assistant.phase)
    }

    @ViewBuilder private var icon: some View {
        switch assistant.phase {
        case .listening:
            Image(systemName: "waveform").symbolEffect(.variableColor.iterative).foregroundStyle(Theme.accent)
        case .thinking:
            Image(systemName: "sparkles").symbolEffect(.pulse).foregroundStyle(Theme.accent)
        case .done:
            Image(systemName: assistant.reply?.success == false ? "questionmark" : "checkmark")
                .foregroundStyle(assistant.reply?.success == false ? Theme.accent : .green)
        case .idle:
            Image(systemName: "mic").foregroundStyle(.secondary)
        }
    }
}
