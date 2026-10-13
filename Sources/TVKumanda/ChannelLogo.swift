import AppKit
import SwiftUI

/// Kanal logoları uygulama paketindeki Resources/Logos klasöründen, kanal adından türetilen anahtarla yüklenir:
/// "TRT 1 HD" → trt1.png, "HABERTÜRK HD" → haberturk.png
@MainActor
enum LogoCatalog {
    private static var cache: [String: NSImage?] = [:]

    static func key(for name: String) -> String {
        // Türkçe yerel ayarı "I"yı "ı"ya çevirdiği için dil bağımsız katlanır; dosya adları ASCII.
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
            .replacingOccurrences(of: "ı", with: "i")
        return folded
            .split { !$0.isLetter && !$0.isNumber }
            .filter { $0 != "hd" }
            .joined()
    }

    static func image(for name: String) -> NSImage? {
        let key = key(for: name)
        if let cached = cache[key] { return cached }
        var url = Bundle.main.url(forResource: key, withExtension: "png", subdirectory: "Logos")
        #if DEBUG
        // Paketlenmemiş debug derlemesinde proje klasöründen oku.
        if url == nil {
            let local = URL(fileURLWithPath: "Resources/Logos/\(key).png")
            if FileManager.default.fileExists(atPath: local.path) { url = local }
        }
        #endif
        let image = url.flatMap(NSImage.init(contentsOf:))
        cache[key] = image
        return image
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
