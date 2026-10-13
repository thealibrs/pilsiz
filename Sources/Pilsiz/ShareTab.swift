import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// "TV'de göster": Mac ekranını yansıt, fotoğraf ve video gönder.
struct ShareTab: View {
    @Environment(TVController.self) private var tv
    @State private var dropTargeted = false

    private var share: ScreenShare { tv.share }

    var body: some View {
        VStack(spacing: 10) {
            PanoCard()

            Card("Mac ekranın, büyük ekranda", icon: "display") {
                Text("Mac ekranını TV'ye yansıtır. Sunum, belge ve web sayfaları için uygundur; saniyede birkaç kare olduğu için film izlemeye uygun değildir.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if share.activity == .mirroring {
                    HStack {
                        Label("Yansıtılıyor · \(share.framesPerSecond, format: .number.precision(.fractionLength(1))) kare/sn", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
                        Spacer()
                        Button("Durdur") { share.stop() }
                    }
                } else {
                    Button { share.startMirroring(tv: tv) } label: {
                        Label("Yansıtmayı başlat", systemImage: "rectangle.on.rectangle.angled").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!tv.isOnline || share.activity == .connecting)
                }
            }

            Card("Fotoğraf ya da video gönder", icon: "photo.on.rectangle") {
                dropZone
                mediaControls
            }

            status

            if share.activity != .off {
                Button(role: .destructive) { share.stop() } label: {
                    Label("TV'deki Pilsiz Ekranı'nı kapat", systemImage: "xmark.circle").frame(maxWidth: .infinity)
                }
            }

            Text("İlk gönderimde TV bir onay sorar; Pilsiz onu kendisi onaylar. Ekran açık kaldıkça yeni gönderimlerde tekrar sorulmaz.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 6) {
            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 22)).foregroundStyle(.secondary)
            Text("Fotoğrafları ya da bir videoyu buraya sürükle").font(.system(size: 11.5, weight: .medium))
            Button("Dosya seç…", action: choose).controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(dropTargeted ? Theme.accent : Color.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = await withCheckedContinuation({ (continuation: CheckedContinuation<URL?, Never>) in
                        _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                    }) { urls.append(url) }
                }
                if !urls.isEmpty { share.share(urls, tv: tv) }
            }
            return true
        }
    }

    @ViewBuilder private var mediaControls: some View {
        if case .photos(let index, let count) = share.activity {
            HStack(spacing: 8) {
                Button { share.step(-1) } label: { Image(systemName: "chevron.left") }
                Text("Fotoğraf \(index + 1) / \(count)").font(.system(size: 11.5, weight: .medium)).monospacedDigit()
                Button { share.step(1) } label: { Image(systemName: "chevron.right") }
                Spacer()
                Toggle("Slayt", isOn: Binding(get: { share.slideshow }, set: { _ in share.toggleSlideshow() }))
                    .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            }
        }
    }

    @ViewBuilder private var status: some View {
        switch share.activity {
        case .off, .mirroring, .photos:
            EmptyView()
        case .connecting:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("TV'de Pilsiz Ekranı açılıyor…").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        case .preparingVideo(let name):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("“\(name)” TV için hazırlanıyor…").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        case .video(let name):
            Label("TV'de oynatılıyor: \(name)", systemImage: "play.rectangle.fill")
                .font(.system(size: 11.5, weight: .medium)).foregroundStyle(.green).lineLimit(1)
        case .failed(let message):
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.accent)
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

/// Pano: TV'de açılan ana ekran. Ok tuşları pano açıkken TV'ye değil panoya gider.
private struct PanoCard: View {
    @Environment(TVController.self) private var tv
    @State private var editing = false

    private var pano: Dashboard { tv.dashboard }

    var body: some View {
        Card("Pano", icon: "square.grid.2x2") {
            Text("Uygulamalar, YouTube kısayolları, haberler, hava ve piyasa tek ekranda. Açıkken klavyenin ok tuşları, Kumanda sekmesi ve aşağıdaki dokunmatik alan panoyu gezdirir.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if pano.isOpen(on: tv.share) {
                HStack {
                    Label("Pano TV'de açık", systemImage: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11.5, weight: .medium)).foregroundStyle(Theme.accent)
                    Spacer()
                    Button("Geri") { tv.press(.back) }
                    Button("Kapat") { pano.close(tv: tv) }
                }
                PanoTouchpad { tv.press($0) }
                    .frame(height: 130)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.key))
                    .overlay {
                        VStack(spacing: 4) {
                            Image(systemName: "hand.draw").font(.system(size: 20)).foregroundStyle(.secondary)
                            Text("İki parmakla kaydır: gez").font(.system(size: 11.5, weight: .medium))
                            Text("İki parmakla dokun ya da tıkla: seç").font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                        .allowsHitTesting(false)
                    }
            } else {
                Button { pano.open(tv: tv) } label: {
                    Label(pano.status == .opening ? "Açılıyor…" : "Panoyu TV'de aç", systemImage: "tv").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!tv.isOnline || pano.status == .opening)
            }
            if case .failed(let message) = pano.status {
                Text(message).font(.system(size: 11)).foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
            DisclosureGroup("YouTube kısayolları", isExpanded: $editing) {
                VStack(spacing: 6) {
                    ForEach(Bindable(pano).shortcuts) { $shortcut in
                        HStack(spacing: 6) {
                            TextField("Ad", text: $shortcut.name).frame(width: 96)
                            TextField("Video ya da kanal linki", text: $shortcut.link)
                        }
                        .textFieldStyle(.roundedBorder)
                    }
                    Text("Kanal linki verirsen (youtube.com/@kanal) o kanalın canlı yayını açılır.")
                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 6)
            }
            .font(.system(size: 11.5))
        }
    }
}
