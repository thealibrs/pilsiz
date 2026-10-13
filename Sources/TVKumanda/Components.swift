import SwiftUI

enum Theme {
    static let background = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let card = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.07)
    static let key = Color.white.opacity(0.08)
    static let accent = Color(red: 0.93, green: 0.18, blue: 0.27)
}

/// Başlıklı koyu kart.
struct Card<Content: View, Trailing: View>: View {
    let title: String
    var icon: String?
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.secondary) }
                Text(title).font(.system(size: 12, weight: .semibold))
                Spacer()
                trailing()
            }
            content()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
    }
}

extension Card where Trailing == EmptyView {
    init(_ title: String, icon: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, icon: icon, trailing: { EmptyView() }, content: content)
    }
}

/// Küçük, büyük harfli bölüm etiketi ("ŞİMDİ EKRANDA" gibi).
struct SectionLabel: View {
    let text: String
    var color: Color = .secondary

    var body: some View {
        Text(text.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1)
            .foregroundStyle(color)
    }
}

/// Basıldığı anda tetiklenen (bırakınca değil) ve istenirse basılı tutulunca tekrarlayan tuş.
struct KeyButton<Label: View>: View {
    let action: () -> Void
    var repeats = false
    var help = ""
    @ViewBuilder let label: () -> Label

    @State private var pressed = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        label()
            .opacity(pressed ? 0.55 : 1)
            .scaleEffect(pressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.08), value: pressed)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressed else { return }
                        pressed = true
                        action()
                        guard repeats else { return }
                        repeatTask = Task {
                            try? await Task.sleep(for: .milliseconds(400))
                            while !Task.isCancelled {
                                action()
                                try? await Task.sleep(for: .milliseconds(160))
                            }
                        }
                    }
                    .onEnded { _ in
                        pressed = false
                        repeatTask?.cancel()
                        repeatTask = nil
                    }
            )
            .help(help)
            .accessibilityLabel(help)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}

/// Simge + isteğe bağlı yazı içeren standart kumanda tuşu.
struct RemoteButton: View {
    let symbol: String
    var title: String?
    var height: CGFloat = 32
    var repeats = false
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        KeyButton(action: action, repeats: repeats, help: title ?? "") {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                if let title { Text(title).font(.system(size: 11.5, weight: .medium)) }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.key))
        }
    }
}

/// Gerçekçi TV görseli (Resources/tv.png); içerik görseldeki ekran alanına yerleştirilir.
struct RealisticTV<Content: View>: View {
    var isOn: Bool
    @ViewBuilder var content: () -> Content

    /// tv.png içindeki ekran alanı, görsel boyutuna oranla.
    private static var screen: CGRect { CGRect(x: 0.0061, y: 0.0099, width: 0.9867, height: 0.867) }

    var body: some View {
        if let image = BundledImage.named("tv") {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .overlay {
                    GeometryReader { proxy in
                        let rect = CGRect(
                            x: proxy.size.width * Self.screen.minX, y: proxy.size.height * Self.screen.minY,
                            width: proxy.size.width * Self.screen.width, height: proxy.size.height * Self.screen.height
                        )
                        display(size: rect.size).position(x: rect.midX, y: rect.midY)
                    }
                }
        } else {
            display(size: CGSize(width: 260, height: 146))
        }
    }

    private func display(size: CGSize) -> some View {
        ZStack {
            if isOn {
                // Açık panelin hafif arka ışığı.
                RadialGradient(colors: [Color(white: 0.17), Color(white: 0.03)], center: .center,
                               startRadius: 0, endRadius: size.width * 0.62)
            }
            content()
            // Camdaki yansıma içeriğin üstünde de görünsün.
            LinearGradient(colors: [Color.white.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .center)
                .allowsHitTesting(false)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
        .animation(.easeInOut(duration: 0.35), value: isOn)
    }
}

/// Uygulama logosu yerine kullanılan renkli rozet.
struct AppBadge: View {
    let app: TVApp
    var size: CGFloat = 40

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(background)
            .frame(width: size, height: size)
            .overlay { glyph }
    }

    private var background: AnyShapeStyle {
        switch app.id {
        case "netflix": AnyShapeStyle(Color.white)
        case "prime": AnyShapeStyle(Color(red: 0.0, green: 0.66, blue: 0.88).gradient)
        case "youtube": AnyShapeStyle(Color.white)
        default: AnyShapeStyle(Theme.key)
        }
    }

    @ViewBuilder private var glyph: some View {
        switch app.id {
        case "netflix":
            Text("N").font(.system(size: size * 0.55, weight: .black)).foregroundStyle(Theme.accent)
        case "prime":
            VStack(spacing: -2) {
                Text("prime").font(.system(size: size * 0.24, weight: .bold))
                Text("video").font(.system(size: size * 0.2, weight: .medium))
            }
            .foregroundStyle(.white)
        case "youtube":
            Image(systemName: "play.rectangle.fill").font(.system(size: size * 0.45)).foregroundStyle(.red)
        case "browser":
            Image(systemName: "globe").font(.system(size: size * 0.42)).foregroundStyle(.secondary)
        case "media":
            Image(systemName: "play.square.stack").font(.system(size: size * 0.42)).foregroundStyle(.secondary)
        default:
            Image(systemName: "square.grid.2x2").font(.system(size: size * 0.42)).foregroundStyle(.secondary)
        }
    }
}

/// "Bugün", "Yarın" ya da kısa gün adı ("Çar").
func dayLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return "Bugün" }
    if Calendar.current.isDateInTomorrow(date) { return "Yarın" }
    return date.formatted(.dateTime.weekday(.abbreviated))
}

/// "21:00" biçiminde saat.
func clock(_ date: Date) -> String {
    date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
}

func formatDuration(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes >= 60 { return "\(minutes / 60) sa \(minutes % 60) dk" }
    if minutes >= 1 { return "\(minutes) dk" }
    return "\(Int(seconds)) sn"
}
