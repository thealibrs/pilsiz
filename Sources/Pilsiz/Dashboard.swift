import Foundation
import Observation

/// Panodaki bir YouTube kısayolu: video linki ya da kanal adresi (kanalın o anki canlı yayını açılır).
struct PanoShortcut: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var link: String

    static let defaults = [
        PanoShortcut(name: "Lofi müzik", link: "https://www.youtube.com/@LofiGirl"),
        PanoShortcut(name: "NTV", link: "https://www.youtube.com/@NTV"),
        PanoShortcut(name: "CNN Türk", link: "https://www.youtube.com/@cnnturk"),
        PanoShortcut(name: "NASA", link: "https://www.youtube.com/@NASA"),
    ]
}

/// Panonun hava durumu için şehir (Open-Meteo koordinatları ve saat dilimi).
struct PanoCity: Codable, Equatable, Sendable {
    var name: String
    var latitude: Double
    var longitude: Double
    var timeZone: String

    static let ankara = PanoCity(name: "Ankara", latitude: 39.93, longitude: 32.86, timeZone: "Europe/Istanbul")
}

/// Panodaki haberlerin RSS kaynağı.
struct NewsSource: Hashable, Sendable {
    let name: String
    let url: URL

    static let presets = [
        NewsSource(name: "Gazete Oksijen", url: URL(string: "https://gazeteoksijen.com/export/rss")!),
        NewsSource(name: "BBC Türkçe", url: URL(string: "https://feeds.bbci.co.uk/turkce/rss.xml")!),
        NewsSource(name: "CNN Türk", url: URL(string: "https://www.cnnturk.com/feed/rss/all/news")!),
        NewsSource(name: "Habertürk", url: URL(string: "https://www.haberturk.com/rss")!),
        NewsSource(name: "TRT Haber", url: URL(string: "https://www.trthaber.com/manset_articles.rss")!),
    ]
}

/// TV'de açılan pano: uygulamalar, YouTube kısayolları, haberler, hava ve piyasa.
///
/// Sayfa `ShareServer`'dan sunulur ve "TV'de göster" ile aynı HbbTV ekranında açılır. Veriyi Mac toplar;
/// TV'nin tarayıcısı dışarıya istek atmaz. Ok tuşları `TVController.press` üzerinden sayfaya iletilir.
@MainActor
@Observable
final class Dashboard {
    enum Status: Equatable {
        case closed, opening, open
        case failed(String)
    }

    private(set) var status: Status = .closed
    var shortcuts: [PanoShortcut] {
        didSet {
            guard shortcuts != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(shortcuts), forKey: "panoShortcuts")
            fetched["shortcuts"] = nil
        }
    }

    /// Hava durumu şehri; Ayarlar › Pano'dan değişir.
    var city: PanoCity {
        didSet {
            guard city != oldValue else { return }
            defaults.set(try? JSONEncoder().encode(city), forKey: "panoCity")
            fetched["weather"] = nil
        }
    }

    /// Haber kaynağının RSS adresi; Ayarlar › Pano'dan değişir.
    var newsFeed: URL {
        didSet {
            guard newsFeed != oldValue else { return }
            defaults.set(newsFeed.absoluteString, forKey: "panoNewsFeed")
            fetched["news"] = nil
        }
    }

    var newsSourceName: String {
        NewsSource.presets.first { $0.url == newsFeed }?.name ?? newsFeed.host()?.replacingOccurrences(of: "www.", with: "") ?? "Haber"
    }

    private let defaults = UserDefaults.standard
    private var refreshTask: Task<Void, Never>?
    private var fetched: [String: Date] = [:]
    private var news: [News] = []
    private var weather: Weather?
    private var market: [MarketRow] = []
    /// Kısayolların çözülmüş video kimlikleri ve küçük resimleri (kısayol sırasıyla).
    private var videos: [String?] = []
    private var thumbnails: [Data?] = []

    init() {
        shortcuts = defaults.data(forKey: "panoShortcuts").flatMap { try? JSONDecoder().decode([PanoShortcut].self, from: $0) }
            ?? PanoShortcut.defaults
        city = defaults.data(forKey: "panoCity").flatMap { try? JSONDecoder().decode(PanoCity.self, from: $0) } ?? .ankara
        newsFeed = defaults.string(forKey: "panoNewsFeed").flatMap(URL.init(string:)) ?? NewsSource.presets[0].url
    }

    func isOpen(on share: ScreenShare) -> Bool {
        status == .open && share.server.currentMode == .dashboard
    }

    #if DEBUG
    /// Anlık görüntü modunda pano kartını açık hâliyle çizmek için; TV'ye bir şey gönderilmez.
    func debugMarkOpen(tv: TVController) {
        status = .open
        tv.share.server.setMode(.dashboard)
    }
    #endif

    // MARK: - Açma, kapama

    func open(tv: TVController) {
        guard status != .opening else { return }
        status = .opening
        let server = tv.share.server
        server.setPanoAction { [weak self, weak tv] id in
            Task { @MainActor in
                if let self, let tv { self.perform(id, tv: tv) }
            }
        }
        Task {
            // Eldeki veriyle hemen açılır; taze veri arkadan gelir.
            publish(tv: tv)
            server.setMode(.dashboard)
            if let failure = await tv.share.openScreen(tv: tv) {
                server.setMode(.idle)
                status = .failed(failure)
                return
            }
            status = .open
            refreshTask?.cancel()
            refreshTask = Task {
                while !Task.isCancelled, isOpen(on: tv.share) {
                    await refresh(tv: tv)
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
    }

    /// Panoyu kapatır; TV canlı yayına döner.
    func close(tv: TVController) {
        status = .closed
        refreshTask?.cancel()
        tv.share.stop()
    }

    /// Pano açıkken gezinme tuşlarını sayfaya yollar. Tuş panoya gittiyse true.
    func handle(_ key: RemoteKey, tv: TVController) -> Bool {
        guard status == .open else { return false }
        guard isOpen(on: tv.share) else {
            // Pano başka bir gönderimle ya da kapatılarak ekrandan kalkmış.
            status = .closed
            refreshTask?.cancel()
            return false
        }
        let name: String? = switch key {
        case .up: "up"
        case .down: "down"
        case .left: "left"
        case .right: "right"
        case .ok: "ok"
        case .back, .exit: "back"
        default: nil
        }
        guard let name else { return false }
        tv.share.server.pushPanoKey(name)
        return true
    }

    /// Panoda seçilen kart. Uygulama açmadan önce pano kapatılır ki TV yayına dönmüş olsun.
    private func perform(_ id: String, tv: TVController) {
        guard isOpen(on: tv.share) else { return }
        if id == "close" || id == "live" {
            close(tv: tv)
        } else if id == "app:mac" {
            status = .closed
            refreshTask?.cancel()
            tv.share.startMirroring(tv: tv)
        } else if id.hasPrefix("app:"), let app = TVApp.all.first(where: { $0.id == id.dropFirst(4) }) {
            leave(tv: tv) { tv.open(app) }
        } else if id.hasPrefix("yt:"), let index = Int(id.dropFirst(3)), videos.indices.contains(index),
                  let videoID = videos[index], let video = YouTubeVideo(link: videoID) {
            leave(tv: tv) { tv.playYouTube(video) }
        }
    }

    private func leave(tv: TVController, then action: @escaping @MainActor () -> Void) {
        close(tv: tv)
        Task {
            // Sayfanın "kapan" komutunu alıp TV'nin yayına dönmesi için.
            try? await Task.sleep(for: .milliseconds(1500))
            action()
        }
    }

    // MARK: - Veri

    private func isStale(_ key: String, after seconds: TimeInterval) -> Bool {
        Date().timeIntervalSince(fetched[key] ?? .distantPast) > seconds
    }

    func refresh(tv: TVController) async {
        let now = Date()
        let (feed, source, city) = (newsFeed, newsSourceName, city)
        async let newNews = isStale("news", after: 600) ? Self.fetchNews(from: feed, source: source) : nil
        async let newWeather = isStale("weather", after: 1200) ? Self.fetchWeather(for: city) : nil
        async let newMarket = isStale("market", after: 300) ? Self.fetchMarket() : nil
        let links = shortcuts.map(\.link)
        async let newShortcuts = isStale("shortcuts", after: 1800) ? Self.resolve(links) : nil

        if let items = await newNews { news = items; fetched["news"] = now }
        if let value = await newWeather { weather = value; fetched["weather"] = now }
        if let rows = await newMarket { market = rows; fetched["market"] = now }
        // Kısayollar bu arada düzenlendiyse sonuç eski listeye aittir; bir sonraki turda yeniden çözülür.
        if let resolved = await newShortcuts, links == shortcuts.map(\.link) {
            videos = resolved.map(\.id)
            thumbnails = resolved.map(\.thumbnail)
            fetched["shortcuts"] = now
        }
        publish(tv: tv)
    }

    /// Eldeki veriyi sayfanın okuduğu JSON'a çevirip sunucuya verir.
    private func publish(tv: TVController) {
        var images: [String: Data] = [:]
        var root: [String: Any] = [
            "city": city.name,
            "tz": TimeZone.current.secondsFromGMT() / 60,
            "news": news.map { ["cat": $0.category, "time": Int($0.date.timeIntervalSince1970 * 1000), "title": $0.title, "sum": $0.summary] },
            "market": market.map { ["name": $0.name, "unit": $0.unit, "value": $0.value, "change": $0.change, "up": $0.up, "points": $0.points] },
        ]
        root["shorts"] = shortcuts.prefix(4).enumerated().map { index, shortcut -> [String: Any] in
            var entry: [String: Any] = ["name": shortcut.name]
            if thumbnails.indices.contains(index), let thumbnail = thumbnails[index], let id = videos[index] {
                // Ad video kimliğini içerir: yayın değişince TV eski resmi önbellekten göstermez.
                let name = "yt-\(id).jpg"
                images[name] = thumbnail
                entry["img"] = "/pano/img/\(name)"
            }
            return entry
        }
        if let weather {
            root["weather"] = [
                "temp": weather.temperature, "feels": weather.feelsLike, "text": weather.text, "icon": weather.icon,
                "hours": weather.hours.map { ["t": $0.time, "temp": $0.temperature, "icon": $0.icon] },
                "days": weather.days.map { ["name": $0.name, "icon": $0.icon, "max": $0.high, "min": $0.low] },
            ] as [String: Any]
        }
        if let channel = tv.currentChannel {
            var live: [String: Any] = ["name": channel.name.replacingOccurrences(of: " HD", with: ""), "prog": "", "left": ""]
            if let programme = tv.epg.schedule(for: channel.name).now {
                live["prog"] = programme.title
                live["left"] = Self.remaining(until: programme.stop)
            }
            if let logo = Self.logoData(for: channel.name) {
                let name = "logo-\(NameKey.key(channel.name)).png"
                images[name] = logo
                live["logo"] = "/pano/img/\(name)"
            }
            root["live"] = live
        }
        guard let json = try? JSONSerialization.data(withJSONObject: root, options: [.sortedKeys]) else { return }
        tv.share.server.setPano(json: json, images: images)
    }

    private static func remaining(until date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        return minutes >= 60 ? "\(minutes / 60) sa \(minutes % 60) dk kaldı" : "\(minutes) dk kaldı"
    }

    private static func logoData(for channelName: String) -> Data? {
        let key = NameKey.key(channelName)
        var url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "Logos")
        #if DEBUG
        if url == nil { url = URL(fileURLWithPath: "Resources/Logos/\(key).png") }
        #endif
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: - Kaynaklar

    struct News: Sendable {
        let category: String
        let date: Date
        let title: String
        let summary: String
    }

    struct Weather: Sendable {
        struct Hour: Sendable { let time: String; let temperature: Int; let icon: String }
        struct Day: Sendable { let name: String; let icon: String; let high: Int; let low: Int }
        let temperature: Int
        let feelsLike: Int
        let text: String
        let icon: String
        let hours: [Hour]
        let days: [Day]
    }

    struct MarketRow: Sendable {
        let name: String
        let unit: String
        let value: String
        let change: String
        let up: Bool
        /// Gün içi seyir, 0–1 arasına ölçeklenmiş.
        let points: [Double]
    }

    private nonisolated static func get(_ url: URL, headers: [String: String] = [:]) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 12)
        // Haber ve piyasa sunucuları tarayıcı kimliği olmayan istekleri geri çevirebiliyor.
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36",
                         forHTTPHeaderField: "User-Agent")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    // MARK: Haberler (RSS)

    private nonisolated static let categories = [
        "turkiye": "Türkiye", "dunya": "Dünya", "ekonomi": "Ekonomi", "spor": "Spor", "teknoloji": "Teknoloji",
        "kultur-sanat": "Kültür", "saglik": "Sağlık", "yasam": "Yaşam", "bilim": "Bilim", "politika": "Politika",
        "yazarlar": "Yazarlar", "egitim": "Eğitim", "cevre": "Çevre", "magazin": "Magazin", "otomobil": "Otomobil",
    ]

    /// RSS beslemesindeki ilk 12 haber. Kategori, haber adresinin ilk iki parçasından tanınırsa yazılır
    /// (gazeteoksijen.com/dunya/…, trthaber.com/haber/turkiye/…); tanınmazsa kaynağın adı kullanılır.
    nonisolated static func fetchNews(from feed: URL, source: String) async -> [News]? {
        guard let data = await get(feed) else { return nil }
        let text = String(decoding: data, as: UTF8.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let date = { (value: String) -> Date? in
            for format in ["EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss zzz"] {
                formatter.dateFormat = format
                if let date = formatter.date(from: value) { return date }
            }
            return nil
        }
        let items = text.matches(of: /<item>(.*?)<\/item>/.dotMatchesNewlines()).prefix(12).compactMap { match -> News? in
            let item = String(match.output.1)
            guard let title = field("title", in: item), !title.isEmpty else { return nil }
            let path = (field("link", in: item) ?? field("guid", in: item)).flatMap { URL(string: $0)?.pathComponents.dropFirst() } ?? []
            let category = path.prefix(2).lazy.compactMap { categories[$0] }.first ?? source
            let summary = field("h4", in: item) ?? field("description", in: item).map { String($0.prefix(240)) } ?? ""
            return News(category: category, date: field("pubDate", in: item).flatMap(date) ?? Date(), title: title, summary: summary)
        }
        return items.isEmpty ? nil : Array(items)
    }

    /// Etiketin içeriği: iç etiketler atılır, HTML kaçışları çözülür, boşluklar sadeleşir.
    private nonisolated static func field(_ name: String, in text: String) -> String? {
        guard let regex = try? Regex("<\(name)>(.*?)</\(name)>").dotMatchesNewlines(),
              let match = text.firstMatch(of: regex), let raw = match.output[1].substring else { return nil }
        // CDATA içi düz metin sayılır; yoksa etiket temizliği bütün içeriği silerdi.
        var value = String(raw).replacing(/<!\[CDATA\[(.*?)\]\]>/.dotMatchesNewlines()) { String($0.output.1) }
        value = value.replacing(/<[^>]+>/, with: " ")
        for (entity, character) in ["&amp;": "&", "&quot;": "\"", "&apos;": "'", "&lt;": "<", "&gt;": ">", "&nbsp;": " "] {
            value = value.replacingOccurrences(of: entity, with: character)
        }
        value = value.replacing(/&#(\d+);/) { match in
            Int(match.output.1).flatMap(UnicodeScalar.init).map { String(Character($0)) } ?? ""
        }
        return value.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: Hava (Open-Meteo)

    nonisolated static func fetchWeather(for city: PanoCity) async -> Weather? {
        struct Response: Decodable {
            struct Current: Decodable { let temperature_2m: Double; let apparent_temperature: Double; let weather_code: Int; let is_day: Int }
            struct Hourly: Decodable { let time: [String]; let temperature_2m: [Double]; let weather_code: [Int]; let is_day: [Int] }
            struct Daily: Decodable { let time: [String]; let weather_code: [Int]; let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
            let current: Current
            let hourly: Hourly
            let daily: Daily
        }
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(city.latitude)), .init(name: "longitude", value: String(city.longitude)),
            .init(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: city.timeZone), .init(name: "forecast_days", value: "4"),
        ]
        guard let data = await get(components.url!), let response = try? JSONDecoder().decode(Response.self, from: data) else { return nil }

        let stamp = DateFormatter()
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.timeZone = TimeZone(identifier: city.timeZone)
        stamp.dateFormat = "yyyy-MM-dd'T'HH:mm"
        // Önümüzdeki saatten başlayarak üçer saat arayla beş dilim.
        let hourly = response.hourly
        let first = hourly.time.firstIndex { stamp.date(from: $0).map { $0 > Date() } ?? false } ?? 0
        let hours = stride(from: first, to: min(first + 15, hourly.time.count), by: 3).map { index in
            Weather.Hour(time: String(hourly.time[index].suffix(5)), temperature: Int(hourly.temperature_2m[index].rounded()),
                         icon: describe(hourly.weather_code[index], day: hourly.is_day[index] == 1).icon)
        }
        stamp.dateFormat = "yyyy-MM-dd"
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "tr_TR")
        weekday.timeZone = stamp.timeZone
        weekday.dateFormat = "EEEE"
        let daily = response.daily
        let days = daily.time.indices.dropFirst().prefix(3).map { index in
            Weather.Day(name: stamp.date(from: daily.time[index]).map(weekday.string(from:)) ?? "",
                        icon: describe(daily.weather_code[index], day: true).icon,
                        high: Int(daily.temperature_2m_max[index].rounded()), low: Int(daily.temperature_2m_min[index].rounded()))
        }
        let now = describe(response.current.weather_code, day: response.current.is_day == 1)
        return Weather(temperature: Int(response.current.temperature_2m.rounded()), feelsLike: Int(response.current.apparent_temperature.rounded()),
                       text: now.text, icon: now.icon, hours: hours, days: Array(days))
    }

    /// Şehir adından koordinat ve saat dilimi (Open-Meteo geocoding).
    nonisolated static func findCity(_ query: String) async -> PanoCity? {
        struct Response: Decodable {
            struct Place: Decodable { let name: String; let latitude: Double; let longitude: Double; let timezone: String? }
            let results: [Place]?
        }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [.init(name: "name", value: query), .init(name: "count", value: "1"), .init(name: "language", value: "tr")]
        guard let data = await get(components.url!),
              let place = (try? JSONDecoder().decode(Response.self, from: data))?.results?.first else { return nil }
        return PanoCity(name: place.name, latitude: place.latitude, longitude: place.longitude,
                        timeZone: place.timezone ?? TimeZone.current.identifier)
    }

    /// WMO hava kodu → Türkçe ad ve sayfadaki simge.
    private nonisolated static func describe(_ code: Int, day: Bool) -> (text: String, icon: String) {
        switch code {
        case 0: ("Açık", day ? "clear" : "moon")
        case 1: ("Az bulutlu", day ? "partly" : "moon")
        case 2: ("Parçalı bulutlu", day ? "partly" : "cloud")
        case 3: ("Bulutlu", "cloud")
        case 45, 48: ("Sisli", "cloud")
        case 51...57: ("Çisenti", "rain")
        case 61...65: ("Yağmurlu", "rain")
        case 66, 67: ("Dondurucu yağmur", "rain")
        case 71...77: ("Karlı", "snow")
        case 80...82: ("Sağanak yağışlı", "rain")
        case 85, 86: ("Kar sağanağı", "snow")
        case 95...99: ("Gök gürültülü", "storm")
        default: ("—", "cloud")
        }
    }

    // MARK: Piyasa (Yahoo Finance)

    private struct Quote: Sendable {
        let price: Double
        let previous: Double
        let closes: [Double]
    }

    private nonisolated static func quote(_ symbol: String) async -> Quote? {
        guard let today = await chart(symbol, range: "1d", interval: "30m") else { return nil }
        // Gün yeni başladıysa çizilecek nokta yoktur; grafik son günlerin saatlik seyrinden alınır.
        if today.closes.count < 8, let week = await chart(symbol, range: "5d", interval: "60m") {
            return Quote(price: today.price, previous: today.previous, closes: Array(week.closes.suffix(24)))
        }
        return today
    }

    /// `previous`, istenen aralıktan önceki kapanıştır: bir günlük aralıkta dünkü kapanış.
    private nonisolated static func chart(_ symbol: String, range: String, interval: String) async -> Quote? {
        struct Response: Decodable {
            struct Chart: Decodable { let result: [Result]? }
            struct Result: Decodable { let meta: Meta; let indicators: Indicators }
            struct Meta: Decodable { let regularMarketPrice: Double; let chartPreviousClose: Double }
            struct Indicators: Decodable { let quote: [Series] }
            struct Series: Decodable { let close: [Double?]? }
            let chart: Chart
        }
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        components.queryItems = [.init(name: "range", value: range), .init(name: "interval", value: interval)]
        guard let url = components.url, let data = await get(url),
              let result = (try? JSONDecoder().decode(Response.self, from: data))?.chart.result?.first else { return nil }
        return Quote(price: result.meta.regularMarketPrice, previous: result.meta.chartPreviousClose,
                     closes: (result.indicators.quote.first?.close ?? []).compactMap { $0 })
    }

    nonisolated static func fetchMarket() async -> [MarketRow]? {
        async let dollar = quote("USDTRY=X")
        async let euro = quote("EURTRY=X")
        async let ounce = quote("GC=F")
        async let index = quote("XU100.IS")
        let (usd, eur, gold, bist) = await (dollar, euro, ounce, index)

        var rows: [MarketRow] = []
        if let usd { rows.append(row("Dolar", unit: "USD/TRY", quote: usd, digits: 2)) }
        if let eur { rows.append(row("Euro", unit: "EUR/TRY", quote: eur, digits: 2)) }
        if let usd, let gold {
            // Gram altın, ons fiyatı ile dolar kurundan hesaplanır; Kapalıçarşı fiyatından biraz farklı olabilir.
            let perGram = { (ounce: Double, rate: Double) in ounce * rate / 31.1034768 }
            let gram = Quote(price: perGram(gold.price, usd.price), previous: perGram(gold.previous, usd.previous),
                             closes: gold.closes.map { perGram($0, usd.price) })
            rows.append(row("Gram altın", unit: "ons fiyatından", quote: gram, digits: 0))
        }
        if let bist { rows.append(row("BIST 100", unit: "Endeks", quote: bist, digits: 0)) }
        return rows.isEmpty ? nil : rows
    }

    private nonisolated static func row(_ name: String, unit: String, quote: Quote, digits: Int) -> MarketRow {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits
        let value = formatter.string(from: quote.price as NSNumber) ?? ""
        let percent = quote.previous == 0 ? 0 : (quote.price - quote.previous) / quote.previous * 100
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        let change = "%" + (formatter.string(from: abs(percent) as NSNumber) ?? "")

        // Grafik en fazla 24 noktaya seyreltilir ve 0–1 arasına ölçeklenir.
        let step = max(1, (quote.closes.count + 23) / 24)
        let sampled = stride(from: 0, to: quote.closes.count, by: step).map { quote.closes[$0] } + [quote.price]
        let low = sampled.min() ?? 0, high = sampled.max() ?? 0
        let points = sampled.map { high > low ? (($0 - low) / (high - low) * 100).rounded() / 100 : 0.5 }
        return MarketRow(name: name, unit: unit, value: value, change: change, up: percent >= 0, points: points)
    }

    // MARK: YouTube kısayolları

    /// Her kısayolun video kimliğini ve küçük resmini bulur. Kanal adresleri o anki canlı yayına çözülür.
    private nonisolated static func resolve(_ links: [String]) async -> [(id: String?, thumbnail: Data?)] {
        await withTaskGroup(of: (Int, String?, Data?).self) { group in
            for (index, link) in links.prefix(4).enumerated() {
                group.addTask {
                    guard let id = await videoID(for: link) else { return (index, nil, nil) }
                    let thumbnail = await get(URL(string: "https://i.ytimg.com/vi/\(id)/mqdefault.jpg")!)
                    return (index, id, thumbnail)
                }
            }
            var result = [(id: String?, thumbnail: Data?)](repeating: (nil, nil), count: min(links.count, 4))
            for await (index, id, thumbnail) in group { result[index] = (id, thumbnail) }
            return result
        }
    }

    nonisolated static func videoID(for link: String) async -> String? {
        if let video = YouTubeVideo(link: link) { return video.id }
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: text.contains("://") ? text : "https://" + text),
              let host = components.host?.lowercased(), host.hasSuffix("youtube.com") else { return nil }
        // Kanal sayfasının /live adresi, o an yayındaki videoya işaret eder.
        var path = components.path.hasSuffix("/") ? String(components.path.dropLast()) : components.path
        if !path.hasSuffix("/live") { path += "/live" }
        components.path = path
        components.query = nil
        guard let url = components.url, let data = await get(url, headers: ["Accept-Language": "tr"]) else { return nil }
        let html = String(decoding: data, as: UTF8.self)
        return html.firstMatch(of: /<link rel="canonical" href="https:\/\/www\.youtube\.com\/watch\?v=([\w-]{11})"/).map { String($0.output.1) }
    }
}
