import SwiftUI

// MARK: - Kumanda

struct RemoteTab: View {
    var body: some View {
        RemoteBody()
    }
}

/// TV'nin kendi kumandasına (Vestel) benzeyen, daha kısa tutulmuş kumanda gövdesi.
private struct RemoteBody: View {
    @Environment(TVController.self) private var tv
    private let width: CGFloat = 208

    var body: some View {
        VStack(spacing: 9) {
            topRow
            digits
            rockers
            NavigationPad()
            apps
            colorKeys
            media
            Text("Pilsiz")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.18))
                .padding(.top, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .frame(width: width)
        .background(plastic(RoundedRectangle(cornerRadius: 38, style: .continuous)))
        .frame(maxWidth: .infinity)
    }

    /// Parlak siyah plastik gövde.
    private func plastic(_ shape: some Shape) -> some View {
        shape
            .fill(LinearGradient(colors: [Color(white: 0.15), Color(white: 0.06)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.09), .clear], startPoint: .topLeading, endPoint: .center)))
            .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 12, y: 6)
    }

    // MARK: Satırlar

    private var topRow: some View {
        HStack(spacing: 8) {
            RemoteKeyCap(width: 38, height: 25, help: "Güç", action: { tv.press(.power) }) {
                Image(systemName: "power").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
            }
            Spacer()
            RemoteKeyCap(width: 28, height: 20, help: "Menü", action: { tv.press(.menu) }) {
                Image(systemName: "gearshape").font(.system(size: 10, weight: .semibold))
            }
            RemoteKeyCap(width: 28, height: 20, help: "Önceki kanal", action: { tv.send(code: 1034) }) {
                Image(systemName: "arrow.left.arrow.right").font(.system(size: 10, weight: .semibold))
            }
            Spacer()
            RemoteKeyCap(width: 38, height: 25, help: "Kaynak", action: { tv.press(.source) }) {
                Image(systemName: "rectangle.portrait.and.arrow.right").font(.system(size: 12, weight: .semibold))
            }
        }
    }

    private var digits: some View {
        Grid(horizontalSpacing: 7, verticalSpacing: 6) {
            ForEach(0..<3) { row in
                GridRow { ForEach(1...3, id: \.self) { col in digit(row * 3 + col) } }
            }
            GridRow {
                RemoteKeyCap(height: 22, help: "Altyazı", action: { tv.press(.subtitle) }) {
                    HStack(spacing: 3) {
                        Text("LANG").font(.system(size: 7.5, weight: .bold))
                        Image(systemName: "captions.bubble").font(.system(size: 9))
                    }
                }
                digit(0)
                RemoteKeyCap(height: 22, help: "TV listesi", action: { tv.send(code: 1045) }) {
                    Image(systemName: "list.bullet").font(.system(size: 11, weight: .semibold))
                }
            }
        }
    }

    private func digit(_ n: Int) -> some View {
        let letters = ["_", ".,@", "abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz"][n]
        return RemoteKeyCap(height: 22, help: "\(n)", action: { tv.press(.digit(n)) }) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(n)").font(.system(size: 13, weight: .semibold, design: .rounded))
                Text(letters).font(.system(size: 6.5, weight: .medium)).foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    /// Ses ve kanal tuşları arasında sessiz ve ana ekran.
    private var rockers: some View {
        HStack {
            Rocker(help: ("Sesi aç", "Sesi kıs"), up: { tv.press(.volumeUp) }, down: { tv.press(.volumeDown) }) {
                Image(systemName: "plus").font(.system(size: 12, weight: .bold))
            } middle: {
                Text(tv.isMuted ? "—" : "\(tv.volume)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.15), value: tv.volume)
            } downLabel: {
                Image(systemName: "minus").font(.system(size: 12, weight: .bold))
            }
            Spacer()
            VStack(spacing: 8) {
                RemoteKeyCap(width: 42, height: 27, help: tv.isMuted ? "Sesi aç" : "Sessize al", action: { tv.press(.mute) }) {
                    Image(systemName: tv.isMuted ? "speaker.slash.fill" : "speaker.slash")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tv.isMuted ? Theme.accent : .white)
                }
                RemoteKeyCap(width: 42, height: 37, help: "Ana ekran", action: { tv.press(.home) }) {
                    Image(systemName: "house.fill").font(.system(size: 17)).foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            Rocker(help: ("Kanal +", "Kanal −"), repeats: true, up: { tv.press(.channelUp) }, down: { tv.press(.channelDown) }) {
                Image(systemName: "chevron.up").font(.system(size: 12, weight: .bold))
            } middle: {
                Text("P").font(.system(size: 13, weight: .semibold, design: .rounded))
            } downLabel: {
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .bold))
            }
        }
        .padding(.horizontal, 2)
    }

    private var apps: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 6) {
            GridRow {
                appKey("netflix", fill: .white) {
                    Text("NETFLIX").font(.system(size: 11, weight: .heavy)).fontWidth(.condensed)
                        .foregroundStyle(Color(red: 0.86, green: 0.07, blue: 0.11))
                }
                appKey("youtube", fill: Color(red: 0.86, green: 0.1, blue: 0.1)) {
                    Text("YouTube").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                }
            }
            GridRow {
                appKey("browser", fill: Color(white: 0.92)) {
                    Label("İnternet", systemImage: "globe").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(white: 0.15))
                }
                appKey("prime", fill: Color(red: 0.0, green: 0.62, blue: 0.86)) {
                    Text("prime video").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                }
            }
        }
    }

    private func appKey(_ id: String, fill: Color, @ViewBuilder label: () -> some View) -> some View {
        let app = TVApp.all.first { $0.id == id }
        let face = label()
        return KeyButton(action: { if let app { tv.open(app) } }, help: app?.name ?? id) {
            face
                .frame(maxWidth: .infinity)
                .frame(height: 21)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill.gradient))
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
        }
    }

    private var colorKeys: some View {
        HStack(spacing: 8) {
            ForEach([(RemoteKey.red, Color.red, "Kırmızı"), (.green, .green, "Yeşil"), (.yellow, .yellow, "Sarı"), (.blue, .blue, "Mavi")], id: \.0) { key, color, name in
                KeyButton(action: { tv.press(key) }, help: "\(name) tuş") {
                    Capsule().fill(color.gradient)
                        .frame(maxWidth: .infinity).frame(height: 11)
                        .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                }
            }
        }
    }

    private var media: some View {
        HStack(spacing: 7) {
            mediaKey("backward.fill", "Geri sar", .rewind)
            mediaKey("play.fill", "Oynat", .play)
            mediaKey("pause.fill", "Duraklat", .pause)
            mediaKey("stop.fill", "Durdur", .stop)
            mediaKey("forward.fill", "İleri sar", .forward)
        }
    }

    private func mediaKey(_ symbol: String, _ help: String, _ key: RemoteKey) -> some View {
        RemoteKeyCap(height: 19, help: help, action: { tv.press(key) }) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
        }
    }
}

/// Kumandadaki koyu, hafif kabarık tuş.
private struct RemoteKeyCap<Label: View>: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 7
    var repeats = false
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        KeyButton(action: action, repeats: repeats, help: help) {
            label()
                .foregroundStyle(.white)
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : nil)
                .background(RemoteKeyFace(shape: RoundedRectangle(cornerRadius: radius, style: .continuous)))
        }
    }
}

private struct RemoteKeyFace<S: Shape>: View {
    let shape: S

    var body: some View {
        shape
            .fill(LinearGradient(colors: [Color(white: 0.24), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
            .overlay(shape.stroke(.white.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.5), radius: 1.5, y: 1.5)
    }
}

/// Ses (+/−) ve kanal (P) için dikey çift tuş.
private struct Rocker<Up: View, Middle: View, Down: View>: View {
    let help: (up: String, down: String)
    var repeats = true
    let up: () -> Void
    let down: () -> Void
    @ViewBuilder let upLabel: () -> Up
    @ViewBuilder let middle: () -> Middle
    @ViewBuilder let downLabel: () -> Down

    var body: some View {
        VStack(spacing: 0) {
            half(upLabel, help.up, up)
            middle().frame(height: 16)
            half(downLabel, help.down, down)
        }
        .foregroundStyle(.white)
        .frame(width: 38, height: 80)
        .background(RemoteKeyFace(shape: Capsule()))
    }

    private func half(_ label: () -> some View, _ help: String, _ action: @escaping () -> Void) -> some View {
        let face = label()
        return KeyButton(action: action, repeats: repeats, help: help) {
            face.frame(width: 38, height: 32)
        }
    }
}

/// Ok tuşları ve OK; köşelerde rehber, bilgi, geri ve çıkış tuşları.
private struct NavigationPad: View {
    @Environment(TVController.self) private var tv
    private let height: CGFloat = 146
    private let ring: CGFloat = 116
    private let gap: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let w = (proxy.size.width - gap) / 2
            let h = (height - gap) / 2
            ZStack {
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        corner(.topLeading, w, h, help: "Yayın akışı", key: .epg) {
                            Image(systemName: "list.bullet.rectangle").font(.system(size: 11, weight: .semibold))
                        }
                        corner(.topTrailing, w, h, help: "Bilgi", key: .info) {
                            Image(systemName: "info").font(.system(size: 12, weight: .bold))
                        }
                    }
                    HStack(spacing: gap) {
                        corner(.bottomLeading, w, h, help: "Geri", key: .back) {
                            Text("BACK").font(.system(size: 8.5, weight: .bold))
                        }
                        corner(.bottomTrailing, w, h, help: "Çıkış", key: .exit) {
                            Text("EXIT").font(.system(size: 8.5, weight: .bold))
                        }
                    }
                }
                dpad
            }
            .frame(width: proxy.size.width, height: height)
        }
        .frame(height: height)
    }

    /// Dış köşesi yuvarlatılmış çeyrek tuş; yazısı köşeye yaslanır.
    private func corner(_ alignment: Alignment, _ w: CGFloat, _ h: CGFloat, help: String, key: RemoteKey,
                        @ViewBuilder label: () -> some View) -> some View {
        let r: CGFloat = 26
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: alignment == .topLeading ? r : 6,
            bottomLeadingRadius: alignment == .bottomLeading ? r : 6,
            bottomTrailingRadius: alignment == .bottomTrailing ? r : 6,
            topTrailingRadius: alignment == .topTrailing ? r : 6,
            style: .continuous
        )
        let face = label()
        return KeyButton(action: { tv.press(key) }, help: help) {
            face
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .frame(width: w, height: h, alignment: alignment)
                .background(RemoteKeyFace(shape: shape))
        }
    }

    private var dpad: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.2), Color(white: 0.11)], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(Color(white: 0.08), lineWidth: 5))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            arrow("triangle.fill", 0, "Yukarı", .up).offset(y: -ring / 3)
            arrow("triangle.fill", 180, "Aşağı", .down).offset(y: ring / 3)
            arrow("triangle.fill", -90, "Sol", .left).offset(x: -ring / 3)
            arrow("triangle.fill", 90, "Sağ", .right).offset(x: ring / 3)
            KeyButton(action: { tv.press(.ok) }, help: "OK") {
                Text("OK")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color(white: 0.09)))
                    .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 2.5).padding(3))
                    .contentShape(Circle())
            }
        }
        .frame(width: ring, height: ring)
    }

    private func arrow(_ symbol: String, _ degrees: Double, _ help: String, _ key: RemoteKey) -> some View {
        KeyButton(action: { tv.press(key) }, repeats: true, help: help) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .rotationEffect(.degrees(degrees))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
    }
}
