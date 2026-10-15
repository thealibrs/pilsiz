import SwiftUI

/// Kanallar: liste (program adı önde, "rehber") ya da ızgara (logo duvarı) görünümü.
/// Ekrandaki kanal listenin üstünde sabit durur; ızgarada fareyle üstüne gelinen kanalın programı altta görünür.
struct ChannelsTab: View {
    enum Layout: String { case list, grid }
    enum Filter: String { case favorites, frequent, all }

    @Environment(TVController.self) private var tv
    @AppStorage("channelsLayout") private var layout = Layout.list
    @AppStorage("channelsFilter") private var filter = Filter.all
    @State private var search = ""
    @State private var editing: Channel?
    @State private var scanning = false
    @State private var expandedSchedule: UUID?
    @State private var hovered: UUID?

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            syncStatus

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
                if search.isEmpty { filters }
                TimelineView(.everyMinute) { context in
                    // 400'ü aşkın kanal olabildiği için satırlar görünür oldukça oluşturulur.
                    LazyVStack(spacing: 6, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                        if layout == .list {
                            Section {
                                listRows(at: context.date)
                            } header: {
                                onAirCard(at: context.date)
                            }
                        } else {
                            Section {
                                grid(at: context.date)
                            } header: {
                                onAirCard(at: context.date)
                            } footer: {
                                peek(at: context.date)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Araç çubuğu ve filtreler

    private var toolbar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
                TextField("Kanal, numara ya da program", text: $search).textFieldStyle(.plain).font(.system(size: 12))
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.key))

            HStack(spacing: 2) {
                layoutButton(.list, symbol: "list.bullet", help: "Liste")
                layoutButton(.grid, symbol: "square.grid.2x2", help: "Izgara")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.key))

            Menu {
                Button("Kanal ekle", systemImage: "plus") {
                    editing = Channel(number: tv.channels.nextFreeNumber, name: "")
                    scanning = false
                }
                Button("Kanal tarama sihirbazı", systemImage: "wand.and.stars") {
                    editing = nil
                    scanning = true
                }
                Divider()
                Button("Kanal listesini TV'den eşitle", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await tv.syncChannels() }
                }
                .disabled(tv.channelSync == .syncing)
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(.secondary)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.key))
            .help("Kanal ekle, sihirbaz, TV'den eşitle")
        }
    }

    private func layoutButton(_ value: Layout, symbol: String, help: String) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { layout = value } } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(layout == value ? .primary : .tertiary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(layout == value ? Color.white.opacity(0.14) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var filters: some View {
        HStack(spacing: 6) {
            chip(.favorites, "★ Favoriler", count: tv.channels.favorites.count)
            chip(.frequent, "Sık izlenen", count: nil)
            chip(.all, "Tümü", count: tv.channels.channels.count)
            Spacer()
        }
    }

    private func chip(_ value: Filter, _ title: String, count: Int?) -> some View {
        Button { withAnimation(.snappy(duration: 0.2)) { filter = value } } label: {
            HStack(spacing: 4) {
                Text(title)
                if let count { Text("\(count)").opacity(0.55) }
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(filter == value ? Color.black : .secondary)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(Capsule().fill(filter == value ? Color.white.opacity(0.92) : Theme.key))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hangi kanallar

    /// Arama varsa tüm kanallarda ad, numara ve şimdiki program adına göre; yoksa seçili filtreye göre.
    private func shown(at date: Date) -> [Channel] {
        let all = tv.channels.channels
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            return all.filter {
                $0.name.localizedStandardContains(query) || String($0.number).hasPrefix(query)
                    || tv.epg.schedule(for: $0.name, at: date).now?.title.localizedStandardContains(query) == true
            }
        }
        let list: [Channel] = switch filter {
        case .favorites: tv.channels.favorites
        case .frequent: frequent
        case .all: all
        }
        // Anlık görüntü modunda yüzlerce satır tek resme sığmaz.
        return RootView.scrolls ? list : Array(list.prefix(layout == .grid ? 24 : 12))
    }

    /// Son 30 günde en uzun izlenen kanallar.
    private var frequent: [Channel] {
        let totals = tv.activity.totals(lastDays: 30)
        let numbers = totals
            .compactMap { key, seconds in ActivityStore.channelNumber(fromKey: key).map { ($0, seconds) } }
            .sorted { $0.1 > $1.1 }
            .prefix(24)
            .map(\.0)
        return numbers.compactMap { number in tv.channels.channels.first { $0.number == number } }
    }

    private var currentChannel: Channel? {
        guard tv.isOnline, tv.runningApp == nil else { return nil }
        return tv.currentChannel
    }

    private func isCurrent(_ channel: Channel) -> Bool { currentChannel?.id == channel.id }

    // MARK: - Ekrandaki kanal

    @ViewBuilder private func onAirCard(at date: Date) -> some View {
        if let channel = currentChannel {
            let schedule = tv.epg.schedule(for: channel.name, at: date)
            let programme = schedule.now
            HStack(spacing: 10) {
                LogoBox(name: channel.name, width: 54, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("EKRANDA")
                            .font(.system(size: 9, weight: .heavy))
                            .tracking(0.6)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Theme.accent))
                        Text(programme.map { "P \(channel.number) · \(timeRange($0))" } ?? "P \(channel.number)")
                            .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text(programme?.title ?? channel.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if let programme {
                        ProgressLine(value: programme.progress(at: date), highlighted: true).padding(.top, 2)
                        Text(onAirDetail(programme, next: schedule.next, at: date))
                            .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: expandedSchedule == channel.id ? "chevron.up" : "calendar.badge.clock")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.background)
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.card))
                    .overlay(RadialGradient(colors: [Theme.accent.opacity(0.22), .clear], center: .topTrailing, startRadius: 0, endRadius: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous)))
            )
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Theme.accent.opacity(0.35)))
            .contentShape(Rectangle())
            .onTapGesture { toggleSchedule(channel) }
            .help("Yayın akışı ve hatırlatıcılar")
            .padding(.bottom, 2)
        }
    }

    // MARK: - Liste

    @ViewBuilder private func listRows(at date: Date) -> some View {
        let all = shown(at: date)
        // Ekrandaki kanal üstteki sabit kartta duruyor; listede ikinci kez gösterilmez.
        let channels = all.filter { !isCurrent($0) }
        if all.isEmpty {
            emptyFilter
        }
        if let current = currentChannel, expandedSchedule == current.id {
            ScheduleList(channel: current, date: date)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }
        ForEach(channels) { channel in
            row(channel, at: date)
            if expandedSchedule == channel.id {
                ScheduleList(channel: channel, date: date)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func row(_ channel: Channel, at date: Date) -> some View {
        let current = isCurrent(channel)
        let programme = tv.epg.schedule(for: channel.name, at: date).now
        let isHovered = hovered == channel.id
        return HStack(spacing: 10) {
            LogoBox(name: channel.name, width: 58, height: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(programme?.title ?? channel.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(meta(channel, programme, at: date))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if let programme {
                    ProgressLine(value: programme.progress(at: date), highlighted: current).padding(.top, 3)
                }
            }
            Spacer(minLength: 4)
            if isHovered {
                if programme != nil {
                    rowButton(hasReminder(channel) ? "bell.badge.fill" : "calendar.badge.clock",
                              tint: expandedSchedule == channel.id || hasReminder(channel) ? Theme.accent : .primary,
                              help: "Yayın akışı ve hatırlatıcılar") { toggleSchedule(channel) }
                }
                rowButton(channel.favorite ? "star.fill" : "star", tint: channel.favorite ? .yellow : .primary,
                          help: channel.favorite ? "Favorilerden çıkar" : "Favorilere ekle") {
                    tv.channels.toggleFavorite(channel)
                }
            } else {
                // Fare üstünde değilken yalnızca durum simgeleri: gürültü azalsın.
                if hasReminder(channel) {
                    Image(systemName: "bell.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                }
                if channel.favorite {
                    Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow)
                }
            }
        }
        .frame(minHeight: 34)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(current ? Theme.accent.opacity(0.13) : isHovered ? Color.white.opacity(0.09) : Theme.card))
        .contentShape(Rectangle())
        .onHover { inside in hovered = inside ? channel.id : (hovered == channel.id ? nil : hovered) }
        .onTapGesture { tv.switchTo(channel) }
        .contextMenu { menu(channel) }
        .help("Tıkla: kanala geç · Sağ tık: düzenle")
    }

    private func meta(_ channel: Channel, _ programme: Programme?, at date: Date) -> String {
        var parts = ["\(channel.number)"]
        if programme != nil { parts.append(channel.name) }
        if let programme { parts.append("\(formatDuration(programme.stop.timeIntervalSince(date))) kaldı") }
        return parts.joined(separator: " · ")
    }

    private func rowButton(_ symbol: String, tint: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Theme.key))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Izgara

    @ViewBuilder private func grid(at date: Date) -> some View {
        let channels = shown(at: date)
        let showFavorites = search.isEmpty && filter == .all && !tv.channels.favorites.isEmpty
        if channels.isEmpty {
            emptyFilter
        }
        if showFavorites {
            gridSection("Favoriler", count: tv.channels.favorites.count, channels: tv.channels.favorites)
            gridSection("Tüm kanallar", count: tv.channels.channels.count, channels: channels)
        } else if !channels.isEmpty {
            gridSection(nil, count: channels.count, channels: channels)
        }
    }

    private func gridSection(_ title: String?, count: Int, channels: [Channel]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title {
                HStack {
                    SectionLabel(text: title)
                    Spacer()
                    Text("\(count)").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
                .padding(.top, 4)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
                ForEach(channels) { channel in tile(channel) }
            }
        }
    }

    private func tile(_ channel: Channel) -> some View {
        let current = isCurrent(channel)
        let isHovered = hovered == channel.id
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return LogoBox(name: channel.name, width: nil, height: 30, plain: true)
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(shape.fill(isHovered ? Color.white.opacity(0.09) : Color.black.opacity(0.35)))
            .overlay(shape.stroke(current ? Theme.accent : isHovered ? Color.white.opacity(0.2) : Theme.cardStroke,
                                  lineWidth: current ? 1.5 : 1))
            .overlay(alignment: .topLeading) {
                Text("\(channel.number)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(current ? Theme.accent : .secondary)
                    .padding(.leading, 6)
                    .padding(.top, 4)
            }
            .overlay(alignment: .topTrailing) {
                if channel.favorite {
                    Image(systemName: "star.fill").font(.system(size: 8)).foregroundStyle(.yellow).padding(5)
                }
            }
            .overlay(alignment: .bottom) {
                if current { Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 10).padding(.bottom, 4) }
            }
            .contentShape(shape)
            .onHover { inside in hovered = inside ? channel.id : (hovered == channel.id ? nil : hovered) }
            .onTapGesture { tv.switchTo(channel) }
            .contextMenu { menu(channel) }
            .help(channel.name)
    }

    /// Izgaranın altında sabit duran şerit: fareyle üstüne gelinen (yoksa ekrandaki) kanalda ne var.
    @ViewBuilder private func peek(at date: Date) -> some View {
        let channel = hovered.flatMap { id in tv.channels.channels.first { $0.id == id } } ?? currentChannel
        if let channel {
            let schedule = tv.epg.schedule(for: channel.name, at: date)
            HStack(spacing: 10) {
                LogoBox(name: channel.name, width: 52, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.now?.title ?? channel.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    Text(peekDetail(channel, schedule))
                        .font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                    if let now = schedule.now {
                        ProgressLine(value: now.progress(at: date), highlighted: isCurrent(channel)).padding(.top, 2)
                    }
                }
                Spacer(minLength: 4)
                if !isCurrent(channel) {
                    Button("Geç") { tv.switchTo(channel) }
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.background)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: -4)
            )
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(.white.opacity(0.12)))
            .padding(.top, 4)
        }
    }

    private func peekDetail(_ channel: Channel, _ schedule: (now: Programme?, next: Programme?)) -> String {
        var parts = ["P \(channel.number)"]
        if let now = schedule.now { parts.append(timeRange(now)) } else { parts.append(channel.name) }
        if let next = schedule.next { parts.append("sırada \(next.start.formatted(date: .omitted, time: .shortened))") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Ortak

    @ViewBuilder private func menu(_ channel: Channel) -> some View {
        Button("Kanala geç") { tv.switchTo(channel) }
        Button("Yayın akışı") { layout = .list; toggleSchedule(channel) }
        Button("Düzenle") { scanning = false; editing = channel }
        Button(channel.favorite ? "Favorilerden çıkar" : "Favorilere ekle") { tv.channels.toggleFavorite(channel) }
        Divider()
        Button("Sil", role: .destructive) { tv.channels.delete(channel) }
    }

    /// "1 sa 54 dk kaldı · sırada 13:15 Haberler"
    private func onAirDetail(_ programme: Programme, next: Programme?, at date: Date) -> String {
        var text = "\(formatDuration(programme.stop.timeIntervalSince(date))) kaldı"
        if let next { text += " · sırada \(next.start.formatted(date: .omitted, time: .shortened)) \(next.title)" }
        return text
    }

    private func toggleSchedule(_ channel: Channel) {
        withAnimation(.snappy(duration: 0.2)) {
            expandedSchedule = expandedSchedule == channel.id ? nil : channel.id
        }
    }

    private func timeRange(_ programme: Programme) -> String {
        "\(programme.start.formatted(date: .omitted, time: .shortened))–\(programme.stop.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder private var emptyFilter: some View {
        Text(!search.isEmpty ? "“\(search)” ile eşleşen kanal yok."
             : filter == .favorites ? "Henüz favori kanal yok. Bir kanalın üstüne gelip ☆'a bas."
             : "Pilsiz'den kanal değiştirdikçe en çok izlediğin kanallar burada sıralanır.")
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
    }

    @ViewBuilder private var syncStatus: some View {
        switch tv.channelSync {
        case .idle:
            EmptyView()
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Kanal listesi TV'den alınıyor…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .done(let added, let total):
            Text(added == 0 ? "TV'deki \(total) kanalın hepsi listede." : "TV'den \(added) yeni kanal eklendi (TV'de toplam \(total)).")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed(let message):
            Text("Kanal listesi alınamadı: \(message)")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func hasReminder(_ channel: Channel) -> Bool {
        tv.reminders.upcoming.contains { $0.channelNumber == channel.number }
    }

    private var emptyState: some View {
        Card("Kanal listen boş", icon: "list.number") {
            VStack(alignment: .leading, spacing: 10) {
                Text("TV açıkken kanal listesini tek tıkla TV'nin kendisinden alabilirsin.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("TV'den al") { Task { await tv.syncChannels() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(!tv.isOnline || tv.channelSync == .syncing)
                    Button("Sihirbaz") { scanning = true }
                    Button("Elle ekle") { editing = Channel(number: 1, name: "") }
                }
            }
        }
    }
}

/// Kanal logosu koyu bir kutuda; logo yoksa baş harfli rozet.
private struct LogoBox: View {
    let name: String
    var width: CGFloat?
    var height: CGFloat
    /// Izgarada kutu kartın kendisi olduğu için arka plansız.
    var plain = false

    var body: some View {
        Group {
            if let image = LogoCatalog.image(for: name) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                ChannelLogo(name: name, height: min(height * 0.62, 22))
            }
        }
        .padding(plain ? 0 : 4)
        .frame(width: width, height: height)
        .frame(maxWidth: width == nil ? .infinity : nil)
        .background(plain ? nil : RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.35)))
    }
}

/// Programın ince ilerleme çizgisi; ekrandaki kanalda kırmızı.
private struct ProgressLine: View {
    let value: Double
    var highlighted = false

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Theme.key)
                .overlay(alignment: .leading) {
                    Capsule().fill(highlighted ? Theme.accent : Color.white.opacity(0.45))
                        .frame(width: proxy.size.width * value)
                }
        }
        .frame(height: 3)
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
                Text("Bildirim izni yok: Sistem Ayarları › Bildirimler › Pilsiz")
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
