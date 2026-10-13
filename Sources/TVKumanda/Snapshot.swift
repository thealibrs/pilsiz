#if DEBUG
import AppKit
import SwiftUI

/// Geliştirme aracı: TVKUMANDA_SNAPSHOT=<klasör> ile çalıştırılınca her sekmeyi PNG olarak kaydeder ve çıkar.
@MainActor
enum Snapshot {
    static func runIfRequested(_ tv: TVController) {
        guard let dir = ProcessInfo.processInfo.environment["TVKUMANDA_SNAPSHOT"] else { return }
        RootView.scrolls = false
        Task {
            // TV durumu ve yayın akışı gelsin diye bekle (en fazla 20 sn).
            for _ in 0..<40 where tv.epg.updatedAt == nil || !tv.isOnline {
                try? await Task.sleep(for: .milliseconds(500))
            }
            try? await Task.sleep(for: .seconds(1))
            for tab in Tab.allCases {
                UserDefaults.standard.set(tab.rawValue, forKey: "tab")
                let renderer = ImageRenderer(content: RootView().environment(tv))
                renderer.scale = 2
                if let tiff = renderer.nsImage?.tiffRepresentation,
                   let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(tab.rawValue).png"))
                }
            }
            exit(0)
        }
    }
}
#endif
