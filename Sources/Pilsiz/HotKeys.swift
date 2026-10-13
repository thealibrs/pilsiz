import AppKit
import Carbon.HIToolbox

/// Uygulama öndeyken olmasa da çalışan sistem geneli kısayollar (Carbon RegisterEventHotKey).
/// Erişilebilirlik izni gerektirmez.
@MainActor
final class GlobalHotKeys {
    struct HotKey {
        let combo: KeyCombo
        let action: @MainActor () -> Void
        /// Tuş bırakıldığında (basılı tut ve konuş gibi).
        var release: (@MainActor () -> Void)?
    }

    /// Ayarlarda yeni kısayol kaydedilirken, basılan tuşları Carbon yutmasın diye kısayollar geçici olarak kaldırılır.
    static var isSuspended = false {
        didSet { shared?.sync() }
    }

    nonisolated(unsafe) private static weak var shared: GlobalHotKeys?
    private var wanted: [HotKey] = []
    private var refs: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var releases: [UInt32: @MainActor () -> Void] = [:]
    private var handler: EventHandlerRef?

    func register(_ hotKeys: [HotKey]) {
        Self.shared = self
        if handler == nil {
            var specs = [
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
            ]
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
                let released = GetEventKind(event) == UInt32(kEventHotKeyReleased)
                // Carbon olayları ana iş parçacığında gelir.
                MainActor.assumeIsolated {
                    if released { GlobalHotKeys.shared?.releases[id.id]?() } else { GlobalHotKeys.shared?.actions[id.id]?() }
                }
                return noErr
            }, specs.count, &specs, nil, &handler)
        }
        wanted = hotKeys
        sync()
    }

    func unregisterAll() {
        wanted = []
        sync()
    }

    private func sync() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs = []
        actions = [:]
        releases = [:]
        guard !Self.isSuspended else { return }
        for (index, hotKey) in wanted.enumerated() {
            let id = EventHotKeyID(signature: OSType(0x5456_4B4D), id: UInt32(index + 1)) // 'TVKM'
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(hotKey.combo.keyCode), UInt32(hotKey.combo.modifiers), id,
                                             GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actions[id.id] = hotKey.action
                releases[id.id] = hotKey.release
            }
        }
    }
}

/// Bir tuş ve Carbon değiştirici tuşları (controlKey, optionKey, shiftKey, cmdKey).
struct KeyCombo: Equatable {
    var keyCode: Int
    var modifiers: Int

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// Ayarlarda kaydedilirken basılan tuş.
    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = 0
        if flags.contains(.control) { modifiers |= controlKey }
        if flags.contains(.option) { modifiers |= optionKey }
        if flags.contains(.shift) { modifiers |= shiftKey }
        if flags.contains(.command) { modifiers |= cmdKey }
        self.init(keyCode: Int(event.keyCode), modifiers: modifiers)
    }

    /// "keyCode:modifiers"
    init?(rawValue: String) {
        let parts = rawValue.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        self.init(keyCode: parts[0], modifiers: parts[1])
    }

    var rawValue: String { "\(keyCode):\(modifiers)" }

    /// ⌘, ⌥ ya da ⌃ olmadan (yalnızca F tuşları hariç) her yazışta tetiklenirdi.
    var isAllowed: Bool {
        modifiers & (cmdKey | optionKey | controlKey) != 0 || Self.functionKeys.contains(keyCode)
    }

    /// "⌃⌥⌘ K"
    var display: String {
        var symbols = ""
        if modifiers & controlKey != 0 { symbols += "⌃" }
        if modifiers & optionKey != 0 { symbols += "⌥" }
        if modifiers & shiftKey != 0 { symbols += "⇧" }
        if modifiers & cmdKey != 0 { symbols += "⌘" }
        return symbols.isEmpty ? keyName : "\(symbols) \(keyName)"
    }

    private static let functionKeys = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let specialNames: [Int: String] = {
        var names = [
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_Space: "Space", kVK_Return: "↩", kVK_ANSI_KeypadEnter: "⌤", kVK_Tab: "⇥",
            kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        ]
        for (index, key) in functionKeys.enumerated() { names[key] = "F\(index + 1)" }
        return names
    }()

    /// Tuşun geçerli klavye düzenindeki adı (Türkçe Q'da "Ş" gibi).
    private var keyName: String {
        if let name = Self.specialNames[keyCode] { return name }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let data = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "#\(keyCode)" }
        let layout = unsafeBitCast(data, to: CFData.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = CFDataGetBytePtr(layout).withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) {
            UCKeyTranslate($0, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        let name = String(utf16CodeUnits: chars, count: length).uppercased(with: Locale(identifier: "tr"))
        return status == noErr && !name.trimmingCharacters(in: .whitespaces).isEmpty ? name : "#\(keyCode)"
    }
}

/// Ayarlardan değiştirilebilen sistem geneli kısayollar.
enum HotKeyAction: String, CaseIterable, Identifiable {
    case volumeUp, volumeDown, channelUp, channelDown, mute, search, talk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .volumeUp: "Ses +"
        case .volumeDown: "Ses −"
        case .channelUp: "Kanal +"
        case .channelDown: "Kanal −"
        case .mute: "Sessiz"
        case .search: "Kanal ara"
        case .talk: "Pilsiz'e söyle (basılı tut ve konuş)"
        }
    }

    /// ⌃⌥⌘: tarayıcıların ⌥⌘←/→ sekme kısayollarıyla çakışmasın diye.
    var defaultCombo: KeyCombo {
        let modifiers = controlKey | optionKey | cmdKey
        return switch self {
        case .volumeUp: KeyCombo(keyCode: kVK_UpArrow, modifiers: modifiers)
        case .volumeDown: KeyCombo(keyCode: kVK_DownArrow, modifiers: modifiers)
        case .channelUp: KeyCombo(keyCode: kVK_RightArrow, modifiers: modifiers)
        case .channelDown: KeyCombo(keyCode: kVK_LeftArrow, modifiers: modifiers)
        case .mute: KeyCombo(keyCode: kVK_ANSI_M, modifiers: modifiers)
        case .search: KeyCombo(keyCode: kVK_ANSI_K, modifiers: modifiers)
        case .talk: KeyCombo(keyCode: kVK_Space, modifiers: modifiers)
        }
    }
}

/// Kullanıcının değiştirdiği kısayollar. UserDefaults'ta yalnızca varsayılandan farklı olanlar
/// "mute=46:6400;talk=" biçiminde saklanır; boş değer kısayolun kapatıldığı anlamına gelir.
struct HotKeyBindings: Equatable {
    static let defaultsKey = "hotKeyBindings"
    private var overrides: [HotKeyAction: KeyCombo?] = [:]

    static var current: HotKeyBindings {
        HotKeyBindings(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "")
    }

    init(rawValue: String) {
        for entry in rawValue.split(separator: ";") {
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let action = HotKeyAction(rawValue: String(parts[0])) else { continue }
            overrides[action] = .some(parts.count > 1 ? KeyCombo(rawValue: String(parts[1])) : nil)
        }
    }

    var rawValue: String {
        HotKeyAction.allCases.compactMap { action in
            overrides[action].map { "\(action.rawValue)=\($0?.rawValue ?? "")" }
        }.joined(separator: ";")
    }

    var isCustomized: Bool { !overrides.isEmpty }

    subscript(action: HotKeyAction) -> KeyCombo? {
        get {
            if let combo = overrides[action] { return combo }
            return action.defaultCombo
        }
        set {
            if newValue == action.defaultCombo {
                overrides.removeValue(forKey: action)
            } else {
                overrides[action] = .some(newValue)
            }
        }
    }
}
