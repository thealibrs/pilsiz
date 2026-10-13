import AppKit
import Carbon.HIToolbox
import SwiftUI
import UserNotifications

@main
struct TVKumandaApp: App {
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if Snapshot.runIfRequested(tv) { return }
        #endif

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

        UNUserNotificationCenter.current().delegate = self
        ReminderStore.registerCategory()

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

    private var hotKeysEnabled: Bool?

    private func applySettings() {
        let enabled = UserDefaults.standard.object(forKey: "globalHotKeys") as? Bool ?? true
        if enabled != hotKeysEnabled {
            hotKeysEnabled = enabled
            if enabled { registerHotKeys() } else { hotKeys.unregisterAll() }
        }
        updateStatusItem()
    }

    private func registerHotKeys() {
        hotKeys.register([
            .init(keyCode: kVK_UpArrow) { [tv] in tv.press(.volumeUp) },
            .init(keyCode: kVK_DownArrow) { [tv] in tv.press(.volumeDown) },
            .init(keyCode: kVK_RightArrow) { [tv] in tv.press(.channelUp) },
            .init(keyCode: kVK_LeftArrow) { [tv] in tv.press(.channelDown) },
            .init(keyCode: kVK_ANSI_M) { [tv] in tv.press(.mute) },
            .init(keyCode: kVK_ANSI_K) { [weak self] in self?.showPalette() },
        ])
    }

    // MARK: - Menü çubuğu

    private func observeStatusItem() {
        withObservationTracking { updateStatusItem() } onChange: { [weak self] in
            Task { @MainActor in self?.observeStatusItem() }
        }
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let image = NSImage(systemSymbolName: tv.isOnline ? "tv.fill" : "tv", accessibilityDescription: "TV Kumanda")
        image?.isTemplate = true
        button.image = image

        let style = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .channel
        button.title = statusTitle(style: style).map { " " + $0 } ?? ""
        button.font = .menuBarFont(ofSize: 0)
    }

    private func statusTitle(style: MenuBarStyle) -> String? {
        guard style != .icon, tv.isOnline else { return nil }
        if let app = tv.runningApp { return app.name }
        guard let channel = tv.currentChannel else { return nil }
        let name = shortName(channel.name)
        guard style == .programme, let programme = tv.epg.schedule(for: channel.name).now else { return name }
        let title = programme.title.count > 22 ? programme.title.prefix(21) + "…" : programme.title
        return "\(name) · \(title)"
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
