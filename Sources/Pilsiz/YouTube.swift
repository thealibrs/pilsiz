import Foundation
import Observation

/// Bir YouTube linkinden çıkarılan video (ve isteğe bağlı başlangıç saniyesi, oynatma listesi).
struct YouTubeVideo: Equatable, Sendable {
    let id: String
    var start = 0
    var listID: String?

    /// youtu.be/ID, youtube.com/watch?v=ID, /shorts/ID, /live/ID, /embed/ID, music.youtube.com ya da yalın 11 karakterlik kimlik.
    init?(link: String) {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isID(text) { id = text; return }
        guard let url = URL(string: text.contains("://") ? text : "https://" + text),
              let host = url.host()?.lowercased(),
              host == "youtu.be" || host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com")
        else { return nil }

        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in query.first { $0.name == name }?.value }
        let parts = url.pathComponents.filter { $0 != "/" }
        let candidate: String? = if host == "youtu.be" {
            parts.first
        } else if let v = value("v") {
            v
        } else if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]) {
            parts[1]
        } else {
            nil
        }
        guard let candidate, Self.isID(candidate) else { return nil }
        id = candidate
        start = Self.seconds(value("t") ?? value("start"))
        listID = value("list")
    }

    var url: URL { URL(string: "https://www.youtube.com/watch?v=\(id)")! }

    private static func isID(_ text: String) -> Bool {
        text.count == 11 && text.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// "90", "90s", "1m30s", "1h2m3s" → saniye.
    private static func seconds(_ text: String?) -> Int {
        guard let text, !text.isEmpty else { return 0 }
        if let plain = Int(text) { return plain }
        var total = 0, number = 0
        for character in text {
            if let digit = character.wholeNumberValue { number = number * 10 + digit; continue }
            switch character {
            case "h": total += number * 3600
            case "m": total += number * 60
            case "s": total += number
            default: break
            }
            number = 0
        }
        return total
    }
}

/// Video adı ve küçük resmi (YouTube oEmbed).
struct YouTubeInfo: Sendable, Equatable {
    let title: String
    let author: String
    let thumbnail: URL?
}

/// TV'deki YouTube uygulamasına video gönderir; telefonlardaki "TV'de izle" ile aynı "Lounge" kanalı.
///
/// Akış: TV, DIAL ile bir eşleştirme koduyla bir kez eşleştirilir ve kalıcı ekran kimliği saklanır.
/// Her gönderimde bu kimlikle erişim anahtarı alınır, Lounge oturumu açılır ve `setPlaylist` gönderilir.
@MainActor
@Observable
final class YouTubeCaster {
    enum Status: Equatable {
        case idle
        case sending
        /// coldStart: YouTube bu gönderimle açıldı; profil ekranı çıkarsa yeniden göndermek gerekebilir.
        case playing(String, coldStart: Bool)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var lastVideo: YouTubeVideo?

    private let defaults = UserDefaults.standard
    private var screenID: String? {
        get { defaults.string(forKey: "youtubeScreenID") }
        set { defaults.set(newValue, forKey: "youtubeScreenID") }
    }

    func play(_ video: YouTubeVideo, on host: String) {
        lastVideo = video
        status = .sending
        Task {
            do {
                let wasRunning = await SmartCenter.isRunning(app: "YouTube", on: host)
                let token = try await loungeToken(host: host, launchIfNeeded: !wasRunning)
                if !wasRunning {
                    // Uygulamanın açılıp Lounge'a bağlanması için zaman tanınır.
                    try await Task.sleep(for: .seconds(6))
                }
                try await Lounge.setPlaylist(video, token: token)
                status = .playing(video.id, coldStart: !wasRunning)
            } catch {
                status = .failed(error.localizedDescription)
            }
        }
    }

    func resend(on host: String) {
        if let lastVideo { play(lastVideo, on: host) }
    }

    /// Kayıtlı ekran için güncel anahtar; ekran yoksa ya da geçersizse DIAL ile yeniden eşleştirir.
    private func loungeToken(host: String, launchIfNeeded: Bool) async throws -> String {
        if let screenID, let token = try? await Lounge.token(screenID: screenID) {
            if launchIfNeeded { try await SmartCenter.launch(app: "YouTube", on: host) }
            return token
        }
        let code = UUID().uuidString.lowercased()
        try await SmartCenter.launch(app: "YouTube", on: host, body: "pairingCode=\(code)&theme=cl")
        for _ in 0..<10 {
            try await Task.sleep(for: .seconds(1.5))
            if let screen = try? await Lounge.screen(pairingCode: code) {
                screenID = screen.id
                return screen.token
            }
        }
        throw TVError.timeout
    }

    static func info(for video: YouTubeVideo) async -> YouTubeInfo? {
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [.init(name: "url", value: video.url.absoluteString), .init(name: "format", value: "json")]
        struct OEmbed: Decodable { let title: String; let author_name: String?; let thumbnail_url: String? }
        guard let (data, _) = try? await URLSession.shared.data(from: components.url!),
              let decoded = try? JSONDecoder().decode(OEmbed.self, from: data) else { return nil }
        return YouTubeInfo(title: decoded.title, author: decoded.author_name ?? "",
                           thumbnail: decoded.thumbnail_url.flatMap(URL.init(string:)))
    }
}

/// YouTube Lounge (uzaktan kumanda) API'si. Belgelenmemiş; açık kaynak istemcilerle (pyytlounge vb.) aynı kullanım.
private enum Lounge {
    private static let base = "https://www.youtube.com/api/lounge"

    static func screen(pairingCode: String) async throws -> (id: String, token: String) {
        struct Response: Decodable { struct Screen: Decodable { let screenId: String; let loungeToken: String }; let screen: Screen }
        let data = try await post("\(base)/pairing/get_screen", form: ["pairing_code": pairingCode])
        let screen = try JSONDecoder().decode(Response.self, from: data).screen
        return (screen.screenId, screen.loungeToken)
    }

    static func token(screenID: String) async throws -> String {
        struct Response: Decodable { struct Screen: Decodable { let loungeToken: String }; let screens: [Screen] }
        let data = try await post("\(base)/pairing/get_lounge_token_batch", form: ["screen_ids": screenID])
        guard let token = try JSONDecoder().decode(Response.self, from: data).screens.first?.loungeToken
        else { throw TVError.badResponse }
        return token
    }

    static func setPlaylist(_ video: YouTubeVideo, token: String) async throws {
        var params = [
            "VER": "8", "CVER": "1", "v": "2", "id": UUID().uuidString.lowercased(),
            "device": "REMOTE_CONTROL", "app": "youtube-desktop", "name": "Pilsiz",
            "loungeIdToken": token, "mdx-version": "3", "theme": "cl",
        ]
        // 1. Oturum aç: yanıtta oturum (SID), gsessionid ve son olay numarası (AID) gelir.
        let bind = String(decoding: try await post(
            "\(base)/bc/bind", query: params.merging(["RID": "1", "t": "1", "zx": zx()]) { $1 }, form: ["count": "0"]
        ), as: UTF8.self)
        guard let sid = bind.firstMatch(of: /\["c","([^"]+)"/)?.output.1,
              let gsid = bind.firstMatch(of: /\["S","([^"]+)"/)?.output.1 else { throw TVError.badResponse }
        let aid = bind.matches(of: /\[(\d+),\[/).last.map { String($0.output.1) } ?? "0"
        params.merge(["RID": "2", "SID": String(sid), "gsessionid": String(gsid), "AID": aid, "zx": zx()]) { $1 }

        // 2. Videoyu oynat.
        _ = try await post("\(base)/bc/bind", query: params, form: [
            "count": "1", "ofs": "0",
            "req0__sc": "setPlaylist",
            "req0_videoId": video.id, "req0_videoIds": video.id,
            "req0_currentTime": String(video.start), "req0_currentIndex": "0",
            "req0_listId": video.listID ?? "", "req0_audioOnly": "false",
            "req0_params": "", "req0_playerParams": "",
        ])
    }

    private static func zx() -> String { String(UUID().uuidString.prefix(12)).lowercased() }

    private static func post(_ address: String, query: [String: String] = [:], form: [String: String]) async throws -> Data {
        var components = URLComponents(string: address)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var body = URLComponents()
        body.queryItems = form.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((body.percentEncodedQuery ?? "").utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw TVError.http(status) }
        return data
    }
}
