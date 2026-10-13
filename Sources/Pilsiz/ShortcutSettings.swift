import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Ayarlar'daki "Klavye kısayolları" kartı: kısayola tıklayıp yeni tuşlara basarak değiştirilir.
struct ShortcutsCard: View {
    @AppStorage("globalHotKeys") private var globalHotKeys = true
    @AppStorage(HotKeyBindings.defaultsKey) private var bindingsRaw = ""
    @State private var recording: HotKeyAction?
    @State private var hint: String?
    @State private var monitor: Any?

    private var bindings: HotKeyBindings {
        get { HotKeyBindings(rawValue: bindingsRaw) }
        nonmutating set { bindingsRaw = newValue.rawValue }
    }

    var body: some View {
        Card(title: "Klavye kısayolları", icon: "keyboard") {
            if bindings.isCustomized {
                Button("Varsayılana dön") {
                    recording = nil
                    UserDefaults.standard.removeObject(forKey: HotKeyBindings.defaultsKey)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        } content: {
            Toggle("Her yerde çalışsın (panel kapalıyken de)", isOn: $globalHotKeys)
                .font(.system(size: 12))
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                ForEach(HotKeyAction.allCases) { action in
                    GridRow {
                        recorder(action)
                        Text(action.title).font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("⌘K").font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 7)
                    Text("Kanal ara (panel açıkken)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .opacity(globalHotKeys ? 1 : 0.5)
            Text(hint ?? "Değiştirmek için kısayola tıklayıp yeni tuşlara basın; ⌫ kapatır, esc vazgeçer.")
                .font(.system(size: 10.5))
                .foregroundStyle(hint == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: recording) { _, action in
            hint = nil
            action == nil ? stopRecording() : startRecording()
        }
        .onDisappear { recording = nil }
    }

    private func recorder(_ action: HotKeyAction) -> some View {
        let isRecording = recording == action
        let title = isRecording ? "Tuşlara basın…" : bindings[action]?.display ?? "Yok"
        return Button {
            recording = isRecording ? nil : action
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(isRecording ? Theme.accent : bindings[action] == nil ? .secondary : .primary)
                .padding(.horizontal, 7)
                .frame(minWidth: 96, minHeight: 20, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.key))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isRecording ? Theme.accent : .clear))
        }
        .buttonStyle(.plain)
        .help("Değiştirmek için tıklayın")
    }

    private func startRecording() {
        GlobalHotKeys.isSuspended = true
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { record(event) }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        GlobalHotKeys.isSuspended = false
    }

    private func record(_ event: NSEvent) {
        guard let action = recording else { return }
        let combo = KeyCombo(event: event)
        switch (combo.keyCode, combo.modifiers) {
        case (kVK_Escape, 0):
            recording = nil
        case (kVK_Delete, 0), (kVK_ForwardDelete, 0):
            bindings[action] = nil
            recording = nil
        default:
            guard combo.isAllowed else {
                hint = "Kısayolda ⌘, ⌥ ya da ⌃ tuşlarından en az biri olmalı."
                return
            }
            var updated = bindings
            // Aynı tuşlar başka bir işe atanmışsa ikisi yer değiştirir.
            if let other = HotKeyAction.allCases.first(where: { $0 != action && updated[$0] == combo }) {
                updated[other] = updated[action]
            }
            updated[action] = combo
            bindings = updated
            recording = nil
        }
    }
}
