#if DEBUG
import AppKit
import SwiftUI

/// Geliştirme aracı: PILSIZ_SNAPSHOT=<klasör> ile çalıştırılınca her sekmeyi PNG olarak kaydeder ve çıkar.
@MainActor
enum Snapshot {
    /// Anlık görüntü modu başladıysa true; çağıran paket gerektiren kurulumları (bildirimler) atlamalı.
    static func runIfRequested(_ tv: TVController) -> Bool {
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
