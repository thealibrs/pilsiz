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

    private let server = ShareServer()
    private var captureTask: Task<Void, Never>?
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
                let configuration = SCStreamConfiguration()
                configuration.width = 1280
                configuration.height = Int(1280 * Double(display.height) / Double(max(display.width, 1)))
                configuration.showsCursor = true
                activity = .mirroring
                captureTask = Task { [server] in
                    var count = 0
                    var windowStart = Date()
                    while !Task.isCancelled {
                        let started = Date()
                        if let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration),
                           let jpeg = Self.jpeg(image, quality: 0.55) {
                            server.setFrame(jpeg)
                            count += 1
                        }
                        if Date().timeIntervalSince(windowStart) >= 2 {
                            framesPerSecond = Double(count) / Date().timeIntervalSince(windowStart)
                            count = 0
                            windowStart = Date()
                        }
                        // En fazla ~6 kare/sn: TV'nin tarayıcısı ve ağ için yeterli.
                        let wait = 0.16 - Date().timeIntervalSince(started)
                        if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
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
            server.stop()
        }
    }

    private func stopMedia() {
        captureTask?.cancel()
        captureTask = nil
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
        do { try server.start() } catch {
            activity = .failed("Yerel sunucu başlatılamadı: \(error.localizedDescription)")
            return false
        }
        if server.isConnected { return true }
        guard let address = Self.localAddress(near: tv.host) else {
            activity = .failed("Mac'in yerel ağ adresi bulunamadı.")
            return false
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
            if server.isConnected { return true }
            if let launchFailure {
                activity = .failed("TV'de Pilsiz Ekranı açılamadı: \(launchFailure)")
                return false
            }
            if server.pageFetchedAt == nil, let next = pending.first, Date().timeIntervalSince(started) >= next {
                pending.removeFirst()
                tv.send(code: RemoteKey.ok.rawValue)
            }
        }
        activity = .failed("TV'deki Pilsiz Ekranı bağlanmadı. TV'de onay sorusu açıksa “Evet”i seç.")
        return false
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
