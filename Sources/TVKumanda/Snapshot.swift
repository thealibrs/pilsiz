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
            try? await Task.sleep(for: .seconds(4))
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
