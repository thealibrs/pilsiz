import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// "TV'de göster": pano, Mac ekranını yansıtma, fotoğraf ve video gönderme.
/// TV'deki Pilsiz Ekranı'nda bir şey açıksa en üstte onu yöneten "Şimdi TV'de" kartı durur.
struct ShareTab: View {
    @Environment(TVController.self) private var tv

    private var share: ScreenShare { tv.share }
    private var pano: Dashboard { tv.dashboard }
    private var isPanoOpen: Bool { pano.isOpen(on: share) }
    /// Ekranda bir şey varken kartlar küçülür; dokunmatik alana ya da fotoğraf şeridine yer kalır.
    private var isBusy: Bool { isPanoOpen || pano.status == .opening || share.activity != .off && !isFailed }

    private var isFailed: Bool {
        if case .failed = share.activity { return true }
        return false
    }

    var body: some View {
        VStack(spacing: 10) {
            if isBusy { NowShowingCard() }
            if isPanoOpen { touchpad }
            if case .photos(let index, _) = share.activity { PhotoStrip(current: index) }

            ModeCards(compact: isBusy, choose: choose)

            if !isBusy {
                MediaDropZone(slim: false, choose: choose)
            } else if case .photos = share.activity {
                MediaDropZone(slim: true, choose: choose)
            }

            failure
            ShortcutsRow()

            if !isBusy {
                Text("İlk gönderimde TV bir onay sorar; Pilsiz onu kendisi onaylar.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isBusy)
    }

    private var touchpad: some View {
        PanoTouchpad { tv.press($0) }
            .frame(height: 124)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.key))
            .overlay {
                VStack(spacing: 3) {
                    Image(systemName: "hand.draw").font(.system(size: 20)).foregroundStyle(.secondary)
                    Text("İki parmakla kaydır: gez").font(.system(size: 11.5, weight: .semibold))
                    Text("Dokun ya da tıkla: seç").font(.system(size: 10.5)).foregroundStyle(.secondary)
                }
                .allowsHitTesting(false)
            }
    }

    @ViewBuilder private var failure: some View {
        let message: String? = if case .failed(let text) = share.activity {
            text
        } else if case .failed(let text) = pano.status {
            text
        } else {
            nil
        }
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = ScreenShare.imageTypes + ScreenShare.videoTypes
        panel.message = "TV'de gösterilecek fotoğrafları ya da bir videoyu seç"
        NSApp.activate()
        if panel.runModal() == .OK { share.share(panel.urls, tv: tv) }
    }
}

/// Mod renkleri: pano Pilsiz kırmızısı, yansıtma mor, fotoğraf ve video turuncu.
private enum ShareTint {
    static let pano = Theme.accent
    static let mirror = Color(red: 0.37, green: 0.36, blue: 0.90)
    static let media = Color(red: 1.0, green: 0.62, blue: 0.04)
}

// MARK: - Şimdi TV'de

private struct NowShowingCard: View {
    @Environment(TVController.self) private var tv

    private var share: ScreenShare { tv.share }
    private var pano: Dashboard { tv.dashboard }

    var body: some View {
        VStack(spacing: 10) {
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card)
                .overlay(RadialGradient(colors: [tint.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
        )
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(tint.opacity(0.35)))
    }

    private var tint: Color {
        switch share.activity {
        case .mirroring: ShareTint.mirror
        case .photos, .video, .preparingVideo: ShareTint.media
        default: ShareTint.pano
        }
    }

    @ViewBuilder private var content: some View {
        if pano.isOpen(on: share) {
            header(kicker: "Şimdi TV'de", title: "Pano", subtitle: "Ok tuşları panoyu gezdiriyor", live: true) {
                iconTile("square.grid.2x2", tint: ShareTint.pano)
            }
            HStack(spacing: 8) {
                action("Geri", symbol: "arrow.left") { tv.press(.back) }
                action("Panoyu kapat", symbol: "xmark") { pano.close(tv: tv) }
            }
        } else {
            switch share.activity {
            case .mirroring:
                header(kicker: "Şimdi TV'de", title: "Mac ekranı",
                       subtitle: "Yansıtılıyor · \(share.framesPerSecond.formatted(.number.precision(.fractionLength(1)))) kare/sn",
                       live: true) {
                    iconTile("rectangle.on.rectangle", tint: ShareTint.mirror)
                }
                action("Yansıtmayı durdur", symbol: "stop.fill") { share.stop() }
            case .photos(let index, let count):
                photos(index: index, count: count)
            case .preparingVideo(let name):
                header(kicker: "Hazırlanıyor", title: name, subtitle: "Video TV için dönüştürülüyor…") {
                    progressTile
                }
                action("Vazgeç", symbol: "xmark") { share.stop() }
            case .video(let name):
                header(kicker: "Şimdi TV'de", title: name, subtitle: "TV'de oynatılıyor", live: true) {
                    iconTile("play.rectangle.fill", tint: ShareTint.media)
                }
                action("Videoyu kapat", symbol: "xmark") { share.stop() }
            default:
                // Bağlanıyor ya da pano açılıyor.
                header(kicker: "Bağlanıyor", title: "Pilsiz Ekranı açılıyor…", subtitle: "TV onay sorarsa Pilsiz kendisi onaylar.") {
                    progressTile
                }
            }
        }
    }

    @ViewBuilder private func photos(index: Int, count: Int) -> some View {
        let url = share.photos.indices.contains(index) ? share.photos[index] : nil
        header(kicker: "Şimdi TV'de · \(index + 1) / \(count)", title: url?.lastPathComponent ?? "Fotoğraf",
               subtitle: share.slideshow && count > 1 ? "Slayt gösterisi · 6 sn'de bir" : "Slayt kapalı") {
            if let url {
                PhotoThumb(url: url).frame(width: 60, height: 44)
            } else {
                iconTile("photo", tint: ShareTint.media)
            }
        }
        HStack(spacing: 6) {
            square("chevron.left", help: "Önceki fotoğraf") { share.step(-1) }
            square("chevron.right", help: "Sonraki fotoğraf") { share.step(1) }
            Spacer(minLength: 0)
            if count > 1 {
                KeyButton(action: share.toggleSlideshow, help: share.slideshow ? "Slaytı durdur" : "Slaytı başlat") {
                    Label(share.slideshow ? "Slaytı durdur" : "Slaytı başlat", systemImage: share.slideshow ? "pause.fill" : "play.fill")
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.key))
                }
            }
            square("xmark", help: "Fotoğrafları kapat") { share.stop() }
        }
    }

    // MARK: Parçalar

    private func header(kicker: String, title: String, subtitle: String, live: Bool = false,
                        @ViewBuilder leading: () -> some View) -> some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: kicker)
                Text(title).font(.system(size: 15, weight: .bold)).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 5) {
                    if live { Circle().fill(.green).frame(width: 6, height: 6) }
                    Text(subtitle).lineLimit(1)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private func iconTile(_ symbol: String, tint: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(tint.opacity(0.2)))
    }

    private var progressTile: some View {
        ProgressView().controlSize(.small)
            .frame(width: 44, height: 44)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.key))
    }

    private func action(_ title: String, symbol: String, perform: @escaping () -> Void) -> some View {
        KeyButton(action: perform, help: title) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11.5, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.key))
        }
    }

    private func square(_ symbol: String, help: String, perform: @escaping () -> Void) -> some View {
        KeyButton(action: perform, help: help) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 30, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.key))
        }
    }
}

// MARK: - Fotoğraf şeridi

/// Slayttaki fotoğrafların küçük resimleri; o an gösterilen ortada. Tıklanan fotoğraf TV'de açılır.
private struct PhotoStrip: View {
    @Environment(TVController.self) private var tv
    let current: Int

    var body: some View {
        let photos = tv.share.photos
        let indices = Self.window(around: current, count: photos.count)
        HStack(spacing: 6) {
            ForEach(indices, id: \.self) { index in
                KeyButton(action: { tv.share.showPhoto(index) }, help: photos[index].lastPathComponent) {
                    PhotoThumb(url: photos[index])
                        .frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .opacity(index == current ? 1 : 0.5)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(index == current ? ShareTint.media : .clear, lineWidth: 2))
                }
            }
        }
    }

    /// En fazla 5 fotoğraf; seçili olan mümkünse ortada.
    private static func window(around index: Int, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let size = min(5, count)
        let start = min(max(0, index - size / 2), count - size)
        return Array(start..<start + size)
    }
}

/// Fotoğrafın küçük resmi (HEIC dahil), arka planda üretilir.
private struct PhotoThumb: View {
    let url: URL
    @State private var image: CGImage?

    var body: some View {
        Rectangle().fill(Theme.key)
            .overlay {
                if let image {
                    Image(decorative: image, scale: 2).resizable().scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .task(id: url) { image = await Self.thumbnail(url) }
    }

    private static func thumbnail(_ url: URL) async -> CGImage? {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 240,
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}

// MARK: - Modlar

/// Pano, ekran yansıtma, fotoğraf ve video. Bir şey açıkken küçülür; açık olan çerçevelenir.
private struct ModeCards: View {
    @Environment(TVController.self) private var tv
    let compact: Bool
    let choose: () -> Void

    private var share: ScreenShare { tv.share }
    private var pano: Dashboard { tv.dashboard }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: "TV'de göster")
                    Spacer()
                    if !tv.isOnline {
                        Text("TV kapalı").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 2)
            }
            panoCard
            HStack(spacing: 8) {
                modeCard(title: "Ekranı yansıt", detail: "Sunum ve belgeler için", symbol: "rectangle.on.rectangle",
                         tint: ShareTint.mirror, isOn: share.activity == .mirroring) {
                    if share.activity == .mirroring { share.stop() } else { share.startMirroring(tv: tv) }
                }
                .disabled(!tv.isOnline)
                modeCard(title: "Fotoğraf, video", detail: "Sürükle ya da seç", symbol: "photo.on.rectangle",
                         tint: ShareTint.media, isOn: isShowingMedia, action: choose)
            }
        }
    }

    private var isShowingMedia: Bool {
        switch share.activity {
        case .photos, .video, .preparingVideo: true
        default: false
        }
    }

    private var panoCard: some View {
        let isOpen = pano.isOpen(on: share)
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return KeyButton(action: { if !isOpen { pano.open(tv: tv) } }, help: isOpen ? "Pano TV'de açık" : "Panoyu TV'de aç") {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: compact ? 0 : 6) {
                    Label("Pano", systemImage: "square.grid.2x2")
                        .font(.system(size: compact ? 13 : 16, weight: .bold))
                    if !compact {
                        Text("Uygulamalar, YouTube, haber, hava ve piyasa tek ekranda")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if !isOpen { PanoPreview().frame(width: compact ? 58 : 100, height: compact ? 38 : 68) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, compact ? 10 : 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(RadialGradient(colors: [ShareTint.pano.opacity(0.28), .clear], center: .topTrailing, startRadius: 0, endRadius: 200)
                        .clipShape(shape))
            )
            .overlay(shape.stroke(isOpen ? ShareTint.pano.opacity(0.9) : Theme.cardStroke, lineWidth: isOpen ? 1.5 : 1))
            .overlay(alignment: .topTrailing) { if isOpen { liveDot } }
        }
        .disabled(!tv.isOnline || pano.status == .opening)
        .opacity(tv.isOnline ? 1 : 0.5)
    }

    private func modeCard(title: String, detail: String, symbol: String, tint: Color, isOn: Bool,
                          action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13, style: .continuous)
        return KeyButton(action: action, help: title) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: compact ? 11 : 13, weight: .medium))
                    .foregroundStyle(tint)
                    .frame(width: compact ? 24 : 30, height: compact ? 24 : 30)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.22)))
                Spacer(minLength: 6)
                Text(title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                if !compact {
                    Text(detail).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: compact ? 64 : 84)
            .background(shape.fill(Color(white: 0.11)))
            .overlay(shape.stroke(isOn ? tint.opacity(0.9) : Theme.cardStroke, lineWidth: isOn ? 1.5 : 1))
            .overlay(alignment: .topTrailing) { if isOn { liveDot } }
        }
    }

    private var liveDot: some View {
        Circle().fill(.green).frame(width: 8, height: 8)
            .background(Circle().fill(.green.opacity(0.25)).frame(width: 14, height: 14))
            .padding(9)
    }
}

/// Panonun küçük önizlemesi: büyük kart, uygulama kutuları ve satırlar.
private struct PanoPreview: View {
    var body: some View {
        GeometryReader { proxy in
            let gap = proxy.size.height * 0.07
            HStack(spacing: gap) {
                RoundedRectangle(cornerRadius: 3).fill(Theme.accent.opacity(0.65).gradient)
                    .frame(width: proxy.size.width * 0.55)
                VStack(spacing: gap) {
                    HStack(spacing: gap) {
                        RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.9, green: 0.04, blue: 0.08))
                        RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.1, green: 0.65, blue: 0.93))
                    }
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.1))
                }
            }
            .padding(gap)
        }
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(red: 0.04, green: 0.05, blue: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(.white.opacity(0.08)))
    }
}

// MARK: - Bırakma alanı

private struct MediaDropZone: View {
    @Environment(TVController.self) private var tv
    let slim: Bool
    let choose: () -> Void
    @State private var targeted = false

    var body: some View {
        Group {
            if slim {
                Label("Başka fotoğraf ya da video bırak", systemImage: "square.and.arrow.down")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 20)).foregroundStyle(.secondary)
                    Text("Fotoğrafları ya da bir videoyu buraya sürükle").font(.system(size: 11.5, weight: .semibold))
                    Text("HEIC ve iPhone videoları da olur; video TV için dönüştürülür")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                    Button("Dosya seç…", action: choose).controlSize(.small).padding(.top, 2)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(targeted ? Theme.accent : Color.white.opacity(0.16), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .contentShape(Rectangle())
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                    }) { urls.append(url) }
                }
                if !urls.isEmpty { tv.share.share(urls, tv: tv) }
            }
            return true
        }
    }
}

// MARK: - YouTube kısayolları

/// Panodaki YouTube kısayolları: tek satır, tıklayınca düzenleme açılır.
private struct ShortcutsRow: View {
    @Environment(TVController.self) private var tv
    @AppStorage("panoShortcutsExpanded") private var expanded = false

    private var pano: Dashboard { tv.dashboard }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(.snappy(duration: 0.2)) { expanded.toggle() } } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(red: 1.0, green: 0.0, blue: 0.2)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("YouTube kısayolları").font(.system(size: 12.5, weight: .semibold))
                        Text(summary).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 6) {
                    ForEach(Bindable(pano).shortcuts) { $shortcut in
                        HStack(spacing: 6) {
                            TextField("Ad", text: $shortcut.name).frame(width: 96)
                            TextField("Video ya da kanal linki", text: $shortcut.link)
                        }
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                    }
                    Text("Kanal linki verirsen (youtube.com/@kanal) o kanalın canlı yayını açılır.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.cardStroke))
    }

    private var summary: String {
        let names = pano.shortcuts.map(\.name).filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Panoda kısayol yok" }
        return "Panoda \(names.count) kısayol · " + names.prefix(2).joined(separator: ", ") + (names.count > 2 ? "…" : "")
    }
}
