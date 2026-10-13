import AppKit
import SwiftUI

@main
struct TVKumandaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Menü çubuğu simgesi ve ondan oklu bir “çıkıntı” ile açılan panel.
/// (SwiftUI MenuBarExtra bu oku çizmediği için NSPopover kullanılıyor.)
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tv = TVController()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        Snapshot.runIfRequested(tv)
        #endif

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        observeIcon()

        let hosting = NSHostingController(rootView: RootView().environment(tv))
        hosting.sizingOptions = .preferredContentSize
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.appearance = NSAppearance(named: .darkAqua)
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        paintPopoverFrame()
        NSApp.activate()
        popover.contentViewController?.view.window?.makeKey()
        Task { await tv.refresh() }
    }

    /// Okun da panel ile aynı renkte olması için popover çerçevesini boyar.
    private func paintPopoverFrame() {
        guard let frame = popover.contentViewController?.view.window?.contentView?.superview,
              !frame.subviews.contains(where: { $0 is PopoverBackground }) else { return }
        let background = PopoverBackground(frame: frame.bounds)
        background.autoresizingMask = [.width, .height]
        frame.addSubview(background, positioned: .below, relativeTo: nil)
    }

    private func observeIcon() {
        let online = withObservationTracking { tv.isOnline } onChange: { [weak self] in
            Task { @MainActor in self?.observeIcon() }
        }
        let image = NSImage(systemSymbolName: online ? "tv.fill" : "tv", accessibilityDescription: "TV Kumanda")
        image?.isTemplate = true
        statusItem.button?.image = image
    }
}

private final class PopoverBackground: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(Theme.background).setFill()
        bounds.fill()
    }
}
