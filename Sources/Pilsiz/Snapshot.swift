#if DEBUG
import AppKit
import SwiftUI

/// Geliştirme aracı: PILSIZ_SNAPSHOT=<klasör> ile çalıştırılınca her sekmeyi PNG olarak kaydeder ve çıkar.
@MainActor
enum Snapshot {
    /// Anlık görüntü modu başladıysa true; çağıran paket gerektiren kurulumları (bildirimler) atlamalı.
    static func runIfRequested(_ tv: TVController) -> Bool {
        // PILSIZ_ASK="istek|istek": asistanın anlamasını dener; yalnızca TV'yi değiştirmeyen istekleri uygular.
        if let asks = ProcessInfo.processInfo.environment["PILSIZ_ASK"] {
            Task {
                for _ in 0..<40 where tv.epg.updatedAt == nil { try? await Task.sleep(for: .milliseconds(500)) }
                print("akış:", tv.epg.programmes.count, "kanal anahtarı · güncelleme:", tv.epg.updatedAt.map(String.init(describing:)) ?? "yok",
                      "· TRT 1 şimdi:", tv.epg.schedule(for: "TRT 1 HD").now?.title ?? "-")
                for text in asks.split(separator: "|").map(String.init) {
                    let start = Date()
                    do {
                        guard let intent = try await tv.assistant.interpret(text, tv: tv) else { print(text, "→ model yok"); continue }
                        let elapsed = String(format: "%.1fs", Date().timeIntervalSince(start))
                        print("\(elapsed) “\(text)” → \(intent.action) | kanal: \(intent.channel) | konu: \(intent.topic) | \(intent.amount)")
                        if ["neZaman", "buAksam"].contains(intent.action) {
                            let reply = tv.assistant.perform(intent, tv: tv)
                            print("   ", reply.text)
                            for item in reply.items {
                                print("     ", item.programme.map { clock($0.start) } ?? "", item.channel.name, "·", item.programme?.title ?? "")
                            }
                        } else if intent.action == "kanal" {
                            print("    çözülen kanal:", Assistant.resolveChannel(intent.channel, tv: tv)?.name ?? "YOK")
                        } else if intent.action == "program" {
                            let found = Assistant.find(topic: intent.topic, tv: tv)
                            print("    şimdi:", found.now.first.map { "\($0.0.name) · \($0.1.title)" } ?? "-",
                                  "· sıradaki:", found.upcoming.first.map { "\(dayLabel($0.1.start)) \(clock($0.1.start)) \($0.0.name) · \($0.1.title)" } ?? "-")
                        }
                    } catch {
                        print("“\(text)” → HATA \(error)")
                    }
                }
                exit(0)
            }
            return true
        }
        // PILSIZ_PLAY_YOUTUBE=<link>: YouTube gönderimini uçtan uca dener, sonucu yazdırıp çıkar.
        if let link = ProcessInfo.processInfo.environment["PILSIZ_PLAY_YOUTUBE"] {
            Task {
                for _ in 0..<20 where !tv.isOnline { try? await Task.sleep(for: .milliseconds(500)) }
                guard let video = YouTubeVideo(link: link) else { print("geçersiz link"); exit(1) }
                tv.playYouTube(video)
                for _ in 0..<60 where tv.youtube.status == .sending { try? await Task.sleep(for: .milliseconds(500)) }
                print("youtube:", tv.youtube.status)
                exit(0)
            }
            return true
        }
        guard let dir = ProcessInfo.processInfo.environment["PILSIZ_SNAPSHOT"] else { return false }
        RootView.scrolls = false
        Task {
            // TV durumu ve yayın akışı gelsin diye bekle (en fazla 20 sn).
            for _ in 0..<40 where tv.epg.updatedAt == nil || !tv.isOnline {
                try? await Task.sleep(for: .milliseconds(500))
            }
            // Açılışta başlayan kanal eşitlemesi de bitsin.
            for _ in 0..<20 where tv.channelSync == .syncing {
                try? await Task.sleep(for: .milliseconds(500))
            }
            print("kanal eşitleme:", tv.channelSync)
            try? await Task.sleep(for: .seconds(1))
            for tab in Tab.allCases {
                UserDefaults.standard.set(tab.rawValue, forKey: "tab")
                let renderer = ImageRenderer(content: RootView().environment(tv).environment(PanelState()))
                renderer.scale = 2
                if let tiff = renderer.nsImage?.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(tab.rawValue).png"))
                }
            }
            exit(0)
        }
        return true
    }
}
#endif
