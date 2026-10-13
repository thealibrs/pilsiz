import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case now, remote, channels, apps, activity, settings

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .now: "tv"
        case .remote: "dot.circle.and.hand.point.up.left.fill"
        case .channels: "list.number"
        case .apps: "square.grid.2x2"
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
                    .frame(height: 470)
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
        .onAppear {
            focused = true
            Task { await tv.refresh() }
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
            tabContent
        }
    }

    @ViewBuilder private var tabContent: some View {
        switch tab {
        case .now: NowTab()
        case .remote: RemoteTab()
        case .channels: ChannelsTab()
        case .apps: AppsTab()
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
