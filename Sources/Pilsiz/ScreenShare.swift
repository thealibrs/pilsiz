import AppKit
import AVFoundation
import Observation
import ScreenCaptureKit
import UniformTypeIdentifiers

/// "TV'de göster": Mac ekranını, fotoğrafları ve videoları TV'deki Pilsiz Ekranı'na (HbbTV) gönderir.
@MainActor
@Observable
final class ScreenShare {
    enum Activity: Equatable {
        case off
        case connecting
        case mirroring
        case photos(index: Int, count: Int)
        case preparingVideo(String)
        case video(String)
        case failed(String)
    }

    private(set) var activity: Activity = .off
    private(set) var framesPerSecond = 0.0
    var slideshow = true

    let server = ShareServer()
    #if DEBUG
    var debugServer: ShareServer { server }
    func debugConnect(tv: TVController) async -> Bool { await connect(tv: tv) }
    #endif
    private var captureTask: Task<Void, Never>?
    private var mirror: MirrorCapture?
    private var slideshowTask: Task<Void, Never>?
    private var launchFailure: String?
    private var photos: [URL] = []
    private var photoIndex = 0

    static let imageTypes: [UTType] = [.image]
    static let videoTypes: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]

    // MARK: - Ekran

    func startMirroring(tv: TVController) {
        stopMedia()
        activity = .connecting
        Task {
            guard await connect(tv: tv) else { return }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first else {
                    activity = .failed("Ekran bulunamadı.")
                    return
                }
                // Pilsiz'in kendi paneli yansıtmaya girmesin.
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                // Tam HD: TV paneli 1920×1080; kare hızı çözünürlükten bağımsız olarak ~15'te kalıyor.
                let width = 1920
                let height = Int(Double(width) * Double(display.height) / Double(max(display.width, 1)))
                let capture = MirrorCapture(server: server)
                try await capture.start(filter: filter, width: width, height: height)
                mirror = capture
                activity = .mirroring
                // Panelde TV'ye gerçekten ulaşan kare hızı gösterilir.
                captureTask = Task { [server] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(2))
                        framesPerSecond = Double(server.takeDeliveredCount()) / 2
                    }
                }
            } catch {
                activity = .failed("Ekran kaydı izni gerekiyor: Sistem Ayarları › Gizlilik ve Güvenlik › Ekran ve Sistem Sesi Kaydı › Pilsiz.")
            }
        }
    }

    // MARK: - Fotoğraf ve video

    /// Bırakılan dosyaları türüne göre gönderir: video varsa ilk video, yoksa fotoğraflar slayt olarak.
    func share(_ urls: [URL], tv: TVController) {
        let videos = urls.filter { Self.conforms($0, to: Self.videoTypes) }
        let images = urls.filter { Self.conforms($0, to: Self.imageTypes) }
        if let video = videos.first {
            play(video, tv: tv)
        } else if !images.isEmpty {
            show(images, tv: tv)
        } else {
            activity = .failed("Yalnızca fotoğraf ve video gönderilebilir.")
        }
    }

    func show(_ images: [URL], tv: TVController) {
        stopMedia()
        photos = images.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        photoIndex = 0
        activity = .connecting
        Task {
            guard await connect(tv: tv) else { return }
            showPhoto(at: 0)
            restartSlideshow()
        }
    }

    func step(_ delta: Int) {
        guard !photos.isEmpty else { return }
        showPhoto(at: (photoIndex + delta + photos.count) % photos.count)
        restartSlideshow()
    }

    func toggleSlideshow() {
        slideshow.toggle()
        restartSlideshow()
    }

    func play(_ video: URL, tv: TVController) {
        stopMedia()
        let name = video.deletingPathExtension().lastPathComponent
        activity = .preparingVideo(name)
        Task {
            async let connected = connect(tv: tv, keepActivity: true)
            do {
                let playable = try await Self.playableCopy(of: video)
                guard await connected else { return }
                server.setVideo(playable)
                activity = .video(name)
            } catch {
                activity = .failed("Video hazırlanamadı: \(error.localizedDescription)")
            }
        }
    }

    /// Gönderimi durdurur, TV'deki Pilsiz Ekranı'nı kapatıp canlı yayına döner.
    func stop() {
        stopMedia()
        server.setMode(.close)
        activity = .off
        Task { [server] in
            // Sayfanın "kapan" komutunu alması için kısa bir süre.
            try? await Task.sleep(for: .seconds(2))
            // Bu arada yeni bir gönderim ya da pano başladıysa sunucu açık kalır.
            if server.currentMode == .close { server.stop() }
        }
    }

    private func stopMedia() {
        captureTask?.cancel()
        captureTask = nil
        if let mirror {
            self.mirror = nil
            Task { await mirror.stop() }
        }
        slideshowTask?.cancel()
        slideshowTask = nil
        framesPerSecond = 0
    }

    private func showPhoto(at index: Int) {
        photoIndex = index
        activity = .photos(index: index, count: photos.count)
        let url = photos[index]
        Task.detached(priority: .userInitiated) { [server] in
            if let jpeg = Self.preparedPhoto(url) { server.setFrame(jpeg) }
        }
    }

    private func restartSlideshow() {
        slideshowTask?.cancel()
        guard slideshow, photos.count > 1 else { return }
        slideshowTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled else { return }
                showPhoto(at: (photoIndex + 1) % photos.count)
            }
        }
    }

    // MARK: - TV'de sayfayı açma

    /// Sunucuyu başlatır ve TV'de Pilsiz Ekranı'nı açar. Sayfa zaten bağlıysa yeniden açmaz.
    /// TV her açılışta "Evet/Hayır" onayı sorar ve "Evet" seçili gelir: sayfa bağlanmazsa OK gönderilir.
    private func connect(tv: TVController, keepActivity: Bool = false) async -> Bool {
        if let failure = await openScreen(tv: tv) {
            activity = .failed(failure)
            return false
        }
        return true
    }

    /// `connect`'in durum yazmayan hâli (pano da kullanır): başarısız olursa nedenini döndürür.
    func openScreen(tv: TVController) async -> String? {
        do { try server.start() } catch {
            return "Yerel sunucu başlatılamadı: \(error.localizedDescription)"
        }
        if server.isConnected { return nil }
        guard let address = Self.localAddress(near: tv.host) else {
            return "Mac'in yerel ağ adresi bulunamadı."
        }
        server.resetPageFetch()
        launchFailure = nil
        // Yanıt onaya kadar bekleyebildiği için beklenmeden arka planda gönderilir.
        Task {
            do {
                try await SmartCenter.launchHbbTV(url: "http://\(address):\(ShareServer.port)/", on: tv.host)
            } catch {
                launchFailure = error.localizedDescription
            }
        }
        // Onay: TV önce "Evet/Hayır" sorar ("Evet" seçili gelir), sayfayı ancak onaydan sonra indirir.
        // 1,5 sn'de OK gönderilir; sayfa hâlâ inmediyse 4,5 ve 8 sn'de yeniden denenir. Sayfa indirilmeye
        // başladıysa onay verilmiştir; bir daha OK gönderilmez (canlı yayında OK kanal listesini açar).
        let started = Date()
        var pending: [TimeInterval] = [1.5, 4.5, 8]
        for _ in 0..<75 {
            try? await Task.sleep(for: .milliseconds(200))
            if server.isConnected { return nil }
            if let launchFailure {
                return "TV'de Pilsiz Ekranı açılamadı: \(launchFailure)"
            }
            if server.pageFetchedAt == nil, let next = pending.first, Date().timeIntervalSince(started) >= next {
                pending.removeFirst()
                tv.send(code: RemoteKey.ok.rawValue)
            }
        }
        return "TV'deki Pilsiz Ekranı bağlanmadı. TV'de onay sorusu açıksa “Evet”i seç."
    }

    /// TV ile aynı ağdaki Mac adresi.
    private static func localAddress(near host: String) -> String? {
        let addresses = LocalNetwork.interfaces().map(\.address)
        let prefix = host.split(separator: ".").prefix(3).joined(separator: ".")
        return addresses.first { $0.hasPrefix(prefix + ".") } ?? addresses.first
    }

    // MARK: - Medya hazırlama

    private nonisolated static func conforms(_ url: URL, to types: [UTType]) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return types.contains { type.conforms(to: $0) }
    }

    private nonisolated static func jpeg(_ image: CGImage, quality: Double) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: quality])
    }

    /// Fotoğrafı TV çözünürlüğüne (en fazla 1920×1080) küçültüp JPEG yapar; HEIC de desteklenir.
    private nonisolated static func preparedPhoto(_ url: URL) -> Data? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,  // iPhone fotoğraflarındaki yönü uygula
            kCGImageSourceThumbnailMaxPixelSize: 1920,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return jpeg(image, quality: 0.85)
    }

    /// TV'nin tarayıcısı H.264 MP4 oynatır ve donanım çözücüsü en fazla 1920×1080'i kaldırır.
    /// iPhone videoları (HEVC/MOV, çoğu dikey) bu sınıra sığacak H.264 MP4'e dönüştürülür:
    /// dikey 540×960, yatay 1280×720. (Dikey 720p ayarı 1280 piksel yükseklik verir ve TV'de oynamaz.)
    private nonisolated static func playableCopy(of url: URL) async throws -> URL {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        var isH264 = false
        var size = CGSize(width: 1920, height: 1080)
        if let track = tracks.first {
            let (formats, natural, transform) = try await track.load(.formatDescriptions, .naturalSize, .preferredTransform)
            isH264 = formats.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_H264 }
            let rotated = natural.applying(transform)
            size = CGSize(width: abs(rotated.width), height: abs(rotated.height))
        }
        let fitsDecoder = max(size.width, size.height) <= 1920 && min(size.width, size.height) <= 1080 && size.height <= 1080
        if isH264, fitsDecoder, url.pathExtension.lowercased() == "mp4" { return url }

        let portrait = size.height > size.width
        let preset = portrait ? AVAssetExportPreset960x540 : AVAssetExportPreset1280x720
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("pilsiz-\(UUID().uuidString).mp4")
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        session.shouldOptimizeForNetworkUse = true
        if #available(macOS 15.0, *) {
            try await session.export(to: output, as: .mp4)
        } else {
            session.outputURL = output
            session.outputFileType = .mp4
            await session.export()
            if let error = session.error { throw error }
        }
        return output
    }
}

/// Sürekli ekran yakalama (SCStream): yalnızca ekran değişince kare üretir, JPEG'e ekran kartında çevirir.
/// Saniyede 15 kare: TV'nin tarayıcısı MJPEG akışını saniyede en fazla ~15 kez güncelliyor (14.10.2026'da
/// 960×540, 1280×720 ve 1920×1080 ile ölçüldü; üçünde de 15), fazlası boşa iş.
private final class MirrorCapture: NSObject, SCStreamOutput, @unchecked Sendable {
    private let server: ShareServer
    private let context = CIContext()
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private let queue = DispatchQueue(label: "pilsiz.capture", qos: .userInteractive)
    private var stream: SCStream?

    init(server: ShareServer) {
        self.server = server
    }

    @MainActor func start(filter: SCContentFilter, width: Int, height: Int) async throws {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        configuration.queueDepth = 3
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        // Ekran değişmediyse macOS "boşta" kareler gönderir; onlar atlanır.
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int, SCFrameStatus(rawValue: raw) == .complete,
              let pixels = sampleBuffer.imageBuffer
        else { return }
        let options = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.55]
        if let jpeg = context.jpegRepresentation(of: CIImage(cvPixelBuffer: pixels), colorSpace: colorSpace, options: options) {
            server.setFrame(jpeg)
        }
    }
}
