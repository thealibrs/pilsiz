import AppKit
import SwiftUI

// MARK: - Uygulamalar

/// Üstte TV'de o an açık olan (uygulama ya da kanal), altında yayın uygulamaları,
/// diğer uygulamalar ve YouTube linki.
struct AppsTab: View {
    var body: some View {
        VStack(spacing: 10) {
            NowOnTVCard()
            StreamingShelf()
            OtherAppsRow()
            YouTubeCard()
        }
    }
}

/// Uygulama marka renkleri.
private enum Brand {
    static let netflix = Color(red: 0.90, green: 0.04, blue: 0.08)
    static let prime = Color(red: 0.10, green: 0.65, blue: 0.93)
    static let youtube = Color(red: 1.0, green: 0.0, blue: 0.2)

    static func tint(_ app: TVApp) -> Color {
        switch app.id {
        case "netflix": netflix
        case "prime": prime
        case "youtube": youtube
        default: Theme.accent
        }
    }
}

// MARK: - Şimdi TV'de

private struct NowOnTVCard: View {
    @Environment(TVController.self) private var tv

    var body: some View {
        TimelineView(.everyMinute) { context in
            content(at: context.date)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(background)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(stroke))
                .animation(.easeInOut(duration: 0.25), value: tv.runningApp)
        }
    }

    private var tint: Color? { tv.isOnline ? tv.runningApp.map(Brand.tint) : nil }

    private var background: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Theme.card)
            .overlay(
                RadialGradient(colors: [(tint ?? Theme.accent).opacity(tint == nil ? 0.10 : 0.30), .clear],
                               center: .topTrailing, startRadius: 0, endRadius: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            )
    }

    private var stroke: Color { tint?.opacity(0.35) ?? Theme.cardStroke }

    @ViewBuilder private func content(at date: Date) -> some View {
        if !tv.isOnline {
            off
        } else if let app = tv.runningApp {
            running(app, at: date)
        } else if let channel = tv.currentChannel {
            live(channel, at: date)
        } else {
            header(kicker: "Şimdi TV'de", title: tv.currentInput ?? "Canlı yayın", subtitle: nil) {
                iconTile("antenna.radiowaves.left.and.right")
            }
        }
    }

    private var off: some View {
        let waking = tv.status == .waking
        return header(
            kicker: waking ? "TV açılıyor" : "TV kapalı",
            title: waking ? "Uyandırılıyor…" : "Bir uygulamaya bas",
            subtitle: waking ? "Açılması birkaç saniye sürebilir." : "TV önce uyanır, sonra uygulama açılır."
        ) {
            iconTile("power").symbolEffect(.pulse, isActive: waking)
        }
    }

    private func running(_ app: TVApp, at date: Date) -> some View {
        VStack(spacing: 10) {
            header(kicker: "Şimdi TV'de", title: app.name, subtitle: openFor(at: date), live: true) {
                AppBadge(app: app, size: 44)
            }
            HStack(spacing: 8) {
                action("\(app.name) ana ekranı", symbol: "house", help: "Uygulamayı kapatıp kendi ana ekranından yeniden açar") {
                    tv.restart(app)
                }
                action("Canlı yayına dön", symbol: "tv", help: "Uygulamayı kapatır") { tv.close(app) }
            }
        }
    }

    private func live(_ channel: Channel, at date: Date) -> some View {
        let schedule = tv.epg.schedule(for: channel.name, at: date)
        return VStack(spacing: 10) {
            if let now = schedule.now {
                header(kicker: "Şimdi TV'de · P \(channel.number)", title: now.title, subtitle: channel.name) {
                    logo(channel)
                }
                VStack(spacing: 5) {
                    ProgressBar(value: now.progress(at: date))
                    HStack {
                        Text(timeRange(now))
                        Spacer()
                        Text("\(formatDuration(now.stop.timeIntervalSince(date))) kaldı")
                    }
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            } else {
                header(kicker: "Şimdi TV'de · P \(channel.number)", title: channel.name, subtitle: "Canlı yayın") { logo(channel) }
            }
        }
    }

    // MARK: Parçalar

    private func header(kicker: String, title: String, subtitle: String?, live: Bool = false,
                        @ViewBuilder leading: () -> some View) -> some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: kicker)
                Text(title).font(.system(size: 15, weight: .bold)).lineLimit(1)
                if let subtitle {
                    HStack(spacing: 5) {
                        if live { Circle().fill(.green).frame(width: 6, height: 6) }
                        Text(subtitle).lineLimit(1)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func iconTile(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.key))
    }

    @ViewBuilder private func logo(_ channel: Channel) -> some View {
        Group {
            if let image = LogoCatalog.image(for: channel.name) {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit().padding(5)
            } else {
                ChannelLogo(name: channel.name, height: 24)
            }
        }
        .frame(width: 44, height: 44)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.key))
    }

    private func action(_ title: String, symbol: String, help: String, perform: @escaping () -> Void) -> some View {
        KeyButton(action: perform, help: help) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.key))
        }
    }

    /// "47 dk'dır açık"; Pilsiz uygulamanın ne zaman açıldığını görmediyse yalnızca "TV'de açık".
    private func openFor(at date: Date) -> String {
        guard let since = tv.runningAppSince else { return "TV'de açık" }
        let elapsed = date.timeIntervalSince(since)
        return elapsed < 60 ? "Az önce açıldı" : "\(formatDuration(elapsed))'dır açık"
    }

    private func timeRange(_ programme: Programme) -> String {
        "\(programme.start.formatted(date: .omitted, time: .shortened))–\(programme.stop.formatted(date: .omitted, time: .shortened))"
    }
}

private struct ProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(Theme.key)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.accent).frame(width: proxy.size.width * value)
                }
        }
        .frame(height: 4)
    }
}

// MARK: - Yayın uygulamaları

private struct StreamingShelf: View {
    @Environment(TVController.self) private var tv

    private static let ids = ["netflix", "prime", "youtube"]

    var body: some View {
        let today = tv.activity.totals(lastDays: 1)
        let week = tv.activity.totals(lastDays: 7)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel(text: "Uygulamalar")
                Spacer()
                Text("kullanım").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 2)
            HStack(spacing: 8) {
                ForEach(Self.ids.compactMap { id in TVApp.all.first { $0.id == id } }) { app in
                    BrandCard(app: app, usage: usage(app, today: today, week: week))
                }
            }
        }
    }

    /// Bugün kullanıldıysa bugünkü süre, yoksa son 7 gün.
    private func usage(_ app: TVApp, today: [String: Double], week: [String: Double]) -> (value: String, caption: String) {
        if let seconds = today[app.name], seconds >= 60 { return (formatDuration(seconds), "bugün") }
        if let seconds = week[app.name], seconds >= 60 { return (formatDuration(seconds), "son 7 gün") }
        return ("—", "henüz yok")
    }
}

/// Marka renkli büyük uygulama kartı; TV'de açıksa çerçevelenir ve yeşil nokta taşır.
private struct BrandCard: View {
    @Environment(TVController.self) private var tv
    let app: TVApp
    let usage: (value: String, caption: String)

    private var isRunning: Bool { tv.isOnline && tv.runningApp == app }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 13, style: .continuous) }

    var body: some View {
        KeyButton(action: { tv.open(app) }, help: "\(app.name) aç") {
            VStack(alignment: .leading, spacing: 0) {
                wordmark
                Spacer(minLength: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text(usage.value).font(.system(size: 11, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.75))
                    Text(usage.caption).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.4))
                }
                .lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 92)
            .background(background)
            .overlay(shape.stroke(isRunning ? Brand.tint(app).opacity(0.9) : Theme.cardStroke, lineWidth: isRunning ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if isRunning {
                    Circle().fill(.green).frame(width: 8, height: 8)
                        .background(Circle().fill(.green.opacity(0.25)).frame(width: 14, height: 14))
                        .padding(9)
                }
            }
            .shadow(color: isRunning ? Brand.tint(app).opacity(0.25) : .clear, radius: 10, y: 4)
            .animation(.easeInOut(duration: 0.25), value: isRunning)
        }
    }

    @ViewBuilder private var wordmark: some View {
        switch app.id {
        case "netflix":
            Text("NETFLIX")
                .font(.system(size: 17, weight: .black))
                .fontWidth(.condensed)
                .tracking(0.6)
                .foregroundStyle(Brand.netflix)
        case "prime":
            VStack(alignment: .leading, spacing: -3) {
                Text("prime").font(.system(size: 15, weight: .bold))
                Text("video").font(.system(size: 11.5, weight: .medium)).foregroundStyle(Color(red: 0.81, green: 0.91, blue: 0.97))
                PrimeSmile().stroke(Brand.prime, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 32, height: 7)
                    .padding(.top, 3)
            }
            .foregroundStyle(.white)
        default:
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous).fill(Brand.youtube)
                    .frame(width: 18, height: 13)
                    .overlay(Image(systemName: "play.fill").font(.system(size: 6.5)).foregroundStyle(.white))
                Text("YouTube").font(.system(size: 13, weight: .bold)).tracking(-0.4).foregroundStyle(.white)
            }
        }
    }

    @ViewBuilder private var background: some View {
        switch app.id {
        case "netflix":
            shape.fill(Color(white: 0.02))
                .overlay(RadialGradient(colors: [Brand.netflix.opacity(0.35), .clear], center: .topTrailing,
                                        startRadius: 0, endRadius: 110).clipShape(shape))
        case "prime":
            shape.fill(LinearGradient(colors: [Color(red: 0.05, green: 0.16, blue: 0.25), Color(red: 0.04, green: 0.09, blue: 0.14)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
        default:
            shape.fill(Color(white: 0.11))
        }
    }
}

/// Prime Video logosundaki gülümseme oku.
private struct PrimeSmile: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2),
                          control: CGPoint(x: rect.midX, y: rect.maxY * 1.4))
        return path
    }
}

// MARK: - Diğer uygulamalar

private struct OtherAppsRow: View {
    @Environment(TVController.self) private var tv

    private static let items: [(id: String, title: String, symbol: String)] = [
        ("browser", "İnternet", "globe"),
        ("media", "Medya", "play.square.stack"),
        ("portal", "Tümü", "square.grid.2x2"),
    ]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Self.items, id: \.id) { item in
                if let app = TVApp.all.first(where: { $0.id == item.id }) {
                    KeyButton(action: { tv.open(app) }, help: app.name) {
                        HStack(spacing: 6) {
                            Image(systemName: item.symbol).font(.system(size: 11)).foregroundStyle(.secondary)
                            Text(item.title).font(.system(size: 11.5, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.key))
                    }
                }
            }
        }
    }
}

// MARK: - YouTube

/// YouTube linkini TV'de oynatır; panodaki linki kendiliğinden önerir.
struct YouTubeCard: View {
    @Environment(TVController.self) private var tv
    @State private var link = ""
    @State private var info: YouTubeInfo?
    @State private var fromClipboard = false

    private var video: YouTubeVideo? { YouTubeVideo(link: link) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "YouTube'da oynat")
                Spacer()
                if fromClipboard, video != nil {
                    Label("Panodan alındı", systemImage: "doc.on.clipboard")
                        .font(.system(size: 10.5)).foregroundStyle(.tertiary)
                } else {
                    Button("Panodan", action: paste)
                        .buttonStyle(.plain).font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
            }
            if let video {
                preview(video)
                Button(action: play) {
                    Label("TV'de oynat", systemImage: "play.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                HStack(spacing: 6) {
                    Image(systemName: "link").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField("Başka bir link yapıştır", text: $link)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5))
                        .onSubmit(play)
                    Button { link = ""; fromClipboard = false } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Linki temizle")
                }
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.cardStroke))
            } else {
                emptyState
            }
            status
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
        .task(id: video?.id) {
            info = nil
            if let video { info = await YouTubeCaster.info(for: video) }
        }
        .onAppear {
            if link.isEmpty, let text = NSPasteboard.general.string(forType: .string), YouTubeVideo(link: text) != nil {
                link = text
                fromClipboard = true
            }
        }
    }

    private func preview(_ video: YouTubeVideo) -> some View {
        HStack(alignment: .top, spacing: 10) {
            AsyncImage(url: info?.thumbnail) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Theme.key
            }
            .frame(width: 104, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(info?.title ?? "Video bilgisi alınıyor…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text([info?.author, video.start > 0 ? "Başlangıç \(Self.clock(video.start))" : nil]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    /// Link yokken: yapıştırma alanı. Linki panelin herhangi bir yerine bırakmak da onu oynatır.
    private var emptyState: some View {
        VStack(spacing: 6) {
            TextField("YouTube linkini yapıştır", text: $link)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 12, weight: .medium))
                .onSubmit(play)
            Text("ya da linki panele sürükleyip bırak")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
            if !link.isEmpty {
                Text("Bu bir YouTube linki değil.").font(.system(size: 10.5)).foregroundStyle(Theme.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
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

    private func paste() {
        link = NSPasteboard.general.string(forType: .string) ?? ""
        fromClipboard = video != nil
    }

    private func play() {
        guard let video else { return }
        tv.playYouTube(video)
    }

    /// 42 → "0:42", 3725 → "1:02:05".
    private static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
