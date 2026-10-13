import Foundation
import Observation

struct Channel: Codable, Identifiable, Hashable {
    var id = UUID()
    var number: Int
    var name: String
    var favorite = false
}

/// Kullanıcının kanal listesi. TV kanal adlarını ağdan vermediği için liste Mac'te tutulur.
@MainActor
@Observable
final class ChannelStore {
    private(set) var channels: [Channel] = []
    var lastChannelID: UUID? {
        didSet { UserDefaults.standard.set(lastChannelID?.uuidString, forKey: "lastChannelID") }
    }

    var favorites: [Channel] { channels.filter(\.favorite) }
    var nextFreeNumber: Int { (channels.map(\.number).max() ?? 0) + 1 }

    init() {
        if let data = UserDefaults.standard.data(forKey: "channels"),
           let saved = try? JSONDecoder().decode([Channel].self, from: data) {
            channels = saved
        }
        seedIfNeeded()
        lastChannelID = UserDefaults.standard.string(forKey: "lastChannelID").flatMap(UUID.init)
    }

    /// Kullanıcının TV'sindeki kanal sırası (SmartCenter uygulamasının ekran görüntülerinden, 13.10.2026).
    /// Her sürüm bir kez uygulanır; yalnızca yeni sürümün kanalları mevcut listeyle birleştirilir,
    /// böylece daha önce düzenlenmiş adlar ve favoriler korunur.
    private static let seeds: [(version: Int, channels: [(Int, String)])] = [
        (1, [
            (1, "TRT 1 HD"), (2, "CNN TÜRK HD"), (3, "beIN SPORTS HABER"), (4, "TRT SPOR HD"),
            (5, "TV 100 HD"), (6, "ATV HD"), (7, "TRT 2 HD"), (8, "TRT BELGESEL HD"),
            (9, "KANAL D HD"), (10, "STAR TV HD"), (11, "SHOW HD"), (12, "BEYAZ TV HD"),
            (13, "KANAL 7 HD"), (14, "TV8 HD"), (15, "NOW HD"), (16, "ÜLKE TV HD"),
            (17, "TRT HABER HD"), (19, "A HABER HD"), (21, "TVNET HD"), (23, "HABERTÜRK HD"),
            (26, "NTV HD"), (28, "TGRT HABER HD"), (29, "24 HD"), (30, "HABER GLOBAL HD"),
            (31, "BLOOMBERG HT HD"), (32, "EKOTÜRK HD"), (34, "BENGÜ TÜRK HD"), (35, "HALK TV HD"),
            (36, "FLASH HABER HD"), (37, "AKİT TV HD"), (39, "TRT AVAZ HD"), (40, "TRT KURDİ"),
            (41, "TLC HD"), (42, "DMAX HD"), (43, "TV 2 HD"), (44, "TV 5"),
            (45, "KON TV HD"), (46, "ULUSAL 1 TV"), (47, "TRT ARAPÇA HD"), (48, "TRT WORLD HD"),
            (49, "TGRT"), (50, "KANAL B"),
        ]),
        (2, [
            (51, "TRT TÜRK HD"), (52, "EKOL TV HD"), (53, "MELTEM TV"), (54, "GZT"),
            (55, "KRT TV HD"), (56, "360 HD"), (57, "Bİ KANAL"), (58, "TARIM ORMAN EKRANI HD"),
            (59, "TÜRKSAT TANITIM HD"), (61, "KANAL AVRUPA"), (63, "CNBC-e"), (65, "A2 HD"),
            (66, "DİYANET TV HD"), (68, "TYT TÜRK"), (69, "VAV TV"), (70, "A NEWS HD"),
            (71, "A PARA HD"), (72, "TV8.5 HD"), (73, "TRT SPOR"), (74, "TRT 3 SPOR"),
            (76, "A SPOR HD"), (77, "HT SPOR"), (78, "TİVİBU SPOR HD"), (79, "FB TV"),
            (80, "TRT SPOR YILDIZ"), (81, "TRT ÇOCUK HD"), (82, "MİNİKA ÇOCUK"), (83, "CARTOON NETWORK"),
            (84, "TV4 HD"), (85, "TRT DİYANET ÇOCUK"), (86, "MİNİKA GO"), (87, "STOON TV"),
            (88, "TRT EBA HD"), (89, "TRT GENÇ"), (90, "ZAROK TV"), (91, "TRT DİYANET ÇOCUK"),
            (92, "TRT EBA"), (93, "0 SIFIR TV"), (94, "TÜRKSAT TANITIM"), (95, "TÜRKSAT TANITIM"),
            (96, "TRT BELGESEL"), (97, "TGRT BELGESEL HD"), (98, "ÇİFTÇİ TV"), (99, "AGRO TV"),
            (100, "KÖY TV"), (101, "TRT ULTRA HD TV"), (102, "CEM TV"), (103, "KANAL 3 HD"),
            (104, "TÜRKMENELİ TV HD"), (106, "SEMERKAND HD TV"), (107, "FM TV"), (108, "DOST TV"),
            (109, "TELENEWS"),
        ]),
    ]

    private func seedIfNeeded() {
        let defaults = UserDefaults.standard
        let applied = defaults.integer(forKey: "channelSeedVersion")
        let pending = Self.seeds.filter { $0.version > applied }
        guard !pending.isEmpty else { return }
        for (number, name) in pending.flatMap(\.channels) {
            if let i = channels.firstIndex(where: { $0.number == number }) {
                channels[i].name = name
            } else {
                channels.append(Channel(number: number, name: name))
            }
        }
        save()
        defaults.set(pending.map(\.version).max(), forKey: "channelSeedVersion")
    }

    /// TV'den gelen listeyle birleştirir: yalnızca listede olmayan numaralar eklenir;
    /// mevcut kanalların adları (kullanıcı düzenlemiş olabilir) ve favoriler korunur.
    @discardableResult
    func merge(_ services: [SmartCenter.Service]) -> Int {
        let known = Set(channels.map(\.number))
        let added = services.filter { !known.contains($0.number) }
        guard !added.isEmpty else { return 0 }
        channels += added.map { Channel(number: $0.number, name: $0.name) }
        save()
        return added.count
    }

    func upsert(_ channel: Channel) {
        if let i = channels.firstIndex(where: { $0.id == channel.id }) {
            channels[i] = channel
        } else if let i = channels.firstIndex(where: { $0.number == channel.number }) {
            channels[i].name = channel.name
        } else {
            channels.append(channel)
        }
        save()
    }

    func delete(_ channel: Channel) {
        channels.removeAll { $0.id == channel.id }
        save()
    }

    func toggleFavorite(_ channel: Channel) {
        guard let i = channels.firstIndex(where: { $0.id == channel.id }) else { return }
        channels[i].favorite.toggle()
        save()
    }

    private func save() {
        channels.sort { $0.number < $1.number }
        if let data = try? JSONEncoder().encode(channels) {
            UserDefaults.standard.set(data, forKey: "channels")
        }
    }
}

/// Mac'in gözlemlediği TV kullanım süresi: gün → kategori → saniye.
@MainActor
@Observable
final class ActivityStore {
    static let total = "TV açık"
    static let channelPrefix = "Kanal: "

    private(set) var days: [String: [String: Double]] = [:]

    init() {
        if let data = UserDefaults.standard.data(forKey: "activity"),
           let saved = try? JSONDecoder().decode([String: [String: Double]].self, from: data) {
            days = saved
        }
        mergeChannelKeys()
    }

    /// Kanal anahtarı yalnızca numaradır ("Kanal: 1"); ad değişse de istatistik tek kayıtta kalır.
    static func channelKey(_ number: Int) -> String { channelPrefix + String(number) }

    static func channelNumber(fromKey key: String) -> Int? {
        guard key.hasPrefix(channelPrefix) else { return nil }
        return Int(key.dropFirst(channelPrefix.count).prefix { $0.isNumber })
    }

    /// Eski sürümlerin "Kanal: 1. TRT 1 HD" biçimli anahtarlarını numaraya göre birleştirir.
    private func mergeChannelKeys() {
        var changed = false
        for (day, categories) in days {
            var merged: [String: Double] = [:]
            for (key, seconds) in categories {
                let newKey = Self.channelNumber(fromKey: key).map(Self.channelKey) ?? key
                if newKey != key { changed = true }
                merged[newKey, default: 0] += seconds
            }
            days[day] = merged
        }
        if changed, let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: "activity")
        }
    }

    func record(seconds: Double, app: String?) {
        let key = Self.dayKey(Date())
        var day = days[key, default: [:]]
        day[Self.total, default: 0] += seconds
        if let app { day[app, default: 0] += seconds }
        days[key] = day
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: "activity")
        }
    }

    /// Son `count` günün toplamları, en çoktan aza.
    func totals(lastDays count: Int) -> [String: Double] {
        var result: [String: Double] = [:]
        for offset in 0..<count {
            guard let date = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { continue }
            for (category, seconds) in days[Self.dayKey(date)] ?? [:] { result[category, default: 0] += seconds }
        }
        return result
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}
