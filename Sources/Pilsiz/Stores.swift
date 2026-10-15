import Foundation
import Observation

struct Channel: Codable, Identifiable, Hashable {
    var id = UUID()
    var number: Int
    var name: String
    var favorite = false
}

/// Kullanıcının kanal listesi. Kanallar TV'den alınır (`TVController.syncChannels`);
/// düzenlenen adlar ve favoriler Mac'te tutulur.
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
        lastChannelID = UserDefaults.standard.string(forKey: "lastChannelID").flatMap(UUID.init)
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
