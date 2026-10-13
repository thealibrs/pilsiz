import SwiftUI

struct ChannelsTab: View {
    @Environment(TVController.self) private var tv
    @State private var search = ""
    @State private var editing: Channel?
    @State private var scanning = false
    @State private var expandedSchedule: UUID?

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextField("Kanal ara", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                }
                .padding(.horizontal, 9)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.key))

                iconButton("plus", "Kanal ekle") {
                    editing = Channel(number: tv.channels.nextFreeNumber, name: "")
                    scanning = false
                }
                iconButton("wand.and.stars", "Kanal tarama sihirbazı") {
                    editing = nil
                    scanning = true
                }
            }

            if scanning {
                ScanWizard { scanning = false }
            }
            if let channel = editing {
                ChannelEditor(channel: channel) { editing = nil }
                    .id(channel.id)
            }

            if tv.channels.channels.isEmpty, !scanning, editing == nil {
                emptyState
            } else {
                TimelineView(.everyMinute) { context in
                    VStack(spacing: 4) {
                        ForEach(filtered) { channel in
                            row(channel, at: context.date)
                            if expandedSchedule == channel.id {
                                ScheduleList(channel: channel, date: context.date)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                }
            }
        }
    }

    private var filtered: [Channel] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return tv.channels.channels }
        return tv.channels.channels.filter {
            $0.name.localizedStandardContains(query) || String($0.number).hasPrefix(query)
        }
    }

    private func row(_ channel: Channel, at date: Date) -> some View {
        let isCurrent = tv.channels.lastChannelID == channel.id
        let programme = tv.epg.schedule(for: channel.name, at: date).now
        return HStack(spacing: 10) {
            Text("\(channel.number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .frame(width: 26, height: 26)
                .background(Circle().fill(isCurrent ? Theme.accent : Theme.key))
            ChannelLogo(name: channel.name, height: 20)
                .frame(width: 58, height: 30)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.35)))
            VStack(alignment: .leading, spacing: 1) {
                Text(channel.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                if let programme {
                    Text(programme.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isCurrent, tv.isOnline { SectionLabel(text: "Ekranda", color: Theme.accent) }
            if programme != nil {
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        expandedSchedule = expandedSchedule == channel.id ? nil : channel.id
                    }
                } label: {
                    Image(systemName: hasReminder(channel) ? "bell.badge.fill" : "calendar.badge.clock")
                        .font(.system(size: 11))
                        .foregroundStyle(expandedSchedule == channel.id || hasReminder(channel) ? Theme.accent : Color.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Yayın akışı ve hatırlatıcılar")
            }
            Button { tv.channels.toggleFavorite(channel) } label: {
                Image(systemName: channel.favorite ? "star.fill" : "star")
                    .font(.system(size: 11))
                    .foregroundStyle(channel.favorite ? Color.yellow : Color.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(channel.favorite ? "Favorilerden çıkar" : "Favorilere ekle")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 9).fill(isCurrent ? Theme.accent.opacity(0.12) : Theme.card))
        .contentShape(Rectangle())
        .onTapGesture { tv.switchTo(channel) }
        .contextMenu {
            Button("Kanala geç") { tv.switchTo(channel) }
            Button("Düzenle") { scanning = false; editing = channel }
            Button(channel.favorite ? "Favorilerden çıkar" : "Favorilere ekle") { tv.channels.toggleFavorite(channel) }
            Divider()
            Button("Sil", role: .destructive) { tv.channels.delete(channel) }
        }
        .help("Tıkla: kanala geç · Sağ tık: düzenle")
    }

    private func hasReminder(_ channel: Channel) -> Bool {
        tv.reminders.upcoming.contains { $0.channelNumber == channel.number }
    }

    private var emptyState: some View {
        Card("Kanal listen boş", icon: "list.number") {
            VStack(alignment: .leading, spacing: 10) {
                Text("TV kanal adlarını ağ üzerinden vermiyor. Listeyi bir kez oluşturman yeterli; sonra tek tıkla kanala geçersin.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("En hızlısı sihirbaz: TV'yi sırayla 1, 2, 3… kanallara götürür, sen de ekranda gördüğün adı yazarsın.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Sihirbazı başlat") { scanning = true }.buttonStyle(.borderedProminent)
                    Button("Elle ekle") { editing = Channel(number: 1, name: "") }
                }
            }
        }
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.key))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// Tek bir kanalı ekleme/düzenleme formu.
private struct ChannelEditor: View {
    @Environment(TVController.self) private var tv
    @State var channel: Channel
    let done: () -> Void
    @FocusState private var nameFocused: Bool

    var body: some View {
        Card(tv.channels.channels.contains { $0.id == channel.id } ? "Kanalı düzenle" : "Yeni kanal", icon: "pencil") {
            HStack(spacing: 6) {
                TextField("No", value: $channel.number, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 54)
                TextField("Kanal adı", text: $channel.name)
                    .textFieldStyle(.roundedBorder)
                    .focused($nameFocused)
                    .onSubmit(save)
            }
            HStack {
                Button("İptal", action: done)
                Spacer()
                Button("Kaydet", action: save)
                    .buttonStyle(.borderedProminent)
                    .disabled(channel.name.trimmingCharacters(in: .whitespaces).isEmpty || channel.number < 1)
            }
        }
        .onAppear { nameFocused = true }
    }

    private func save() {
        channel.name = channel.name.trimmingCharacters(in: .whitespaces)
        guard !channel.name.isEmpty, channel.number > 0 else { return }
        tv.channels.upsert(channel)
        done()
    }
}

/// TV'yi sırayla kanallara götürüp kullanıcının gördüğü adı kaydeder.
private struct ScanWizard: View {
    @Environment(TVController.self) private var tv
    let done: () -> Void
    @State private var number = 1
    @State private var name = ""
    @State private var started = false
    @FocusState private var focused: Bool

    var body: some View {
        Card("Kanal tarama sihirbazı", icon: "wand.and.stars") {
            if !started {
                HStack(spacing: 6) {
                    Text("Başlangıç kanalı").font(.system(size: 11.5)).foregroundStyle(.secondary)
                    TextField("", value: $number, format: .number).textFieldStyle(.roundedBorder).frame(width: 54)
                    Spacer()
                    Button("Başlat") { started = true; go(to: number) }.buttonStyle(.borderedProminent)
                }
                Text("TV açık ve TV (anten/uydu) kaynağında olmalı.").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Button("Kapat", action: done).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text("TV'de **\(number). kanal** açıldı. Ekranda gördüğün kanal adını yaz ve Enter'a bas.")
                    .font(.system(size: 11.5))
                    .fixedSize(horizontal: false, vertical: true)
                TextField("ör. TRT 1", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(saveAndNext)
                HStack(spacing: 6) {
                    Button("Bitir", action: done)
                    Spacer()
                    Button("Tekrar") { go(to: number) }.help("Kanal numarasını yeniden gönder")
                    Button("Atla") { go(to: number + 1) }
                    Button("Kaydet ve sonraki", action: saveAndNext).buttonStyle(.borderedProminent)
                }
                .font(.system(size: 11))
            }
        }
        .onAppear { number = max(1, tv.channels.nextFreeNumber) }
    }

    private func go(to n: Int) {
        number = n
        name = tv.channels.channels.first { $0.number == n }?.name ?? ""
        tv.tune(n)
        focused = true
    }

    private func saveAndNext() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { tv.channels.upsert(Channel(number: number, name: trimmed)) }
        go(to: number + 1)
    }
}

/// Bir kanalın sıradaki programları; her birine hatırlatıcı kurulabilir.
private struct ScheduleList: View {
    @Environment(TVController.self) private var tv
    let channel: Channel
    let date: Date

    var body: some View {
        let programmes = tv.epg.upcoming(for: channel.name, from: date)
        VStack(alignment: .leading, spacing: 2) {
            ForEach(programmes, id: \.start) { programme in
                let isSet = tv.reminders.isSet(channel: channel, programme: programme)
                HStack(spacing: 10) {
                    Text(dayPrefix(programme.start) + clock(programme.start))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)
                    Text(programme.title).font(.system(size: 11.5)).lineLimit(1)
                    Spacer()
                    Button { tv.reminders.toggle(channel: channel, programme: programme) } label: {
                        Image(systemName: isSet ? "bell.fill" : "bell")
                            .font(.system(size: 11))
                            .foregroundStyle(isSet ? Theme.accent : Color.secondary)
                            .frame(width: 22, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isSet ? "Hatırlatıcıyı kaldır" : "Başlamadan 5 dk önce hatırlat")
                }
                .padding(.vertical, 3)
            }
            if tv.reminders.permissionDenied {
                Text("Bildirim izni yok: Sistem Ayarları › Bildirimler › TV Kumanda")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.leading, 44)
        .padding(.trailing, 8)
        .padding(.vertical, 4)
    }

    private func dayPrefix(_ start: Date) -> String {
        Calendar.current.isDateInToday(start) ? "" : dayLabel(start) + " "
    }
}
