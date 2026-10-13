import Foundation
import FoundationModels
import Observation

/// Türkçe istekten çıkarılan niyet.
struct TVIntent {
    var action: String
    var channel = ""
    var topic = ""
    var amount = 0
}

/// Cihaz içi modelin ürettiği niyet (Apple Intelligence, macOS 26+).
@available(macOS 26.0, *)
@Generable
struct ModelIntent {
    @Guide(description: "İstenen işlem", .anyOf([
        "kanal", "program", "neZaman", "buAksam",
        "sesSeviye", "sesArttir", "sesAzalt", "sessiz", "kapat", "ac", "bilinmiyor",
    ]))
    var action: String

    @Guide(description: "Yalnızca 'kanal' için: kanal adı ya da numarası, ör. 'TRT 1 HD' veya '15'. Diğerlerinde boş.")
    var channel: String

    @Guide(description: "Yalnızca 'program' ve 'neZaman' için: program adı ya da konu, ör. 'Survivor', 'maç', 'haber'. Diğerlerinde boş.")
    var topic: String

    @Guide(description: "'sesSeviye' için 0-100 hedef seviye; 'sesArttir'/'sesAzalt' için değişim miktarı (belirtilmemişse 5). Diğerlerinde 0.")
    var amount: Int
}

/// Asistanın cevabı: kısa bir cümle ve isteğe bağlı program/kanal satırları.
struct AssistantReply: Equatable {
    struct Item: Identifiable, Equatable {
        let id = UUID()
        let channel: Channel
        let programme: Programme?
    }

    var text: String
    var items: [Item] = []
    var success = true
}

/// "Pilsiz'e söyle": Türkçe doğal dil komutlarını anlayıp TV'de uygular.
/// Anlama cihaz içinde yapılır (önce kurallar, gerekirse Apple'ın cihaz içi dil modeli);
/// kanal ve program bilgisi her zaman uygulamanın kendi verisinden gelir.
@MainActor
@Observable
final class Assistant {
    enum Phase: Equatable { case idle, listening, thinking, done }

    private(set) var phase: Phase = .idle
    private(set) var transcript = ""
    private(set) var reply: AssistantReply?

    var isModelAvailable: Bool {
        if #available(macOS 26.0, *) { return SystemLanguageModel.default.availability == .available }
        return false
    }

    /// Modeli önceden belleğe alır; kullanıcı konuşurken çağrılınca ilk cevap hızlanır.
    func prewarm() {
        if #available(macOS 26.0, *), isModelAvailable {
            LanguageModelSession().prewarm()
        }
    }

    func beginListening() {
        prewarm()
        phase = .listening
        transcript = ""
        reply = nil
    }

    func updateTranscript(_ text: String) {
        transcript = text
    }

    func reset() {
        phase = .idle
        transcript = ""
        reply = nil
    }

    func fail(_ message: String) {
        reply = AssistantReply(text: message, success: false)
        phase = .done
    }

    /// İsteği anlar, uygular ve cevabı yayınlar.
    func handle(_ text: String, tv: TVController) async {
        let request = text.trimmingCharacters(in: .whitespacesAndNewlines)
        transcript = request
        guard !request.isEmpty else { fail("Seni duyamadım."); return }
        phase = .thinking

        do {
            guard let intent = try await interpret(request, tv: tv) else {
                fail("Bu Mac'te Apple Intelligence kapalı; yalnızca “kanal 15”, “TRT 1” gibi basit komutlar çalışır.")
                return
            }
            reply = perform(intent, tv: tv)
            phase = .done
        } catch {
            fail("Bunu anlayamadım, başka türlü söyler misin?")
        }
    }

    /// İsteği niyete çevirir: önce kurallar, sonra cihaz içi model. Model yoksa nil.
    func interpret(_ text: String, tv: TVController) async throws -> TVIntent? {
        if let quick = Self.quickIntent(text, tv: tv) { return quick }
        if #available(macOS 26.0, *), isModelAvailable {
            return try await Self.modelIntent(text, tv: tv)
        }
        return nil
    }

    // MARK: - Anlama

    /// Model gerektirmeyen kalıplar: numara, tam kanal adı, ses, sessiz, aç/kapat, "bu akşam".
    /// Hızlıdır ve modelin güvenlik filtresine takılmaz.
    private static func quickIntent(_ text: String, tv: TVController) -> TVIntent? {
        let lowered = text.lowercased(with: Locale(identifier: "tr_TR"))
        let words = Set(lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let mentionsVolume = lowered.contains("ses")
        if mentionsVolume, let number = lowered.firstMatch(of: /(\d{1,3})/).flatMap({ Int($0.output.1) }) {
            return TVIntent(action: "sesSeviye", amount: number)
        }
        if lowered.contains("sessiz") || (mentionsVolume && (words.contains("kapat") || words.contains("kes"))) {
            return TVIntent(action: "sessiz")
        }
        if mentionsVolume, ["kıs", "azalt", "düşür", "alçalt"].contains(where: lowered.contains) {
            return TVIntent(action: "sesAzalt", amount: lowered.contains("çok") ? 10 : 5)
        }
        if mentionsVolume, ["aç", "arttır", "artır", "yükselt"].contains(where: lowered.contains) {
            return TVIntent(action: "sesArttir", amount: lowered.contains("çok") ? 10 : 5)
        }
        // Yalnızca "televizyonu kapat", "tv'yi aç" gibi cümleler: "Show TV'yi aç" bir kanal isteğidir.
        let filler: Set<String> = ["televizyon", "televizyonu", "tv", "tvyi", "yi", "şunu", "lütfen", "bi", "bir", "mısın", "misin", "artık"]
        let rest = words.subtracting(filler)
        if ["televizyon", "tv"].contains(where: lowered.contains), rest.count == 1, let verb = rest.first {
            if verb.hasPrefix("kapat") { return TVIntent(action: "kapat") }
            if verb.hasPrefix("aç") { return TVIntent(action: "ac") }
        }
        if lowered.contains("bu akşam") || lowered.contains("ne izlesem") || lowered.contains("akşam ne var") {
            return TVIntent(action: "buAksam")
        }
        // "Maçı aç" → izle; "maç hangi kanalda", "maç var mı" → listele.
        if words.contains(where: { $0.hasPrefix("maç") }) {
            let watch = words.contains("aç") || words.contains("açar")
            return TVIntent(action: watch ? "program" : "neZaman", topic: "maç")
        }
        if let match = lowered.wholeMatch(of: /(?:kanal\s*)?(\d{1,4})(?:\.|'?[iıuü]n?[ie]?)?(?:\s*(?:kanal[ıi]?|aç|ac))?/) {
            return TVIntent(action: "kanal", channel: String(match.output.1))
        }
        let key = NameKey.key(lowered.replacingOccurrences(of: "aç", with: ""))
        if !key.isEmpty, tv.channels.channels.contains(where: { NameKey.key($0.name) == key }) {
            return TVIntent(action: "kanal", channel: text)
        }
        return nil
    }

    @available(macOS 26.0, *)
    private static func modelIntent(_ text: String, tv: TVController) async throws -> TVIntent {
        // Modelin bağlam sınırı küçük: tüm kanallar yerine en önemli ~40 kanal verilir.
        let known = importantChannels(tv: tv, limit: 40).map(\.name).joined(separator: ", ")
        let session = LanguageModelSession(instructions: """
        Sen Pilsiz adlı bir televizyon kumandasısın. Kullanıcının Türkçe isteğini tek bir işleme çevir.
        - Belirli bir kanalı açmak ("TRT 1'i aç", "kanal 15", "ATV'ye geç") → kanal
        - Bir programı ya da konuyu izlemek ("Survivor'ı aç", "maçı aç", "haberleri aç") → program
        - "X ne zaman", "X hangi kanalda", "X var mı" → neZaman
        - "Bu akşam ne var", "ne izlesem", "akşam ne var" → buAksam
        - Sesi açmak/artırmak → sesArttir; kısmak/azaltmak → sesAzalt; "sesi 20 yap" → sesSeviye
        - "Sessize al", "sesi kapat" → sessiz; "televizyonu kapat" → kapat; "televizyonu aç" → ac
        - Anlamsız ya da TV ile ilgisiz (hava durumu, saat vb.) → bilinmiyor
        Örnekler:
        "maç hangi kanalda" → neZaman, konu "maç"
        "Kızılcık Şerbeti ne zaman" → neZaman, konu "Kızılcık Şerbeti"
        "haberleri aç" → program, konu "haber"
        "Survivor'ı aç" → program, konu "Survivor"
        "Show TV'yi aç" → kanal, kanal "SHOW HD"
        Kanallardan bazıları: \(known)
        """)
        let intent = try await session.respond(to: text, generating: ModelIntent.self, options: .init(temperature: 0)).content
        return TVIntent(action: intent.action, channel: intent.channel, topic: intent.topic, amount: intent.amount)
    }

    // MARK: - Uygulama

    func perform(_ intent: TVIntent, tv: TVController) -> AssistantReply {
        switch intent.action {
        case "kanal":
            guard let channel = Self.resolveChannel(intent.channel, tv: tv) else {
                return AssistantReply(text: "“\(intent.channel)” adında bir kanal bulamadım.", success: false)
            }
            tv.switchTo(channel)
            return AssistantReply(text: "\(channel.name) açılıyor.", items: [.init(channel: channel, programme: tv.epg.schedule(for: channel.name).now)])

        case "program":
            return watch(topic: intent.topic.isEmpty ? intent.channel : intent.topic, tv: tv)

        case "neZaman":
            var (now, upcoming) = Self.find(topic: intent.topic, tv: tv)
            if now.isEmpty, upcoming.isEmpty, !intent.channel.isEmpty {
                // Model konuyu bazen kanal alanına yazıyor.
                (now, upcoming) = Self.find(topic: intent.channel, tv: tv)
            }
            let items = (now + upcoming).prefix(4).map { AssistantReply.Item(channel: $0.0, programme: $0.1) }
            guard !items.isEmpty else {
                return AssistantReply(text: "Yayın akışında “\(intent.topic)” bulamadım.", success: false)
            }
            return AssistantReply(text: now.isEmpty ? "\(intent.topic) yakında:" : "\(intent.topic) şu an yayında:", items: Array(items))

        case "buAksam":
            let items = Self.tonight(tv: tv).map { AssistantReply.Item(channel: $0.0, programme: $0.1) }
            guard !items.isEmpty else { return AssistantReply(text: "Bu akşam için yayın akışı bulamadım.", success: false) }
            return AssistantReply(text: "Bu akşam senin kanallarında:", items: items)

        case "sesSeviye":
            tv.setVolume(intent.amount)
            return AssistantReply(text: "Ses \(min(100, max(0, intent.amount))) yapıldı.")
        case "sesArttir":
            tv.setVolume(tv.volume + max(1, intent.amount == 0 ? 5 : abs(intent.amount)))
            return AssistantReply(text: "Ses açıldı: \(tv.volume).")
        case "sesAzalt":
            tv.setVolume(tv.volume - max(1, intent.amount == 0 ? 5 : abs(intent.amount)))
            return AssistantReply(text: "Ses kısıldı: \(tv.volume).")
        case "sessiz":
            tv.press(.mute)
            return AssistantReply(text: tv.isMuted ? "Sessize alındı." : "Ses açıldı.")
        case "kapat":
            guard tv.isOnline else { return AssistantReply(text: "TV zaten kapalı.") }
            tv.power()
            return AssistantReply(text: "TV kapatılıyor.")
        case "ac":
            guard !tv.isOnline else { return AssistantReply(text: "TV zaten açık.") }
            tv.power()
            return AssistantReply(text: "TV açılıyor.")
        default:
            return AssistantReply(text: "Bunu anlayamadım. “TRT 1'i aç”, “sesi kıs” ya da “bu akşam ne var” diyebilirsin.", success: false)
        }
    }

    /// Program ya da konu şu an yayındaysa o kanala geçer; değilse sıradaki yayına hatırlatıcı kurar.
    private func watch(topic: String, tv: TVController) -> AssistantReply {
        let (now, upcoming) = Self.find(topic: topic, tv: tv)
        if let (channel, programme) = now.first {
            tv.switchTo(channel)
            return AssistantReply(text: "\(programme.title) açılıyor · \(channel.name)", items: [.init(channel: channel, programme: programme)])
        }
        // "Haberleri aç" gibi konular bir kanal adıyla da eşleşebilir.
        if let channel = Self.resolveChannel(Self.stem(NameKey.key(topic)), tv: tv) {
            tv.switchTo(channel)
            return AssistantReply(text: "\(channel.name) açılıyor.", items: [.init(channel: channel, programme: tv.epg.schedule(for: channel.name).now)])
        }
        if let (channel, programme) = upcoming.first {
            if !tv.reminders.isSet(channel: channel, programme: programme) {
                tv.reminders.toggle(channel: channel, programme: programme)
            }
            return AssistantReply(
                text: "\(programme.title) şu an yayında değil; \(dayLabel(programme.start).lowercased(with: Locale(identifier: "tr_TR"))) \(clock(programme.start))'de \(channel.name)'de. Hatırlatıcı kurdum.",
                items: [.init(channel: channel, programme: programme)]
            )
        }
        return AssistantReply(text: "Yayın akışında “\(topic)” bulamadım.", success: false)
    }

    // MARK: - Veri

    /// Numara, tam ad, ad öneki ya da ad içinde geçme; eşitlikte düşük numaralı (ana) kanal.
    static func resolveChannel(_ text: String, tv: TVController) -> Channel? {
        let channels = tv.channels.channels
        if let number = Int(text.filter(\.isNumber)), text.allSatisfy({ $0.isNumber || $0.isWhitespace }) {
            return channels.first { $0.number == number }
        }
        let key = NameKey.key(text)
        guard !key.isEmpty else { return nil }
        let keyed = channels.map { (channel: $0, key: NameKey.key($0.name)) }
        return keyed.first { $0.key == key }?.channel
            ?? keyed.filter { $0.key.hasPrefix(key) || key.hasPrefix($0.key) }.min { $0.channel.number < $1.channel.number }?.channel
            ?? keyed.filter { $0.key.contains(key) }.min { $0.channel.number < $1.channel.number }?.channel
    }

    /// Konuyu yayın akışında arar: şu an yayında olanlar ve önümüzdeki 7 gün.
    static func find(topic: String, tv: TVController) -> (now: [(Channel, Programme)], upcoming: [(Channel, Programme)]) {
        let key = stem(NameKey.key(topic))
        // Modelin bazen konu yerine yazdığı anlamsız kelimeler.
        guard key.count >= 2, !["kanal", "kanalda", "program", "ne", "zaman", "yayin"].contains(key) else { return ([], []) }
        let isMatch = key.hasPrefix("mac") || key == "futbol"
        let date = Date()
        var now: [(Channel, Programme)] = []
        var upcoming: [(Channel, Programme)] = []
        // Aynı yayını veren kanallar (ör. iki numaradaki TRT Spor) bir kez listelenir.
        var seen: Set<String> = []
        for channel in importantChannels(tv: tv, limit: .max) {
            let sports = NameKey.key(channel.name).contains("spor") || NameKey.key(channel.name).contains("bein")
            let matches: (Programme) -> Bool = { programme in
                let words = NameKey.tokens(programme.title)
                if isMatch {
                    // "Maç Özel", "maçı" eşleşir, "Maceracı" eşleşmez; spor kanallarında "Takım A - Takım B" de maçtır.
                    return words.contains { ["mac", "maci", "macin", "maclar", "maclari"].contains($0) }
                        || (sports && (programme.title.contains(" - ") || programme.title.contains(" – ")))
                }
                // Kısa kelimeler yalnızca kelime başında eşleşir ("haber" → "Gece Haberleri").
                return key.count >= 5 ? NameKey.key(programme.title).contains(key) : words.contains { $0.hasPrefix(key) }
            }
            let schedule = tv.epg.schedule(for: channel.name, at: date)
            if let current = schedule.now, matches(current), seen.insert("\(current.title)\(current.start)").inserted {
                now.append((channel, current))
            }
            if let next = tv.epg.upcoming(for: channel.name, from: date, limit: 200).first(where: matches),
               seen.insert("\(next.title)\(next.start)").inserted {
                upcoming.append((channel, next))
            }
        }
        return (now, upcoming.sorted { $0.1.start < $1.1.start })
    }

    /// Akşamın öne çıkanları: önemli kanallarda 19:00'dan (ya da şimdiden) gece yarısına başlayan uzun programlar.
    static func tonight(tv: TVController) -> [(Channel, Programme)] {
        let calendar = Calendar.current
        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let windowStart: Date
        let windowEnd: Date
        if hour < 6 || hour >= 22 {
            // Gece: sıradaki üç saat.
            windowStart = now.addingTimeInterval(-30 * 60)
            windowEnd = now.addingTimeInterval(3 * 3600)
        } else {
            windowStart = max(now.addingTimeInterval(-30 * 60), calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now) ?? now)
            windowEnd = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: now) ?? now
        }
        var picks: [(Channel, Programme)] = []
        var seen: Set<String> = []
        for channel in importantChannels(tv: tv, limit: 16) {
            let candidates = [tv.epg.schedule(for: channel.name, at: now).now].compactMap { $0 }
                + tv.epg.upcoming(for: channel.name, from: now, limit: 200)
            if let programme = candidates.first(where: {
                $0.start >= windowStart && $0.start <= windowEnd && $0.stop.timeIntervalSince($0.start) >= 40 * 60
            }), seen.insert("\(programme.title)\(programme.start)").inserted {
                picks.append((channel, programme))
            }
        }
        return Array(picks.prefix(8)).sorted { $0.1.start < $1.1.start }
    }

    /// Türkçe çekim eklerini kaba biçimde atar: "haberleri" → "haber", "survivori" → "survivor", "maci" → "mac".
    static func stem(_ key: String) -> String {
        for suffix in ["leri", "lari", "ler", "lar", "yi", "yu", "ni", "nu", "i", "u"] where key.hasSuffix(suffix) && key.count - suffix.count >= 3 {
            return String(key.dropLast(suffix.count))
        }
        return key
    }

    /// Favoriler, en çok izlenenler, sonra numara sırası.
    static func importantChannels(tv: TVController, limit: Int) -> [Channel] {
        let watched = tv.activity.totals(lastDays: 30)
        func score(_ channel: Channel) -> Double {
            (channel.favorite ? 1_000_000 : 0) + (watched[ActivityStore.channelKey(channel.number)] ?? 0) - Double(channel.number)
        }
        return Array(tv.channels.channels.sorted { score($0) > score($1) }.prefix(limit))
    }
}
