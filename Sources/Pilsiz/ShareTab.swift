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
