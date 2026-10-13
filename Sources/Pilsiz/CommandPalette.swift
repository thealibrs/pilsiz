import Observation
import SwiftUI

/// Panelin anlık arayüz durumu; menü çubuğu kısayolları da buradan paneli yönlendirir.
@MainActor
@Observable
final class PanelState {
    var paletteOpen = false
}

/// ⌘K hızlı arama: kanal adı, numarası ya da yayındaki programa göre kanala geçiş.
struct CommandPalette: View {
    @Environment(TVController.self) private var tv
    @Environment(PanelState.self) private var panel
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private struct Result: Identifiable {
        let channel: Channel
        let programme: Programme?
        var id: UUID { channel.id }
    }

    var body: some View {
        let youtube = YouTubeVideo(link: query)
        let results = youtube == nil ? search(at: Date()) : []
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Kanal, numara ya da program ara", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit {
                        if let youtube { playYouTube(youtube) } else { choose(results) }
                    }
                    .onKeyPress(.downArrow) { move(1, in: results); return .handled }
                    .onKeyPress(.upArrow) { move(-1, in: results); return .handled }
                    .onExitCommand { close() }
                Button { close() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Kapat (Esc)")
            }
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.key))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.accent.opacity(0.5)))

            if let youtube {
                HStack(spacing: 10) {
                    Image(systemName: "play.rectangle.fill").font(.system(size: 18)).foregroundStyle(.red)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("TV'de YouTube'da oynat").font(.system(size: 12.5, weight: .medium))
                        Text(youtube.id).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.18)))
                .contentShape(Rectangle())
                .onTapGesture { playYouTube(youtube) }
            } else if results.isEmpty {
                Text(query.isEmpty ? "Yazmaya başla: “trt”, “15”, “haber”…" : "Sonuç yok")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            VStack(spacing: 3) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    row(result, selected: index == selection)
                        .onTapGesture { tv.switchTo(result.channel); close() }
                }
            }
            if !results.isEmpty {
                Text("↑↓ seç · ↩ kanala geç · esc kapat")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear { focused = true }
        .onChange(of: query) { selection = 0 }
    }

    private func row(_ result: Result, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Text("\(result.channel.number)")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            ChannelLogo(name: result.channel.name, height: 18).frame(width: 50, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(result.channel.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                if let programme = result.programme {
                    Text(programme.title).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if selected {
                Image(systemName: "return").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(selected ? Theme.accent.opacity(0.18) : .clear))
        .contentShape(Rectangle())
    }

    /// Numara tam eşleşmesi önce, sonra kanal adı, sonra yayındaki program adı.
    private func search(at date: Date) -> [Result] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        let key = NameKey.key(text)
        var scored: [(score: Int, result: Result)] = []
        for channel in tv.channels.channels {
            let programme = tv.epg.schedule(for: channel.name, at: date).now
            let nameKey = NameKey.key(channel.name)
            let score: Int
            if Int(text) == channel.number { score = 0 }
            else if nameKey.hasPrefix(key) { score = 1 }
            else if nameKey.contains(key) { score = 2 }
            else if let programme, NameKey.key(programme.title).contains(key) { score = 3 }
            else if String(channel.number).hasPrefix(text) { score = 4 }
            else { continue }
            scored.append((score, Result(channel: channel, programme: programme)))
        }
        return scored
            .sorted { ($0.score, $0.result.channel.number) < ($1.score, $1.result.channel.number) }
            .prefix(8)
            .map(\.result)
    }

    private func move(_ step: Int, in results: [Result]) {
        guard !results.isEmpty else { return }
        selection = (selection + step + results.count) % results.count
    }

    private func playYouTube(_ video: YouTubeVideo) {
        tv.playYouTube(video)
        close()
    }

    private func choose(_ results: [Result]) {
        guard results.indices.contains(selection) else { return }
        tv.switchTo(results[selection].channel)
        close()
    }

    private func close() {
        query = ""
        panel.paletteOpen = false
    }
}
