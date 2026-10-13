import SwiftUI

// MARK: - Ekranda

struct NowTab: View {
    @Environment(TVController.self) private var tv
    @AppStorage("tab") private var tab: Tab = .now

    var body: some View {
        VStack(spacing: 10) {
            screen
            VolumeCard()

            Card(title: "Favori kanallar", icon: "star", trailing: {
                Button("Tümü") { tab = .channels }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }) {
                if tv.channels.favorites.isEmpty {
                    Text("Kanallar sekmesinde ★ ile işaretlediğin kanallar burada görünür.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    TimelineView(.everyMinute) { context in
                        let chips = HStack(spacing: 6) {
                            ForEach(tv.channels.favorites) { channel in
                                ChannelChip(channel: channel, date: context.date)
                            }
                        }
                        Group {
                            if RootView.scrolls {
                                ScrollView(.horizontal) { chips }
                                    .scrollIndicators(.never)
                                    // Kartın kenarına kadar kaysın.
                                    .contentMargins(.horizontal, 12, for: .scrollContent)
                            } else {
                                // Anlık görüntü modu: satır taşar ama kartı genişletmez.
                                Color.clear.frame(height: 74)
                                    .overlay(alignment: .leading) { chips.fixedSize().padding(.leading, 12) }
                            }
                        }
                        .padding(.horizontal, -12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .clipped()
                        // Sağdaki solma, satırın devam ettiğini belli eder.
                        .mask(
                            LinearGradient(stops: [.init(color: .black, location: 0.86), .init(color: .clear, location: 1)],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                    }
                }
            }

            Card("Uygulamalar", icon: "square.grid.2x2") {
                HStack(spacing: 0) {
                    ForEach(TVApp.all.prefix(4)) { app in AppTile(app: app, size: 38) }
                }
            }

            if !tv.reminders.upcoming.isEmpty {
                RemindersCard()
            }

            InputsCard()
        }
    }

    private var screen: some View {
        TimelineView(.everyMinute) { context in
            screen(at: context.date)
        }
    }

    /// Kanal açıksa yayın akışındaki şimdiki ve sıradaki program.
    private func schedule(at date: Date) -> (now: Programme?, next: Programme?) {
        guard tv.isOnline, tv.runningApp == nil, let channel = tv.currentChannel else { return (nil, nil) }
        return tv.epg.schedule(for: channel.name, at: date)
    }

    private func screen(at date: Date) -> some View {
        let programme = schedule(at: date)
        return VStack(spacing: 0) {
            RealisticTV(isOn: tv.isOnline) {
                screenContent(programme.now)
            }
            .padding(.horizontal, 6)

            HStack {
                SectionLabel(text: "● Şimdi ekranda", color: Theme.accent)
                Spacer()
                if tv.isOnline, let input = tv.currentInput { SectionLabel(text: input, color: Theme.accent) }
            }
            .padding(.top, 10)
            if let now = programme.now {
                ProgrammeSummary(channel: tv.currentChannel, now: now, next: programme.next, date: date)
                    .padding(.top, 4)
            } else {
                Text(subtitle)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder private func screenContent(_ programme: Programme?) -> some View {
        if !tv.isOnline {
            // Kapalı panel gerçekte simsiyahtır; yalnızca soluk bir ipucu.
            VStack(spacing: 6) {
                Image(systemName: "power").font(.system(size: 18))
                Text("TV kapalı").font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(Color.white.opacity(0.22))
        } else if let app = tv.runningApp {
            VStack(spacing: 8) {
                AppBadge(app: app, size: 46)
                Text(app.name).font(.system(size: 16, weight: .semibold))
            }
        } else if let channel = tv.currentChannel {
            VStack(spacing: 8) {
                ChannelLogo(name: channel.name, height: programme == nil ? 58 : 48)
                    .frame(maxWidth: 200)
                Text(programme?.title ?? "\(channel.number) · \(channel.name)")
                    .font(.system(size: programme == nil ? 12 : 15, weight: .semibold))
                    .foregroundStyle(programme == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .padding(.horizontal, 14)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 22))
                Text("Televizyon").font(.system(size: 13, weight: .semibold))
            }
        }
    }

    private var subtitle: String {
        if !tv.isOnline { return "Güç tuşuyla ağ üzerinden açmayı deneyebilirsin." }
        if let app = tv.runningApp { return "\(app.name) açık." }
        if let channel = tv.currentChannel { return "\(channel.number). kanal · \(channel.name)" }
        return "Senin TV'n. Senin salonun. Senin kumandan."
    }
}

/// Şimdiki program: saat aralığı, ilerleme ve sıradaki program.
struct ProgrammeSummary: View {
    @Environment(TVController.self) private var tv
    let channel: Channel?
    let now: Programme
    let next: Programme?
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(now.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 8)
                Text("\(clock(now.start))–\(clock(now.stop))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule().fill(Theme.key)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent).frame(width: proxy.size.width * now.progress(at: date))
                    }
            }
            .frame(height: 3)
            if let next {
                HStack(spacing: 6) {
                    Text("Sırada \(clock(next.start)) · \(next.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if let channel {
                        let isSet = tv.reminders.isSet(channel: channel, programme: next)
                        Button { tv.reminders.toggle(channel: channel, programme: next) } label: {
                            Image(systemName: isSet ? "bell.fill" : "bell")
                                .font(.system(size: 11))
                                .foregroundStyle(isSet ? Theme.accent : Color.secondary)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(isSet ? "Hatırlatıcıyı kaldır" : "Başlamadan 5 dk önce hatırlat")
                    }
                }
            }
        }
    }
}

/// Yaklaşan program hatırlatıcıları.
struct RemindersCard: View {
    @Environment(TVController.self) private var tv

    var body: some View {
        Card("Hatırlatıcılar", icon: "bell") {
            VStack(spacing: 6) {
                ForEach(tv.reminders.upcoming) { reminder in
                    HStack(spacing: 10) {
                        ChannelLogo(name: reminder.channelName, height: 16).frame(width: 40)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(reminder.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            Text("\(dayLabel(reminder.start)) \(clock(reminder.start)) · \(reminder.channelName)")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button { tv.reminders.remove(reminder) } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Hatırlatıcıyı kaldır")
                    }
                }
            }
        }
    }
}

struct VolumeCard: View {
    @Environment(TVController.self) private var tv
    @State private var syncing = false
    @State private var syncText = ""

    var body: some View {
        Card(title: "TV Sesi", icon: tv.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", trailing: {
            Text(tv.isMuted ? "Sessiz" : "\(tv.volume)")
                .font(.system(size: tv.isMuted ? 13 : 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.15), value: tv.volume)
        }) {
            HStack(spacing: 8) {
                Button { tv.press(.mute) } label: {
                    Image(systemName: tv.isMuted ? "speaker.slash.fill" : "speaker.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(tv.isMuted ? Theme.accent : .secondary)
                        .frame(width: 18)
                }
                .buttonStyle(.plain)
                .help(tv.isMuted ? "Sesi aç" : "Sessize al")

                VolumeSlider(value: tv.volume, dimmed: tv.isMuted) { tv.setVolume($0) }

                Image(systemName: "speaker.wave.3.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                if syncing {
                    TextField("TV'deki değer", text: $syncText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 96)
                        .onSubmit(applySync)
                    Button("Kaydet", action: applySync).font(.system(size: 11))
                } else {
                    Button("TV hoparlörü · Eşitle") { syncText = "\(tv.volume)"; syncing = true }
                        .buttonStyle(.plain)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .help("Uygulamadaki seviye TV ekranındakiyle farklıysa TV'de gördüğün değeri gir")
                }
                Spacer()
                stepper("minus", .volumeDown)
                stepper("plus", .volumeUp)
            }
        }
    }

    private func applySync() {
        if let level = Int(syncText) { tv.syncVolume(to: level) }
        syncing = false
    }

    private func stepper(_ symbol: String, _ key: RemoteKey) -> some View {
        KeyButton(action: { tv.press(key) }, repeats: true) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.key))
        }
    }
}

/// Örnekteki gibi kırmızı dolgulu, sürüklenebilir ses çubuğu.
private struct VolumeSlider: View {
    let value: Int
    var dimmed = false
    let onChange: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let x = width * CGFloat(value) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.key).frame(height: 5)
                Capsule().fill(dimmed ? Color.gray : Theme.accent).frame(width: max(5, x), height: 5)
                Circle()
                    .fill(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .frame(width: 16, height: 16)
                    .offset(x: min(max(0, x - 8), width - 16))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let level = Int((drag.location.x / max(width, 1) * 100).rounded())
                    let clamped = min(100, max(0, level))
                    if clamped != value { onChange(clamped) }
                }
            )
        }
        .frame(height: 20)
        .accessibilityElement()
        .accessibilityLabel("Ses seviyesi")
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { direction in
            onChange(value + (direction == .increment ? 1 : -1))
        }
    }
}

struct ChannelChip: View {
    @Environment(TVController.self) private var tv
    let channel: Channel
    let date: Date

    var body: some View {
        let isCurrent = tv.channels.lastChannelID == channel.id
        let programme = tv.epg.schedule(for: channel.name, at: date).now
        KeyButton(action: { tv.switchTo(channel) }, help: "\(channel.name) kanalına geç") {
            VStack(spacing: 3) {
                ChannelLogo(name: channel.name, height: 20)
                    .frame(maxWidth: 62)
                    .padding(.bottom, 2)
                Text(channel.name)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(programme?.title ?? "\(channel.number). kanal")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .frame(width: 80, height: 74)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isCurrent ? Theme.accent.opacity(0.22) : Theme.key)
            )
        }
    }
}

struct AppTile: View {
    @Environment(TVController.self) private var tv
    let app: TVApp
    var size: CGFloat = 44

    var body: some View {
        KeyButton(action: { tv.open(app) }, help: "\(app.name) aç") {
            VStack(spacing: 6) {
                AppBadge(app: app, size: size)
                    .overlay(alignment: .topTrailing) {
                        if tv.runningApp == app {
                            Circle().fill(.green).frame(width: 8, height: 8).offset(x: 3, y: -3)
                        }
                    }
                Text(app.name).font(.system(size: 10.5)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct InputsCard: View {
    @Environment(TVController.self) private var tv
    @AppStorage("inputsExpanded") private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if expanded {
                list.transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
        .clipped()
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "cable.connector").font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Girişler").font(.system(size: 12, weight: .semibold))
            if !expanded, tv.isOnline, let input = tv.currentInput {
                SectionLabel(text: input, color: Theme.accent).padding(.leading, 4)
            }
            Spacer()
            Button("Kaynak menüsü") { tv.press(.source) }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(expanded ? 0 : -90))
                .frame(width: 16)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.snappy(duration: 0.22)) { expanded.toggle() }
        }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(expanded ? "Girişleri gizle" : "Girişleri göster")
    }

    private var list: some View {
        VStack(spacing: 6) {
            ForEach(Array(tv.inputs.enumerated()), id: \.offset) { index, input in
                KeyButton(action: { tv.selectInput(index) }, help: "\(input) girişine geç") {
                    HStack(spacing: 10) {
                        Image(systemName: icon(for: input))
                            .font(.system(size: 13))
                            .frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.key))
                        Text(input).font(.system(size: 12.5, weight: .medium))
                        Spacer()
                        if tv.isOnline, tv.currentInput == input {
                            SectionLabel(text: "Ekranda", color: Theme.accent)
                        }
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9).fill(tv.currentInput == input ? Theme.accent.opacity(0.12) : .clear))
                }
            }
        }
    }

    private func icon(for input: String) -> String {
        let lower = input.lowercased()
        if lower.hasPrefix("hdmi") { return "cable.connector.horizontal" }
        if lower == "tv" { return "antenna.radiowaves.left.and.right" }
        if lower.contains("usb") { return "externaldrive" }
        return "rectangle.connected.to.line.below"
    }
}

// MARK: - Kumanda

struct RemoteTab: View {
    @Environment(TVController.self) private var tv

    var body: some View {
        VStack(spacing: 10) {
            Card("Kumanda", icon: "dot.circle.and.hand.point.up.left.fill") {
                HStack(spacing: 12) {
                    VStack(spacing: 14) {
                        round("house", "Ana ekran", .home)
                        round("arrow.uturn.backward", "Geri", .back)
                    }
                    DPad()
                    VStack(spacing: 14) {
                        round("gearshape", "Menü", .menu)
                        round("xmark", "Çıkış", .exit)
                    }
                }
                .frame(maxWidth: .infinity)
                HStack(spacing: 6) {
                    RemoteButton(symbol: "backward.fill") { tv.press(.rewind) }
                    RemoteButton(symbol: "play.fill") { tv.press(.play) }
                    RemoteButton(symbol: "pause.fill") { tv.press(.pause) }
                    RemoteButton(symbol: "stop.fill") { tv.press(.stop) }
                    RemoteButton(symbol: "forward.fill") { tv.press(.forward) }
                }
                .padding(.top, 4)
            }

            TouchpadCard()
            KeyboardCard()
            VolumeCard()

            Card("Kanal", icon: "list.number") {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        RemoteButton(symbol: "chevron.down", title: "Kanal −", repeats: true) { tv.press(.channelDown) }
                        RemoteButton(symbol: "chevron.up", title: "Kanal +", repeats: true) { tv.press(.channelUp) }
                    }
                    HStack(spacing: 6) {
                        RemoteButton(symbol: "arrow.left.arrow.right", title: "Önceki") { tv.send(code: 1034) }
                        RemoteButton(symbol: "list.bullet", title: "TV listesi") { tv.send(code: 1045) }
                    }
                }
            }

            Card("Sayılar", icon: "number") {
                Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                    ForEach(0..<3) { row in
                        GridRow { ForEach(1...3, id: \.self) { col in digit(row * 3 + col) } }
                    }
                    GridRow {
                        RemoteButton(symbol: "info.circle") { tv.press(.info) }
                        digit(0)
                        RemoteButton(symbol: "list.bullet.rectangle") { tv.press(.epg) }
                    }
                }
            }

            Card("Renkli tuşlar", icon: "circle.grid.2x2") {
                HStack(spacing: 6) {
                    ForEach([(RemoteKey.red, Color.red), (.green, .green), (.yellow, .yellow), (.blue, .blue)], id: \.0) { key, color in
                        KeyButton(action: { tv.press(key) }) {
                            Capsule().fill(color.gradient).frame(height: 7).padding(.horizontal, 10)
                                .frame(maxWidth: .infinity).frame(height: 26)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.key))
                        }
                    }
                }
            }
        }
    }

    private func round(_ symbol: String, _ help: String, _ key: RemoteKey) -> some View {
        KeyButton(action: { tv.press(key) }, help: help) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.key))
        }
    }

    private func digit(_ n: Int) -> some View {
        KeyButton(action: { tv.press(.digit(n)) }) {
            Text("\(n)").font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.key))
        }
    }
}

/// İmleç alanı: fare/trackpad alanın üzerinde gezdikçe TV imleci aynı yönde hareket eder; tıklama OK'dir.
private struct TouchpadCard: View {
    @Environment(TVController.self) private var tv
    @State private var lastLocation: CGPoint?
    @State private var hovering = false
    /// Telefon uygulaması ekran noktasını ~1,33 ile çarpıyor; Mac'te alan küçük olduğu için biraz daha hızlı.
    private let speed = 2.0

    var body: some View {
        Card(title: "Touchpad", icon: "cursorarrow.motionlines", trailing: {
            Text("Üzerinde gezdir · tıkla = OK").font(.system(size: 10)).foregroundStyle(.secondary)
        }) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(hovering ? Theme.accent.opacity(0.10) : Theme.key)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(hovering ? Theme.accent.opacity(0.5) : .clear))
                .overlay {
                    Image(systemName: "hand.point.up.left")
                        .font(.system(size: 22))
                        .foregroundStyle(.tertiary)
                        .opacity(hovering ? 0 : 1)
                }
                .frame(height: 120)
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location):
                        if let last = lastLocation {
                            tv.moveCursor(dx: (location.x - last.x) * speed, dy: (location.y - last.y) * speed)
                        }
                        lastLocation = location
                        hovering = true
                    case .ended:
                        lastLocation = nil
                        hovering = false
                    }
                }
                .onTapGesture { tv.press(.ok) }
                .accessibilityLabel("TV imleç alanı")
                .accessibilityAddTraits(.isButton)
            HStack(spacing: 8) {
                // Canlı yayında ve menülerde TV imleç göstermiyor; tarayıcıda gösteriyor (13.10.2026'da doğrulandı).
                Text("TV imleci yalnızca tarayıcı gibi web ekranlarında gösterir.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button("Tarayıcıyı aç") { tv.send(code: 1065) }
                    .controlSize(.small)
            }
        }
    }
}

/// Mac klavyesinden TV'deki etkin yazı alanına (ör. YouTube araması) metin gönderir.
private struct KeyboardCard: View {
    @Environment(TVController.self) private var tv
    @State private var text = ""

    var body: some View {
        Card("Klavye", icon: "keyboard") {
            HStack(spacing: 6) {
                TextField("TV'ye yazılacak metin", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button("Gönder", action: send)
                    .disabled(text.isEmpty)
            }
            Text("Önce TV'de bir yazı alanı açık olmalı, ör. YouTube veya Netflix araması.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func send() {
        guard !text.isEmpty else { return }
        tv.type(text)
        text = ""
    }
}

private struct DPad: View {
    @Environment(TVController.self) private var tv
    private let size: CGFloat = 150

    var body: some View {
        ZStack {
            Circle().fill(Theme.key)
            arrow("chevron.up", .up).offset(y: -size / 3)
            arrow("chevron.down", .down).offset(y: size / 3)
            arrow("chevron.left", .left).offset(x: -size / 3)
            arrow("chevron.right", .right).offset(x: size / 3)
            KeyButton(action: { tv.press(.ok) }, help: "OK") {
                Text("OK")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(Theme.accent.gradient))
            }
        }
        .frame(width: size, height: size)
    }

    private func arrow(_ symbol: String, _ key: RemoteKey) -> some View {
        KeyButton(action: { tv.press(key) }, repeats: true) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 42, height: 42)
                .contentShape(Rectangle())
        }
    }
}

// MARK: - Uygulamalar

struct AppsTab: View {
    var body: some View {
        VStack(spacing: 10) {
            YouTubeCard()
            Card("Uygulamalar", icon: "square.grid.2x2") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 14) {
                    ForEach(TVApp.all) { app in AppTile(app: app, size: 48) }
                }
                .padding(.vertical, 4)
            }
            Text("Netflix, Prime Video ve YouTube doğrudan açılır; hangisinin açık olduğu da izlenir ve Aktivite'ye yazılır.")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }
}

/// YouTube linkini TV'de oynatır; panodaki linki kendiliğinden önerir.
struct YouTubeCard: View {
    @Environment(TVController.self) private var tv
    @State private var link = ""
    @State private var info: YouTubeInfo?

    private var video: YouTubeVideo? { YouTubeVideo(link: link) }

    var body: some View {
        Card(title: "YouTube'da aç", icon: "play.rectangle.fill", trailing: {
            Button("Panodan") { link = NSPasteboard.general.string(forType: .string) ?? "" }
                .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
        }) {
            HStack(spacing: 6) {
                TextField("YouTube linki yapıştır", text: $link)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(play)
                Button("TV'de oynat", action: play)
                    .buttonStyle(.borderedProminent)
                    .disabled(video == nil)
            }
            if let info {
                HStack(spacing: 10) {
                    AsyncImage(url: info.thumbnail) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Theme.key
                    }
                    .frame(width: 96, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        Text(info.author).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            } else if !link.isEmpty, video == nil {
                Text("Bu bir YouTube linki değil.").font(.system(size: 10.5)).foregroundStyle(Theme.accent)
            }
            status
            Text("Linki panele sürükleyip bırakabilir ya da ⌘K aramasına yapıştırabilirsin.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task(id: video?.id) {
            info = nil
            if let video { info = await YouTubeCaster.info(for: video) }
        }
        .onAppear {
            if link.isEmpty, let text = NSPasteboard.general.string(forType: .string), YouTubeVideo(link: text) != nil {
                link = text
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch tv.youtube.status {
        case .idle:
            EmptyView()
        case .sending:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("TV'ye gönderiliyor…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .playing(_, let coldStart):
            HStack(spacing: 8) {
                Label("TV'de oynatılıyor", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11)).foregroundStyle(.green)
                Spacer()
                if coldStart {
                    // YouTube kapalıyken açıldıysa profil ekranı videonun önüne geçebilir.
                    Button("Başlamadıysa tekrar gönder") { tv.youtube.resend(on: tv.host) }
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
        case .failed(let message):
            Text("Gönderilemedi: \(message)").font(.system(size: 11)).foregroundStyle(Theme.accent)
        }
    }

    private func play() {
        guard let video else { return }
        tv.playYouTube(video)
    }
}

// MARK: - Aktivite

struct ActivityTab: View {
    @Environment(TVController.self) private var tv
    @State private var period = 1

    var body: some View {
        let totals = tv.activity.totals(lastDays: period)
        let total = totals[ActivityStore.total] ?? 0
        let ranked = totals.filter { $0.key != ActivityStore.total }.sorted { $0.value > $1.value }
        let channels = ranked.filter { $0.key.hasPrefix(ActivityStore.channelPrefix) }
        let apps = ranked.filter { !$0.key.hasPrefix(ActivityStore.channelPrefix) }

        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Aktivite")
            HStack(spacing: 6) {
                Text("Dönem").font(.system(size: 11)).foregroundStyle(.secondary)
                ForEach([(1, "Bugün"), (7, "7 gün"), (30, "30 gün")], id: \.0) { days, title in
                    Button(title) { period = days }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(period == days ? Theme.accent : Theme.key))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionLabel(text: "TV açık kalma süresi")
                Text(formatDuration(total))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.accent)
                Text("Bu Mac açıkken gözlemlenen süre.").font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.1)))

            Card("En çok izlenen kanallar", icon: "list.number") {
                if channels.isEmpty {
                    Text("Kanalları bu uygulamadan (Kanallar sekmesi, favoriler ya da Kanal +/−) değiştirdikçe hangi kanalda ne kadar kaldığın burada sıralanır.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(channels.enumerated()), id: \.element.key) { rank, item in
                    let number = ActivityStore.channelNumber(fromKey: item.key) ?? 0
                    let name = tv.channels.channels.first { $0.number == number }?.name ?? "\(number). kanal"
                    UsageRow(
                        title: name,
                        logo: name,
                        badge: "\(rank + 1)",
                        seconds: item.value,
                        maximum: channels.first?.value ?? 1
                    )
                }
            }

            if !apps.isEmpty {
                Card("Uygulamalar", icon: "square.grid.2x2") {
                    ForEach(apps, id: \.key) { item in
                        UsageRow(title: item.key, logo: nil, badge: nil, seconds: item.value, maximum: apps.first?.value ?? 1)
                    }
                }
            }
        }
    }
}

private struct UsageRow: View {
    let title: String
    /// Logo aranacak kanal adı (numarasız).
    let logo: String?
    let badge: String?
    let seconds: Double
    let maximum: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                if let badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Theme.key))
                }
                if let logo {
                    ChannelLogo(name: logo, height: 16).frame(width: 40)
                }
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Text(formatDuration(seconds)).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                Capsule().fill(Theme.key)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.accent)
                            .frame(width: proxy.size.width * min(1, seconds / max(maximum, 1)))
                    }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 3)
    }
}
