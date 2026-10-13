import Carbon.HIToolbox

/// Uygulama öndeyken olmasa da çalışan sistem geneli kısayollar (Carbon RegisterEventHotKey).
/// Erişilebilirlik izni gerektirmez.
@MainActor
final class GlobalHotKeys {
    struct HotKey {
        let keyCode: Int
        let action: @MainActor () -> Void
    }

    /// ⌃⌥⌘: tarayıcıların ⌥⌘←/→ sekme kısayollarıyla çakışmasın diye.
    static let modifiers = controlKey | optionKey | cmdKey

    nonisolated(unsafe) private static weak var shared: GlobalHotKeys?
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handler: EventHandlerRef?

    func register(_ hotKeys: [HotKey]) {
        unregisterAll()
        Self.shared = self
        if handler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                // Carbon olayları ana iş parçacığında gelir.
                MainActor.assumeIsolated { GlobalHotKeys.shared?.actions[id.id]?() }
                return noErr
            }, 1, &spec, nil, &handler)
        }
        for (index, hotKey) in hotKeys.enumerated() {
            let id = EventHotKeyID(signature: OSType(0x5456_4B4D), id: UInt32(index + 1)) // 'TVKM'
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotKey.keyCode), UInt32(Self.modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id.id] = hotKey.action
            }
        }
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
    }
}
