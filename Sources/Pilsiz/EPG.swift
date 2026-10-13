import Foundation
import Observation

/// Kanal adlarını karşılaştırılabilir anahtara çevirir: "STAR TV HD" → "startv".
/// Logo dosya adları ve yayın akışı eşleştirmesi aynı kuralı kullanır.
enum NameKey {
    static func tokens(_ name: String) -> [String] {
        // Türkçe yerel ayarı "I"yı "ı"ya çevirdiği için dil bağımsız katlanır.
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0 != "hd" }
    }

    static func key(_ name: String) -> String { tokens(name).joined() }

    /// Yayın akışında adı farklı geçen kanallar.
    private static let aliases = ["trtarapca": "trtarabi", "stoontv": "spacetoon"]

    /// En kesin eşleşmeden en gevşeğe aday anahtarlar ("startv", "star").
    static func candidates(_ name: String) -> [String] {
        let all = tokens(name)
        var keys = [all.joined()]
        if let alias = aliases[keys[0]] { keys.append(alias) }
        let withoutTV = all.filter { $0 != "tv" }.joined()
        // "TV 5" → "5" gibi tek başına sayı kalan anahtarlar başka kanallarla çakışır.
        if !withoutTV.isEmpty, !withoutTV.allSatisfy(\.isNumber), withoutTV != keys[0] { keys.append(withoutTV) }
        return keys
    }
}

struct Programme: Sendable, Hashable {
    let start: Date
    let stop: Date
    let title: String

    func progress(at date: Date) -> Double {
        let total = stop.timeIntervalSince(start)
        return total > 0 ? min(1, max(0, date.timeIntervalSince(start) / total)) : 0
    }
}

/// Türksat kanallarının 7 günlük yayın akışı (XMLTV), Mac'te önbelleğe alınır.
@MainActor
@Observable
final class EPGStore {
    /// Kaynaklar, öncelik sırasıyla; ilk kaynakta olan kanal sonrakilerden alınmaz.
    /// - epgshare01: 178 kanal, 3 gün (gzip).
    /// - trology85/iptv-epg-turkey: aynı yayın verisi, yalnızca o gün; ilkinde olmayan kanalları (ör. NOW) tamamlar.
    private static let sources: [(name: String, url: URL)] = [
        ("epgshare01", URL(string: "https://epgshare01.online/epgshare01/epg_ripper_TR1.xml.gz")!),
        ("trology", URL(string: "https://raw.githubusercontent.com/trology85/iptv-epg-turkey/main/epg/turksat_epg.xml")!),
    ]
    private static let maxAge: TimeInterval = 6 * 3600

    private(set) var programmes: [String: [Programme]] = [:]
    private(set) var updatedAt: Date?

    private let directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Pilsiz", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    init() {
        Task { await run() }
    }

    /// Kanalda şu an yayında olan ve sıradaki program.
    func schedule(for channelName: String, at date: Date = Date()) -> (now: Programme?, next: Programme?) {
        guard let list = NameKey.candidates(channelName).lazy.compactMap({ self.programmes[$0] }).first,
              let index = list.firstIndex(where: { $0.stop > date }) else { return (nil, nil) }
        let upcoming = list[index]
        guard upcoming.start <= date else { return (nil, upcoming) }
        return (upcoming, list.indices.contains(index + 1) ? list[index + 1] : nil)
    }

    /// Kanalın şu andan itibaren yayınlanacak programları.
    func upcoming(for channelName: String, from date: Date = Date(), limit: Int = 8) -> [Programme] {
        guard let list = NameKey.candidates(channelName).lazy.compactMap({ self.programmes[$0] }).first else { return [] }
        return Array(list.filter { $0.start > date }.prefix(limit))
    }

    private func cacheURL(_ name: String) -> URL { directory.appendingPathComponent("epg-\(name).xml") }

    private func run() async {
        await reload(cachedFiles())
        while true {
            let stale = Date().timeIntervalSince(updatedAt ?? .distantPast) > Self.maxAge
            // Gün değişince hemen tazele: kaynaklar günlük güncelleniyor.
            let newDay = updatedAt.map { !Calendar.current.isDateInToday($0) } ?? true
            if stale || newDay { await download() }
            try? await Task.sleep(for: .seconds(1800))
        }
    }

    private func cachedFiles() -> [Data] {
        Self.sources.compactMap { try? Data(contentsOf: cacheURL($0.name)) }
    }

    private func download() async {
        var downloaded = false
        for source in Self.sources {
            guard let (data, response) = try? await URLSession.shared.data(from: source.url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            let xml = Gzip.isCompressed(data) ? Gzip.decompress(data) : data
            guard let xml else { continue }
            try? xml.write(to: cacheURL(source.name), options: .atomic)
            downloaded = true
        }
        if downloaded {
            await reload(cachedFiles())
            updatedAt = Date()
        }
    }

    private func reload(_ files: [Data]) async {
        guard !files.isEmpty else { return }
        let merged = await Task.detached(priority: .utility) {
            var result: [String: [Programme]] = [:]
            for file in files {
                for (key, list) in XMLTVParser.parse(file) where result[key] == nil { result[key] = list }
            }
            return result
        }.value
        guard !merged.isEmpty else { return }
        programmes = merged
        if updatedAt == nil {
            updatedAt = (try? FileManager.default.attributesOfItem(atPath: cacheURL(Self.sources[0].name).path))?[.modificationDate] as? Date
        }
    }
}

/// gzip açıcı: macOS'un yerleşik DEFLATE çözücüsü (Apple'ın "zlib" algoritması ham DEFLATE'tir).
enum Gzip {
    static func isCompressed(_ data: Data) -> Bool {
        data.count > 2 && data[data.startIndex] == 0x1f && data[data.startIndex + 1] == 0x8b
    }

    static func decompress(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[2] == 8 else { return nil }
        let flags = bytes[3]
        var index = 10
        if flags & 0x04 != 0 { index += 2 + (Int(bytes[index]) | Int(bytes[index + 1]) << 8) }  // FEXTRA
        if flags & 0x08 != 0 { while index < bytes.count, bytes[index] != 0 { index += 1 }; index += 1 }  // FNAME
        if flags & 0x10 != 0 { while index < bytes.count, bytes[index] != 0 { index += 1 }; index += 1 }  // FCOMMENT
        if flags & 0x02 != 0 { index += 2 }  // FHCRC
        guard index < bytes.count - 8 else { return nil }
        let deflated = Data(bytes[index..<(bytes.count - 8)])
        return try? (deflated as NSData).decompressed(using: .zlib) as Data
    }
}

/// XMLTV belgesini kanal anahtarı → başlangıca göre sıralı programlar sözlüğüne çevirir.
enum XMLTVParser {
    static func parse(_ data: Data) -> [String: [Programme]] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()

        var result: [String: [Programme]] = [:]
        for (id, list) in delegate.programmes {
            // Akışta bazı kanallar iki kez yer alıyor; aynı saatte başlayan kopyalar atılır.
            var sorted: [Programme] = []
            for programme in list.sorted(by: { $0.start < $1.start }) where sorted.last?.start != programme.start {
                sorted.append(programme)
            }
            // Kesin anahtar önce yazılır; gevşek anahtar yalnızca boşsa doldurulur.
            for key in NameKey.candidates(delegate.names[id] ?? id) where result[key] == nil {
                result[key] = sorted
            }
        }
        return result
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var names: [String: String] = [:]
        var programmes: [String: [Programme]] = [:]

        private var text = ""
        private var channelID: String?
        private var programme: (channel: String, start: Date, stop: Date)?
        private var title: String?
        private let formatter: DateFormatter = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyyMMddHHmmss Z"
            return f
        }()

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch element {
            case "channel":
                channelID = attributes["id"]
            case "programme":
                if let channel = attributes["channel"],
                   let start = attributes["start"].flatMap(formatter.date(from:)),
                   let stop = attributes["stop"].flatMap(formatter.date(from:)) {
                    programme = (channel, start, stop)
                }
                title = nil
            default:
                break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            switch element {
            case "display-name":
                if let channelID, names[channelID] == nil { names[channelID] = value }
            case "channel":
                channelID = nil
            case "title":
                if title == nil { title = value }
            case "programme":
                if let programme, let title, !title.isEmpty, title != "-" {
                    programmes[programme.channel, default: []].append(
                        Programme(start: programme.start, stop: programme.stop, title: title)
                    )
                }
                programme = nil
            default:
                break
            }
            text = ""
        }
    }
}
