import AppKit
import SwiftUI

/// Uygulama paketinin Resources klasöründeki PNG'leri önbellekli yükler.
@MainActor
enum BundledImage {
    private static var cache: [String: NSImage?] = [:]

    static func named(_ name: String, in subdirectory: String? = nil) -> NSImage? {
        let path = [subdirectory, name].compactMap { $0 }.joined(separator: "/")
        if let cached = cache[path] { return cached }
        var url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory)
        #if DEBUG
        // Paketlenmemiş debug derlemesinde proje klasöründen oku.
        if url == nil {
            let local = URL(fileURLWithPath: "Resources/\(path).png")
            if FileManager.default.fileExists(atPath: local.path) { url = local }
        }
        #endif
        let image = url.flatMap(NSImage.init(contentsOf:))
        cache[path] = image
        return image
    }
}

/// Kanal logoları Resources/Logos klasöründen, kanal adından türetilen anahtarla yüklenir:
/// "TRT 1 HD" → trt1.png, "HABERTÜRK HD" → haberturk.png
@MainActor
enum LogoCatalog {
    static func image(for name: String) -> NSImage? {
        BundledImage.named(NameKey.key(name), in: "Logos")
    }
}

/// Kanal logosu; logo yoksa adın baş harfleriyle renkli bir rozet.
struct ChannelLogo: View {
    let name: String
    var height: CGFloat = 22

    var body: some View {
        if let image = LogoCatalog.image(for: name) {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(height: height)
        } else {
            Text(initials)
                .font(.system(size: height * 0.5, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, height * 0.3)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: height * 0.22, style: .continuous).fill(color.gradient))
        }
    }

    private var initials: String {
        let words = name.split(separator: " ").filter { $0.uppercased() != "HD" }
        return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var color: Color {
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.6)
    }
}
