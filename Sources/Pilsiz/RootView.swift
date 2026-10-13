import AppKit
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case now, remote, channels, apps, share, activity, settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .now: "tv"
        case .remote: "dot.circle.and.hand.point.up.left.fill"
        case .channels: "list.number"
        case .apps: "square.grid.2x2"
        case .share: "rectangle.on.rectangle.angled"
        case .activity: "chart.bar.xaxis"
        case .settings: "slider.horizontal.3"
        }
    }

    var title: String {
        switch self {
        case .now: "Ekranda"
        case .remote: "Kumanda"
        case .channels: "Kanallar"
        case .apps: "Uygulamalar"
        case .share: "TV'de göster"
        case .activity: "Aktivite"
        case .settings: "Ayarlar"
        }
    }
}

struct RootView: View {
    /// Anlık görüntü modunda ScrollView çizilemediği için kapatılır.
    nonisolated(unsafe) static var scrolls = true

    @Environment(TVController.self) private var tv
    @Environment(PanelState.self) private var panel
    @AppStorage("tab") private var tab: Tab = .now
    @State private var dropTargeted = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            if let error = tv.lastError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.top, 8)
            }
            if Self.scrolls {
                ScrollView { paddedContent }
                    .scrollIndicators(.never)
                    .frame(height: 560)
            } else {
                paddedContent
            }
            footer
        }
        .frame(width: 340)
        .background(Theme.background)
        .environment(\.colorScheme, .dark)
        .tint(Theme.accent)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(phases: [.down, .repeat], action: handle)
        .onDrop(of: [.fileURL, .url, .plainText], isTargeted: $dropTargeted, perform: handleDrop)
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .overlay(Label("TV'de göster", systemImage: "rectangle.on.rectangle.angled")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(10)
                        .background(Capsule().fill(Theme.background)))
                    .padding(6)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            focused = true
            Task { await tv.refresh() }
        }
    }

    /// Panele bırakılanlar: fotoğraf/video dosyaları TV'de gösterilir, YouTube linki TV'de oynatılır.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        Task { @MainActor in
            var links: [String] = []
            var files: [URL] = []
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self), let url = await Self.loadURL(provider) {
                    if url.isFileURL { files.append(url) } else { links.append(url.absoluteString) }
                } else if let text = await Self.loadText(provider) {
                    links.append(text)
                }
            }
            if !files.isEmpty {
                tv.share.share(files, tv: tv)
                tab = .share
            } else if let video = links.lazy.compactMap(YouTubeVideo.init(link:)).first {
                tv.playYouTube(video)
                tab = .apps
            }
        }
        return true
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { text, _ in continuation.resume(returning: text as? String) }
        }
    }

    private var paddedContent: some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
    }

    @ViewBuilder private var content: some View {
        if panel.paletteOpen {
            CommandPalette()
        } else {
            VStack(spacing: 10) {
                if tv.assistant.phase != .idle {
                    AssistantBubble(assistant: tv.assistant, onItem: openAssistantItem)
                        .overlay(alignment: .topTrailing) {
                            Button { tv.assistant.reset() } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                                    .padding(8)
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                tabContent
            }
            .animation(.snappy(duration: 0.2), value: tv.assistant.phase)
        }
    }

    /// Cevaptaki satıra tıklanınca: yayındaysa kanala geç, ileride ise hatırlatıcı kur.
    private func openAssistantItem(_ item: AssistantReply.Item) {
        if let programme = item.programme, programme.start > Date() {
            if !tv.reminders.isSet(channel: item.channel, programme: programme) {
                tv.reminders.toggle(channel: item.channel, programme: programme)
            }
        } else {
            tv.switchTo(item.channel)
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .now: NowTab()
        case .remote: RemoteTab()
        case .channels: ChannelsTab()
        case .apps: AppsTab()
        case .share: ShareTab()
        case .activity: ActivityTab()
        case .settings: SettingsTab()
        }
    }

    // MARK: - Başlık

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.accent.gradient)
                Image(systemName: "tv").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(tv.name).font(.system(size: 14, weight: .semibold))
                Text("Daewoo 43DE54F · Vestel").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if tv.isListening { tv.finishListening() } else { tv.startListening() }
            } label: {
                Image(systemName: tv.isListening ? "waveform" : "mic.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tv.isListening ? .white : .secondary)
                    .symbolEffect(.variableColor.iterative, isActive: tv.isListening)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(tv.isListening ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.key)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Pilsiz'e söyle (⌃⌥⌘ Space)")
            Button {
                panel.paletteOpen.toggle()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(panel.paletteOpen ? Theme.accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.key))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Kanal ara (⌘K)")
            KeyButton(action: tv.power, help: tv.isOnline ? "Kapat" : "Aç") {
                Image(systemName: "power")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(tv.isOnline ? Theme.accent : .secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.key))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { item in
                Button {
                    tab = item
                    panel.paletteOpen = false
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(tab == item ? Theme.accent : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tab == item ? Theme.accent.opacity(0.18) : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
        .padding(.horizontal, 12)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 6, height: 6)
            Text(statusText).font(.system(size: 10.5)).foregroundStyle(.secondary)
            Spacer()
            Text(tv.host).font(.system(size: 9.5, design: .monospaced)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.025))
    }

    private var statusColor: Color {
        switch tv.status {
        case .online: .green
        case .waking, .searching: .orange
        case .offline: Theme.accent
        case .unknown: .gray
        }
    }

    private var statusText: String {
        switch tv.status {
        case .online: "Bağlı"
        case .offline: tv.host.isEmpty ? "TV ayarlanmadı" : "TV kapalı ya da ulaşılamıyor"
        case .waking: "Uyandırılıyor…"
        case .searching: "Ağda aranıyor…"
        case .unknown: "Kontrol ediliyor…"
        }
    }

    // MARK: - Klavye kısayolları (Ekranda ve Kumanda sekmelerinde)

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        if press.modifiers.contains(.command), press.characters.lowercased() == "k" {
            panel.paletteOpen.toggle()
            return .handled
        }
        guard !panel.paletteOpen, tab == .now || tab == .remote else { return .ignored }
        // Bir yazı alanı düzenleniyorsa (ör. "TV'deki değer") tuşlar ona gitsin.
        if NSApp.keyWindow?.firstResponder is NSText { return .ignored }
        let key: RemoteKey? = switch press.key {
        case .upArrow: .up
        case .downArrow: .down
        case .leftArrow: .left
        case .rightArrow: .right
        case .return: .ok
        case .delete: .back
        case .space: .play
        default:
            switch press.characters.lowercased() {
            case "+", "=": .volumeUp
            case "-": .volumeDown
            case "m": .mute
            case "]": .channelUp
            case "[": .channelDown
            case "h": .home
            case "s": .source
            case "i": .info
            case "e": .exit
            case let c where c.count == 1 && c.first!.isNumber: c.first!.wholeNumberValue.map(RemoteKey.digit)
            default: nil
            }
        }
        guard let key else { return .ignored }
        if press.phase == .repeat, key == .ok { return .handled }
        tv.press(key)
        return .handled
    }
}
