import AppKit
import Carbon.HIToolbox
import SwiftUI
import UserNotifications

@main
struct PilsizApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Menü çubuğunda simgenin yanında ne yazacağı.
enum MenuBarStyle: String, CaseIterable, Identifiable {
    case icon, channel, programme

    var id: String { rawValue }
    var title: String {
        switch self {
        case .icon: "Simge"
        case .channel: "Kanal"
        case .programme: "Kanal + program"
        }
    }
}

/// Menü çubuğu simgesi ve ondan oklu bir “çıkıntı” ile açılan panel.
/// (SwiftUI MenuBarExtra bu oku çizmediği için NSPopover kullanılıyor.)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let tv = TVController()
    private let panel = PanelState()
    private let hotKeys = GlobalHotKeys()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private lazy var hud = VoiceHUD(tv: tv)
    private var talkKeyDown: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Snapshot.runIfRequested(tv) { return }
        #endif
        // Oturum açılışında değil de kullanıcı açtıysa (Dock, masaüstü kısayolu, Finder) paneli göster.
        let launchedAtLogin = NSAppleEventManager.shared().currentAppleEvent?
            .paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.imagePosition = .imageLeading
        observeStatusItem()

        let hosting = NSHostingController(rootView: RootView().environment(tv).environment(panel))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)

        if !launchedAtLogin {
            Task { @MainActor in self.showPopover() }
        }

        UNUserNotificationCenter.current().delegate = self
        ReminderStore.registerCategory()
        observeAssistant()

        applySettings()
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySettings() }
        }
        // Menü çubuğundaki program adı dakikada bir güncellenir.
        Task { [weak self] in
            while let self {
                try? await Task.sleep(for: .seconds(60))
                self.updateStatusItem()
            }
        }
    }

    // MARK: - Panel

    /// Uygulama zaten çalışırken Dock'taki ya da masaüstündeki ikona tıklanınca paneli aç.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPopover()
        return false
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        if !popover.isShown {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            paintPopoverFrame()
        }
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        Task { await tv.refresh() }
    }

    // MARK: - Pilsiz'e söyle

    private func talkPressed() {
        talkKeyDown = Date()
        if tv.isListening { tv.finishListening() } else { tv.startListening() }
    }

    private func talkReleased() {
        defer { talkKeyDown = nil }
        guard let down = talkKeyDown, Date().timeIntervalSince(down) > 0.45 else { return }
        tv.finishListening()
    }

    /// Panel kapalıyken asistanın durumu ekranın üstündeki kapsülde gösterilir.
    private func observeAssistant() {
        let phase = withObservationTracking { tv.assistant.phase } onChange: { [weak self] in
            Task { @MainActor in self?.observeAssistant() }
        }
        guard !popover.isShown else { return }
        switch phase {
        case .idle:
            break
        case .listening, .thinking:
            hud.show()
        case .done:
            hud.show()
            let lines = tv.assistant.reply?.items.count ?? 0
            hud.hide(after: lines == 0 ? 3.5 : 6 + Double(lines)) { [weak self] in
                if self?.tv.assistant.phase == .done { self?.tv.assistant.reset() }
            }
        }
    }

    private func showPalette() {
        panel.paletteOpen = true
        showPopover()
    }

    /// Okun da panel ile aynı renkte olması için popover çerçevesini boyar.
    private func paintPopoverFrame() {
        guard let frame = popover.contentViewController?.view.window?.contentView?.superview,
              !frame.subviews.contains(where: { $0 is PopoverBackground }) else { return }
        let background = PopoverBackground(frame: frame.bounds)
        background.autoresizingMask = [.width, .height]
        frame.addSubview(background, positioned: .below, relativeTo: nil)
    }

    // MARK: - Ayarlar ve kısayollar

    /// Kısayolların en son kaydedildiği hâl; yalnızca değiştiğinde yeniden kaydedilir.
    private var hotKeyState: String?

    private func applySettings() {
        let enabled = UserDefaults.standard.object(forKey: "globalHotKeys") as? Bool ?? true
        let bindings = HotKeyBindings.current
        let state = enabled ? "on|" + bindings.rawValue : "off"
        if state != hotKeyState {
            hotKeyState = state
            if enabled { registerHotKeys(bindings) } else { hotKeys.unregisterAll() }
        }
        updateStatusItem()
    }

    private func registerHotKeys(_ bindings: HotKeyBindings) {
        hotKeys.register(HotKeyAction.allCases.compactMap { action -> GlobalHotKeys.HotKey? in
            guard let combo = bindings[action] else { return nil }
            return switch action {
            case .volumeUp: .init(combo: combo) { [tv] in tv.press(.volumeUp) }
            case .volumeDown: .init(combo: combo) { [tv] in tv.press(.volumeDown) }
            case .channelUp: .init(combo: combo) { [tv] in tv.press(.channelUp) }
            case .channelDown: .init(combo: combo) { [tv] in tv.press(.channelDown) }
            case .mute: .init(combo: combo) { [tv] in tv.press(.mute) }
            case .search: .init(combo: combo) { [weak self] in self?.showPalette() }
            // Basılı tut ve konuş; kısa basışta konuşma bitince kendiliğinden durur.
            case .talk: .init(combo: combo, action: { [weak self] in self?.talkPressed() },
                              release: { [weak self] in self?.talkReleased() })
            }
        })
    }

    // MARK: - Menü çubuğu

    private func observeStatusItem() {
        withObservationTracking { updateStatusItem() } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatusItem() }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: tv.isOnline ? "tv.fill" : "tv", accessibilityDescription: "Pilsiz")
        image?.isTemplate = true
        button.image = image

        let style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .channel
        button.attributedTitle = statusTitle(style: style)
    }

    /// Kanal, logosu varsa adı yerine logosuyla gösterilir.
    private func statusTitle(style: MenuBarStyle) -> NSAttributedString {
        let font = NSFont.menuBarFont(ofSize: 0)
        func text(_ string: String) -> NSAttributedString {
            NSAttributedString(string: string, attributes: [.font: font])
        }
        guard style != .icon, tv.isOnline else { return text("") }
        if let app = tv.runningApp { return text(" " + app.name) }
        guard let channel = tv.currentChannel else { return text("") }

        let title = NSMutableAttributedString(attributedString: text(" "))
        if let logo = LogoCatalog.image(for: channel.name), logo.size.height > 0 {
            let height: CGFloat = 14
            let attachment = NSTextAttachment()
            attachment.image = logo
            // Logo satırın ortasına gelsin diye taban çizgisinin altına sarkıtılır.
            attachment.bounds = NSRect(x: 0, y: (font.capHeight - height) / 2,
                                       width: logo.size.width / logo.size.height * height, height: height)
            title.append(NSAttributedString(attachment: attachment))
        } else {
            title.append(text(shortName(channel.name)))
        }
        if style == .programme, let programme = tv.epg.schedule(for: channel.name).now {
            let name = programme.title.count > 22 ? programme.title.prefix(21) + "…" : programme.title
            title.append(text(" · \(name)"))
        }
        return title
    }

    /// "TRT 1 HD" → "TRT 1": menü çubuğunda yer kazanmak için.
    private func shortName(_ name: String) -> String {
        name.replacingOccurrences(of: " HD", with: "").trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Bildirimler

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == ReminderStore.switchAction
                || response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let number = response.notification.request.content.userInfo["channel"] as? Int else { return }
        await MainActor.run { tv.open(channelNumber: number) }
    }
}

private final class PopoverBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(Theme.background).setFill()
        bounds.fill()
    }
}
