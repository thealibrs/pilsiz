import Foundation
import Network
import Observation
import ServiceManagement

/// TV'de açılabilen bir uygulama: DIAL ile ya da kumanda tuşuyla.
struct TVApp: Identifiable, Hashable {
    enum Launch: Hashable { case dial(String), key(Int) }

    let id: String
    let name: String
    let launch: Launch

    static let all: [TVApp] = [
        TVApp(id: "netflix", name: "Netflix", launch: .dial("Netflix")),
        TVApp(id: "prime", name: "Prime Video", launch: .dial("AmazonInstantVideo")),
        TVApp(id: "youtube", name: "YouTube", launch: .dial("YouTube")),
        TVApp(id: "browser", name: "İnternet", launch: .key(1065)),
        TVApp(id: "media", name: "Medya", launch: .key(1057)),
        TVApp(id: "portal", name: "Uygulamalar", launch: .key(1046)),
    ]

    /// Durumu DIAL ile izlenebilen uygulamalar.
    static let tracked = all.filter { if case .dial = $0.launch { true } else { false } }
}

@MainActor
@Observable
final class TVController {
    enum Status: Equatable {
        case unknown, online, offline, waking, searching
    }

    var host: String { didSet { defaults.set(host, forKey: "host") } }
    var mac: String { didSet { defaults.set(mac, forKey: "mac") } }
    var name: String { didSet { defaults.set(name, forKey: "name") } }
    /// TV'nin kendi bildirdiği model ("Daewoo 43DE54F · Vestel"); TV ilk kez bulununca öğrenilir.
    private(set) var model: String { didSet { defaults.set(model, forKey: "tvModel") } }
    /// TV'nin kaynak menüsündeki sırayla, virgülle ayrılmış giriş adları.
    var inputsText: String { didSet { defaults.set(inputsText, forKey: "inputs") } }

    private(set) var status: Status = .unknown
    private(set) var lastError: String?
    private(set) var discovered: [String] = []
    /// DIAL'a göre şu an TV'de çalışan uygulama.
    private(set) var runningApp: TVApp? {
        didSet {
            guard runningApp != oldValue else { return }
            // Pilsiz açıldığında zaten çalışan uygulamanın başlangıç zamanı bilinmez.
            runningAppSince = runningApp != nil && hasPolledApps ? Date() : nil
        }
    }
    /// Uygulamanın açıldığını Pilsiz'in gördüğü an.
    private(set) var runningAppSince: Date?
    private var hasPolledApps = false
    private(set) var currentInput: String?

    enum ChannelSync: Equatable {
        case idle, syncing
        case done(added: Int, total: Int)
        case failed(String)
    }
    private(set) var channelSync: ChannelSync = .idle
    private var cursorDX = 0.0
    private var cursorDY = 0.0
    private var cursorTask: Task<Void, Never>?

    /// TV ses seviyesini ağdan bildirmediği için seviye burada takip edilir (0–100).
    private(set) var volume: Int { didSet { defaults.set(volume, forKey: "volume") } }
    private(set) var isMuted = false
    /// TV'ye gerçekten ulaştırılmış seviye; kaydırıcı hedefi ile arası tek tek tuşla kapatılır.
    private var sentVolume: Int
    private var volumeWorker: Task<Void, Never>?

    let channels = ChannelStore()
    let activity = ActivityStore()
    let epg = EPGStore()
    let reminders = ReminderStore()
    let youtube = YouTubeCaster()
    let assistant = Assistant()
    let share = ScreenShare()
    let dashboard = Dashboard()
    private let voice = VoiceListener()
    var isListening: Bool { assistant.phase == .listening }

    var isOnline: Bool { status == .online }
    var inputs: [String] {
        inputsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var currentChannel: Channel? { channels.channels.first { $0.id == channels.lastChannelID } }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Oturum açılışı ayarlanamadı: \(error.localizedDescription)"
            }
        }
    }

    private let defaults = UserDefaults.standard
    private var didAutoDiscover = false
    private var wakeFailedAt: Date?
    private var lastSample: Date?
    /// Komutlar sırayla çalışır; TV'nin gömülü sunucusu eşzamanlı isteklerde takılabiliyor.
    private var queue: Task<Void, Never>?

    init() {
        host = defaults.string(forKey: "host") ?? ""
        mac = defaults.string(forKey: "mac") ?? ""
        name = defaults.string(forKey: "name") ?? "Salon"
        model = defaults.string(forKey: "tvModel") ?? ""
        inputsText = defaults.string(forKey: "inputs") ?? "TV, HDMI 1, HDMI 2, HDMI 3, AV"
        volume = defaults.object(forKey: "volume") as? Int ?? 20
        sentVolume = defaults.object(forKey: "volume") as? Int ?? 20
        Task { await startPolling() }
    }

    #if DEBUG
    /// Anlık görüntü modunda TV kapalıyken de "bağlı" görünümü çizmek için; durum yoklaması bunu geri almaz.
    private var debugPinnedOnline = false
    func debugForceOnline() {
        debugPinnedOnline = true
        status = .online
        lastError = nil
    }
    #endif

    // MARK: - Komutlar

    func press(_ key: RemoteKey) {
        // Pano açıkken ok, OK ve geri tuşları TV'ye değil panoya gider.
        if dashboard.handle(key, tv: self) { return }
        switch key {
        case .power: power()
        case .volumeUp: setVolume(volume + 1)
        case .volumeDown: setVolume(volume - 1)
        case .mute:
            isMuted.toggle()
            send(code: key.rawValue)
        case .channelUp, .channelDown:
            stepChannel(up: key == .channelUp)
            send(code: key.rawValue)
        default: send(code: key.rawValue)
        }
    }

    // MARK: - Ses

    /// Hedef seviyeye, aradaki fark kadar ses +/− tuşuna basarak ulaşır.
    /// Sürükleme sırasında hedef değişirse aynı işçi yeni hedefe yönelir.
    func setVolume(_ target: Int) {
        volume = min(100, max(0, target))
        isMuted = false
        guard volumeWorker == nil, !host.isEmpty else { return }
        let host = host
        volumeWorker = Task {
            defer { volumeWorker = nil }
            while sentVolume != volume {
                let up = volume > sentVolume
                do {
                    try await SmartCenter.send((up ? RemoteKey.volumeUp : .volumeDown).rawValue, to: host)
                } catch {
                    fail(error)
                    return
                }
                sentVolume += up ? 1 : -1
                // TV çok hızlı gelen basışları yutabiliyor; seviyenin kaymaması için aralık bırakılır.
                try? await Task.sleep(for: .milliseconds(180))
            }
        }
    }

    /// TV ekranında görülen seviyeyi tuş göndermeden kaydeder.
    func syncVolume(to level: Int) {
        volume = min(100, max(0, level))
        sentVolume = volume
    }

    /// Kanal +/− sonrası listedeki bir sonraki/önceki kanalı “ekranda” kabul eder.
    private func stepChannel(up: Bool) {
        guard let current = currentChannel else { return }
        let list = channels.channels
        let next = up ? list.first { $0.number > current.number } : list.last { $0.number < current.number }
        channels.lastChannelID = next?.id
    }

    func send(code: Int) {
        enqueue { host in try await SmartCenter.send(code, to: host) }
    }

    /// Kanal numarasını rakam rakam tuşlar; TV kısa bir beklemenin ardından kanala geçer.
    func switchTo(_ channel: Channel) {
        channels.lastChannelID = channel.id
        currentInput = "TV"
        runningApp = nil
        tune(channel.number)
    }

    /// TV'de şu an açık olan kanalı TV'ye komut göndermeden işaretler.
    /// TV açık kanalı ağdan bildirmediği için kanal başka yerden değişince buradan düzeltilir.
    func markCurrent(_ channel: Channel) {
        channels.lastChannelID = channel.id
        currentInput = "TV"
        runningApp = nil
    }

    /// Bildirim gibi dış tetikleyicilerden: TV kapalıysa önce uyandırır, sonra kanala geçer.
    func open(channelNumber number: Int) {
        guard let channel = channels.channels.first(where: { $0.number == number }) else { return }
        switchTo(channel)
    }

    // MARK: - Kanal listesi, klavye, imleç

    /// Kanal listesini TV'den çeker ve mevcut listeyle birleştirir (radyolar hariç).
    func syncChannels() async {
        guard !host.isEmpty, channelSync != .syncing else { return }
        channelSync = .syncing
        do {
            let services = try await SmartCenter.channelList(from: host).filter(\.isTV)
            let added = channels.merge(services)
            defaults.set(Date(), forKey: "channelsSyncedAt")
            channelSync = .done(added: added, total: services.count)
        } catch {
            channelSync = .failed(error.localizedDescription)
        }
    }

    /// Metni TV'deki etkin yazı alanına yazar.
    func type(_ text: String) {
        enqueue { host in try await SmartCenter.type(text, to: host) }
    }

    /// İmleci göreli taşır; hızlı hareketler birikip ~60 Hz'de tek istekte gönderilir.
    func moveCursor(dx: Double, dy: Double) {
        cursorDX += dx
        cursorDY += dy
        guard cursorTask == nil, !host.isEmpty else { return }
        let host = host
        cursorTask = Task {
            defer { cursorTask = nil }
            while abs(cursorDX) >= 0.5 || abs(cursorDY) >= 0.5 {
                let (dx, dy) = (cursorDX, cursorDY)
                cursorDX = 0
                cursorDY = 0
                try? await SmartCenter.moveCursor(dx: dx, dy: dy, on: host)
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    func tune(_ number: Int) {
        let digits = String(number).compactMap(\.wholeNumberValue)
        enqueue { host in
            for digit in digits {
                try await SmartCenter.send(RemoteKey.digit(digit).rawValue, to: host)
                try await Task.sleep(for: .milliseconds(150))
            }
        }
    }

    /// Kaynak menüsünü açar ve menüdeki sırasına göre girişi rakamla seçer.
    func selectInput(_ index: Int) {
        guard inputs.indices.contains(index) else { return }
        currentInput = inputs[index]
        runningApp = nil
        channels.lastChannelID = nil
        enqueue { host in
            try await SmartCenter.send(RemoteKey.source.rawValue, to: host)
            try await Task.sleep(for: .milliseconds(1200))
            try await SmartCenter.send(RemoteKey.digit(min(index + 1, 9)).rawValue, to: host)
        }
    }

    // MARK: - Pilsiz'e söyle

    /// Yazılı istek (⌘K aramasından).
    func ask(_ text: String) {
        Task { await assistant.handle(text, tv: self) }
    }

    /// Mikrofonu açar; konuşma bitince (sessizlik ya da `finishListening`) isteği işler.
    func startListening() {
        guard !voice.isListening, assistant.phase != .listening else { return }
        assistant.beginListening()
        Task {
            guard await VoiceListener.authorize() else {
                assistant.fail("Mikrofon ya da konuşma tanıma izni yok: Sistem Ayarları › Gizlilik ve Güvenlik.")
                return
            }
            do {
                try voice.start(onText: { [weak self] in self?.assistant.updateTranscript($0) },
                                onSilence: { [weak self] in self?.finishListening() })
            } catch {
                assistant.fail(error.localizedDescription)
            }
        }
    }

    func finishListening() {
        guard voice.isListening else { return }
        Task {
            let text = await voice.stop()
            await assistant.handle(text, tv: self)
        }
    }

    /// YouTube videosunu TV'deki YouTube uygulamasında oynatır.
    func playYouTube(_ video: YouTubeVideo) {
        guard !host.isEmpty else { lastError = "Önce TV'nin IP adresini ayarlayın"; return }
        let host = host
        Task {
            guard await awaitAwake() else { return }
            youtube.play(video, on: host)
        }
        runningApp = TVApp.all.first { $0.id == "youtube" }
    }

    func open(_ app: TVApp) {
        switch app.launch {
        case .key(let code):
            send(code: code)
        case .dial(let dialName):
            enqueue { host in try await SmartCenter.launch(app: dialName, on: host) }
            runningApp = app
        }
    }

    /// Açık uygulamayı DIAL ile kapatır. DIAL kapatamazsa Çıkış tuşu gönderilir.
    func close(_ app: TVApp) {
        guard case .dial(let dialName) = app.launch else { send(code: RemoteKey.exit.rawValue); return }
        if runningApp == app { runningApp = nil }
        enqueue { host in
            do {
                try await SmartCenter.stop(app: dialName, on: host)
            } catch {
                try await SmartCenter.send(RemoteKey.exit.rawValue, to: host)
            }
        }
    }

    /// Uygulamayı kapatıp yeniden açar; uygulama kendi ana ekranından (ör. profil seçimi) başlar.
    func restart(_ app: TVApp) {
        guard case .dial(let dialName) = app.launch else { return }
        enqueue { host in
            try? await SmartCenter.stop(app: dialName, on: host)
            try await Task.sleep(for: .seconds(2))
            try await SmartCenter.launch(app: dialName, on: host)
        }
        runningApp = app
        runningAppSince = Date()
    }

    func power() {
        if status == .online || mac.isEmpty {
            send(code: RemoteKey.power.rawValue)
        } else {
            wake()
        }
    }

    /// Wake-on-LAN gönderir ve TV ağa dönene kadar (en fazla ~30 sn) bekler.
    func wake() {
        do {
            try WakeOnLAN.send(mac: mac)
        } catch {
            fail(error)
            return
        }
        status = .waking
        lastError = nil
        Task {
            for _ in 0..<15 {
                try? await Task.sleep(for: .seconds(2))
                if !host.isEmpty, await SmartCenter.isOnline(host) { markOnline(); return }
                try? WakeOnLAN.send(mac: mac)
            }
            if status == .waking {
                status = .offline
                wakeFailedAt = Date()
                lastError = "TV uyanmadı. TV ayarlarında 'Ağda Uyandırma / Wake On LAN' açık mı?"
            }
        }
    }

    /// TV kapalıysa önce uyandırır ve ağa dönmesini bekler; böylece kapalıyken basılan kanal ya da
    /// uygulama, TV açılınca kendiliğinden çalışır. TV zaten açıksa hemen döner.
    private func awaitAwake() async -> Bool {
        guard status == .offline || status == .waking, !mac.isEmpty else { return true }
        // Uyandırma az önce başarısız olduysa sıradaki komutlar yeniden 30 sn beklemesin.
        if let failed = wakeFailedAt, Date().timeIntervalSince(failed) < 10 { return false }
        if status != .waking { wake() }
        while status == .waking { try? await Task.sleep(for: .milliseconds(500)) }
        guard isOnline else { return false }
        // TV açılınca yayının ve uygulama sunucusunun hazır olması için kısa bir süre tanınır.
        try? await Task.sleep(for: .seconds(4))
        return true
    }

    private func enqueue(_ operation: @escaping @MainActor (String) async throws -> Void) {
        let host = host
        guard !host.isEmpty else { lastError = "Önce TV'nin IP adresini ayarlayın"; return }
        let previous = queue
        queue = Task {
            await previous?.value
            guard await awaitAwake() else { return }
            do {
                try await operation(host)
                markOnline()
            } catch {
                fail(error)
            }
        }
    }

    // MARK: - Durum ve keşif

    func refresh() async {
        #if DEBUG
        if debugPinnedOnline { return }
        #endif
        guard status != .waking, status != .searching else { return }
        if host.isEmpty {
            // Otomatik tarama yalnızca bir kez; sonrası için Ayarlar › “Ağda ara”.
            if !didAutoDiscover { didAutoDiscover = true; await discover() }
            return
        }
        if await SmartCenter.isOnline(host) {
            markOnline()
            await refreshRunningApp()
        } else if status != .waking {
            status = .offline
            runningApp = nil
        }
        recordActivity()
    }

    func discover() async {
        status = .searching
        lastError = nil
        let found = await SmartCenter.discover()
        discovered = found
        if let first = found.first, !found.contains(host) { host = first }
        if found.isEmpty {
            status = .offline
            lastError = "Ağda TV bulunamadı. TV açık ve aynı Wi‑Fi'da mı?"
        } else {
            markOnline()
        }
    }

    private func refreshRunningApp() async {
        let host = host
        for app in TVApp.tracked {
            guard case .dial(let dialName) = app.launch else { continue }
            if await SmartCenter.isRunning(app: dialName, on: host) {
                runningApp = app
                hasPolledApps = true
                return
            }
        }
        if let app = runningApp, TVApp.tracked.contains(app) { runningApp = nil }
        hasPolledApps = true
    }

    private func recordActivity() {
        let now = Date()
        defer { lastSample = now }
        guard isOnline, let last = lastSample else { return }
        // Uzun aralıklar (uyku, ağ kopması) sayılmaz.
        let elapsed = now.timeIntervalSince(last)
        guard elapsed < 60 else { return }
        activity.record(seconds: elapsed, app: runningApp?.name ?? currentChannel.map { ActivityStore.channelKey($0.number) })
    }

    private func startPolling() async {
        while true {
            await refresh()
            try? await Task.sleep(for: .seconds(status == .online ? 15 : 6))
        }
    }

    private func markOnline() {
        let wasOnline = status == .online
        status = .online
        lastError = nil
        if !wasOnline || mac.isEmpty { learnMAC() }
        if !wasOnline || model.isEmpty { learnModel() }
        // Kanal listesi günde en fazla iki kez TV'den kendiliğinden tazelenir.
        let lastSync = defaults.object(forKey: "channelsSyncedAt") as? Date ?? .distantPast
        if !wasOnline, Date().timeIntervalSince(lastSync) > 12 * 3600 {
            Task { await syncChannels() }
        }
    }

    private func learnModel() {
        let host = host
        Task {
            if let info = await SmartCenter.deviceInfo(host) {
                let label = SmartCenter.modelLabel(name: info.name, manufacturer: info.manufacturer)
                if !label.isEmpty, label != model { model = label }
            }
        }
    }

    private func learnMAC() {
        let host = host
        Task {
            if let found = await LocalNetwork.macAddress(for: host), found != mac { mac = found }
        }
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        // Zaman aşımı ya da bağlantı hatası TV'nin kapalı/ulaşılamaz olduğunu gösterir.
        if error is NWError || error as? TVError == .timeout {
            status = .offline
        }
    }
}
