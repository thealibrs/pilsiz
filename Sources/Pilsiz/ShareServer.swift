import Foundation
import Network

/// TV'deki "Pilsiz Ekranı" HbbTV sayfasının bağlandığı yerel HTTP sunucusu.
///
/// Uç noktalar:
/// - `GET /`            HbbTV sayfası
/// - `GET /state`       `{"mode":…, "frame":n, "video":n}` (sayfa ~300 ms'de bir sorar)
/// - `GET /frame.jpg`   son kare (ekran yansıtma ya da fotoğraf)
/// - `GET /video.mp4`   gönderilen video, Range destekli
/// - `GET /pano.html`   pano sayfası; verisi `/pano.json`, görselleri `/pano/img/<ad>`
/// - `GET /pano/poll`   uzun yoklama: kumanda tuşları, veri sürümü ve mod değişimi
/// - `GET /pano/act`    panoda seçilen kartı Mac'e bildirir
///
/// Tüm durum tek bir seri kuyrukta tutulur.
final class ShareServer: @unchecked Sendable {
    enum Mode: String, Sendable { case idle, frames, video, dashboard, close }

    #if DEBUG
    /// Kurulu Pilsiz aynı portu tutarken geliştirme derlemesini denemek için PILSIZ_PORT ile değiştirilebilir.
    static let port = ProcessInfo.processInfo.environment["PILSIZ_PORT"].flatMap(UInt16.init) ?? 8765
    #else
    static let port: UInt16 = 8765
    #endif

    private let queue = DispatchQueue(label: "pilsiz.share")
    private var listener: NWListener?
    private var mode: Mode = .idle { didSet { if mode != oldValue { flushWaiters() } } }
    private var frame: Data?
    private var frameVersion = 0
    private var videoURL: URL?
    private var videoVersion = 0
    private var lastPoll: Date?

    /// MJPEG akışına bağlı TV'ler: tek kalıcı bağlantı, her yeni kare hemen itilir.
    /// Bir kare henüz gönderilirken gelen ara kareler atlanır; hep en yenisi gider, gecikme birikmez.
    private final class Streamer: @unchecked Sendable {  // yalnızca sunucu kuyruğunda kullanılır
        let connection: NWConnection
        var sending = false
        var sentVersion = -1
        init(_ connection: NWConnection) { self.connection = connection }
    }
    private var streamers: [ObjectIdentifier: Streamer] = [:]
    private var delivered = 0

    /// Son çağrıdan bu yana TV'ye ulaştırılan kare sayısı (panelde kare/sn için).
    func takeDeliveredCount() -> Int {
        queue.sync { defer { delivered = 0 }; return delivered }
    }
    private static let boundary = "pilsizframe"
    private var pageFetched: Date?

    // Pano: sayfa tek bir isteği açık tutar (uzun yoklama); tuş gelince ya da veri değişince hemen yanıtlanır.
    private final class Waiter: @unchecked Sendable {  // yalnızca sunucu kuyruğunda kullanılır
        let connection: NWConnection
        let seq: Int
        let dataVersion: Int
        init(_ connection: NWConnection, seq: Int, dataVersion: Int) {
            self.connection = connection
            self.seq = seq
            self.dataVersion = dataVersion
        }
    }
    private var waiters: [ObjectIdentifier: Waiter] = [:]
    private var panoData = Data("{}".utf8)
    private var panoVersion = 0
    private var panoImages: [String: Data] = [:]
    private var panoKeys: [(seq: Int, name: String)] = []
    private var panoSeq = 0
    private var panoAction: (@Sendable (String) -> Void)?

    var currentMode: Mode { queue.sync { mode } }

    var isRunning: Bool { queue.sync { listener != nil } }

    /// TV sayfası son 2 saniyede durum sorduysa ya da pano yoklaması açık bekliyorsa bağlıdır.
    var isConnected: Bool {
        queue.sync { !waiters.isEmpty || (lastPoll.map { Date().timeIntervalSince($0) < 2 } ?? false) }
    }

    /// TV sayfayı onay sorusunu göstermeden hemen önce indirir; bu an onay ekranının geldiğini gösterir.
    var pageFetchedAt: Date? { queue.sync { pageFetched } }

    func resetPageFetch() { queue.sync { pageFetched = nil } }

    func start() throws {
        try queue.sync {
            guard listener == nil else { return }
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: Self.port)!)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.start(queue: queue)
            self.listener = listener
        }
    }

    func stop() {
        queue.sync {
            for streamer in streamers.values { streamer.connection.cancel() }
            streamers = [:]
            for waiter in waiters.values { waiter.connection.cancel() }
            waiters = [:]
            listener?.cancel()
            listener = nil
            lastPoll = nil
        }
    }

    func setFrame(_ jpeg: Data) {
        queue.async {
            self.frame = jpeg
            self.frameVersion += 1
            self.mode = .frames
            for streamer in self.streamers.values { self.push(to: streamer) }
        }
    }

    /// Yayıncıya en yeni kareyi gönderir; gönderim sürerken yeni kare gelirse bitince en yenisi gider.
    private func push(to streamer: Streamer) {
        guard !streamer.sending, let frame, streamer.sentVersion != frameVersion else { return }
        streamer.sending = true
        streamer.sentVersion = frameVersion
        let part = Data("--\(Self.boundary)\r\nContent-Type: image/jpeg\r\nContent-Length: \(frame.count)\r\n\r\n".utf8)
            + frame + Data("\r\n".utf8)
        streamer.connection.send(content: part, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            streamer.sending = false
            if error == nil { self.delivered += 1 }
            if error != nil {
                self.streamers[ObjectIdentifier(streamer)] = nil
                streamer.connection.cancel()
            } else {
                self.push(to: streamer)
            }
        })
    }

    private func startStream(on connection: NWConnection) {
        let streamer = Streamer(connection)
        streamers[ObjectIdentifier(streamer)] = streamer
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.streamers[ObjectIdentifier(streamer)] = nil
            default: break
            }
        }
        let head = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=\(Self.boundary)\r\n"
            + "Cache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] _ in
            self?.push(to: streamer)
        })
    }

    func setVideo(_ url: URL) {
        queue.async {
            self.videoURL = url
            self.videoVersion += 1
            self.mode = .video
        }
    }

    func setMode(_ mode: Mode) {
        queue.async { self.mode = mode }
    }

    // MARK: - Pano

    /// Pano verisini ve görsellerini değiştirir; içerik aynıysa sayfa yeniden çizilmez.
    func setPano(json: Data, images: [String: Data]) {
        queue.async {
            guard json != self.panoData || images != self.panoImages else { return }
            self.panoData = json
            self.panoImages = images
            self.panoVersion += 1
            self.flushWaiters()
        }
    }

    /// Panoya bir kumanda tuşu iletir: up, down, left, right, ok, back.
    func pushPanoKey(_ name: String) {
        queue.async {
            self.panoSeq += 1
            self.panoKeys.append((self.panoSeq, name))
            if self.panoKeys.count > 30 { self.panoKeys.removeFirst(self.panoKeys.count - 30) }
            self.flushWaiters()
        }
    }

    func setPanoAction(_ handler: @escaping @Sendable (String) -> Void) {
        queue.async { self.panoAction = handler }
    }

    private func poll(seq: Int, dataVersion: Int, on connection: NWConnection) {
        lastPoll = Date()
        // İlk yoklama (ya da sunucu yeniden başladıysa) hemen yanıtlanır; eski tuşlar yeniden oynatılmaz.
        guard seq >= 0, seq <= panoSeq else { return replyPoll(keys: [], on: connection) }
        let waiter = Waiter(connection, seq: seq, dataVersion: dataVersion)
        if hasNews(for: waiter) { return replyPoll(to: waiter) }
        let id = ObjectIdentifier(waiter)
        waiters[id] = waiter
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.waiters[id] = nil
            default: break
            }
        }
        queue.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, let waiter = self.waiters.removeValue(forKey: id) else { return }
            self.replyPoll(to: waiter)
        }
    }

    private func hasNews(for waiter: Waiter) -> Bool {
        mode != .dashboard || waiter.dataVersion != panoVersion || waiter.seq < panoSeq
    }

    private func flushWaiters() {
        for (id, waiter) in waiters where hasNews(for: waiter) {
            waiters[id] = nil
            replyPoll(to: waiter)
        }
    }

    private func replyPoll(to waiter: Waiter) {
        replyPoll(keys: panoKeys.filter { $0.seq > waiter.seq }.map(\.name), on: waiter.connection)
    }

    private func replyPoll(keys: [String], on connection: NWConnection) {
        lastPoll = Date()
        let list = keys.map { "\"\($0)\"" }.joined(separator: ",")
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let json = #"{"seq":\#(panoSeq),"mode":"\#(mode.rawValue)","data":\#(panoVersion),"now":\#(now),"keys":[\#(list)]}"#
        send(status: "200 OK", type: "application/json", body: Data(json.utf8), on: connection)
    }

    /// Pano fontları uygulama paketinden okunur; yalnızca bilinen dosya adları kabul edilir.
    private static func font(named file: String) -> Data? {
        let names = ["figtree-latin", "figtree-latin-ext", "bricolage-latin", "bricolage-latin-ext"]
        guard file.hasSuffix(".woff2"), names.contains(String(file.dropLast(6))) else { return nil }
        var url = Bundle.main.url(forResource: String(file.dropLast(6)), withExtension: "woff2", subdirectory: "Fonts")
        #if DEBUG
        if url == nil { url = URL(fileURLWithPath: "Resources/Fonts/\(file)") }
        #endif
        return url.flatMap { try? Data(contentsOf: $0) }
    }

    // MARK: - HTTP

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, buffer: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(to: String(decoding: buffer[..<end.lowerBound], as: UTF8.self), on: connection)
            } else if isComplete || error != nil || buffer.count > 65_536 {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to head: String, on connection: NWConnection) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = lines.first?.split(separator: " ") ?? []
        let target = parts.count > 1 ? parts[1].split(separator: "?", maxSplits: 1) : []
        let path = target.first.map(String.init) ?? "/"
        var query: [String: String] = [:]
        for pair in (target.count > 1 ? target[1] : "").split(separator: "&") {
            let item = pair.split(separator: "=", maxSplits: 1)
            if item.count == 2 { query[String(item[0])] = String(item[1]).removingPercentEncoding }
        }
        let range = lines.first { $0.lowercased().hasPrefix("range:") }
        // TV sayfaları HbbTV türüyle ister; Mac'teki tarayıcıda denerken (localhost) aynı katı XHTML okuması için standart tür.
        let local = lines.contains { $0.lowercased().hasPrefix("host: localhost") || $0.lowercased().hasPrefix("host: 127.0.0.1") }
        let pageType = (local ? "application/xhtml+xml" : "application/vnd.hbbtv.xhtml+xml") + "; charset=UTF-8"

        switch path {
        case "/", "/index.html":
            pageFetched = Date()
            // Pano açılırken ara sayfa görünmesin diye doğrudan pano verilir.
            send(status: "200 OK", type: pageType, body: Data((mode == .dashboard ? Self.panoPage : Self.page).utf8), on: connection)
        case "/video.html":
            send(status: "200 OK", type: pageType, body: Data(Self.videoPage(version: videoVersion).utf8), on: connection)
        case "/pano.html":
            send(status: "200 OK", type: pageType, body: Data(Self.panoPage.utf8), on: connection)
        case "/pano.json":
            send(status: "200 OK", type: "application/json; charset=UTF-8", body: panoData, on: connection)
        case "/pano/poll":
            poll(seq: query["seq"].flatMap(Int.init) ?? -1, dataVersion: query["data"].flatMap(Int.init) ?? -1, on: connection)
        case "/pano/act":
            if let id = query["id"] { panoAction?(id) }
            send(status: "204 No Content", type: "text/plain", body: Data(), on: connection)
        #if DEBUG
        case "/pano/key":
            // Geliştirme: TV ve Pilsiz paneli olmadan tuş göndermek için (curl ile).
            if let name = query["k"] { pushPanoKey(name) }
            send(status: "204 No Content", type: "text/plain", body: Data(), on: connection)
        #endif
        case _ where path.hasPrefix("/pano/font/"):
            if let font = Self.font(named: String(path.dropFirst("/pano/font/".count))) {
                send(status: "200 OK", type: "font/woff2", body: font, on: connection)
            } else {
                send(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
            }
        case _ where path.hasPrefix("/pano/img/"):
            let name = String(path.dropFirst("/pano/img/".count))
            if let image = panoImages[name] {
                send(status: "200 OK", type: name.hasSuffix(".png") ? "image/png" : "image/jpeg", body: image, on: connection)
            } else {
                send(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
            }
        case "/ended":
            // Video bitti: aynı video tekrar açılmasın.
            if mode == .video { mode = .idle }
            send(status: "204 No Content", type: "text/plain", body: Data(), on: connection)
        case "/state":
            lastPoll = Date()
            let json = #"{"mode":"\#(mode.rawValue)","frame":\#(frameVersion),"video":\#(videoVersion)}"#
            send(status: "200 OK", type: "application/json", body: Data(json.utf8), on: connection)
        case "/stream.mjpg":
            startStream(on: connection)
        case "/frame.jpg":
            if let frame {
                send(status: "200 OK", type: "image/jpeg", body: frame, on: connection)
            } else {
                send(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
            }
        case "/video.mp4":
            if let videoURL { sendFile(videoURL, range: range, on: connection) } else {
                send(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
            }
        default:
            send(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
        }
    }

    private func header(status: String, type: String, length: Int, extra: String = "") -> Data {
        Data(("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(length)\r\n"
            + "Cache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\(extra)\r\n").utf8)
    }

    private func send(status: String, type: String, body: Data, on connection: NWConnection) {
        connection.send(content: header(status: status, type: type, length: body.count) + body,
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Videoyu parça parça gönderir; TV oynatıcısı `Range: bytes=…` ile ileri sarabilir.
    private func sendFile(_ url: URL, range: String?, on connection: NWConnection) {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        else {
            send(status: "404 Not Found", type: "text/plain", body: Data(), on: connection)
            return
        }
        var start = 0
        var end = size - 1
        var status = "200 OK"
        var extra = "Accept-Ranges: bytes\r\n"
        if let range, let spec = range.split(separator: "=").last {
            let bounds = spec.split(separator: "-", omittingEmptySubsequences: false)
            start = Int(bounds.first ?? "") ?? 0
            if bounds.count > 1, let last = Int(bounds[1]) { end = min(last, size - 1) }
            status = "206 Partial Content"
            extra += "Content-Range: bytes \(start)-\(end)/\(size)\r\n"
        }
        guard start <= end else {
            send(status: "416 Range Not Satisfiable", type: "text/plain", body: Data(), on: connection)
            return
        }
        try? handle.seek(toOffset: UInt64(start))
        connection.send(content: header(status: status, type: "video/mp4", length: end - start + 1, extra: extra),
                        completion: .contentProcessed { _ in })
        sendChunks(handle, remaining: end - start + 1, on: connection)
    }

    private func sendChunks(_ handle: FileHandle, remaining: Int, on connection: NWConnection) {
        guard remaining > 0, let chunk = try? handle.read(upToCount: min(256 * 1024, remaining)), !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            if error != nil { try? handle.close(); connection.cancel(); return }
            self?.sendChunks(handle, remaining: remaining - chunk.count, on: connection)
        })
    }

    // MARK: - TV sayfası

    /// TV'nin HbbTV tarayıcısı sayfayı katı XHTML olarak okur: betikler CDATA içinde olmalı.
    /// Videoyu JavaScript ile eklemek ya da başlatmak TV'nin uygulamayı kapatmasına yol açıyor (13.10.2026'da
    /// denendi); bu yüzden video, `<video>` etiketinin doğrudan yazıldığı ayrı bir sayfada oynatılır.
    static let page = """
    <!DOCTYPE html PUBLIC "-//HbbTV//1.1.1//EN" "http://www.hbbtv.org/dtd/HbbTV-1.1.1.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml">
    <head>
    <meta http-equiv="Content-Type" content="application/vnd.hbbtv.xhtml+xml; charset=UTF-8" />
    <title>Pilsiz</title>
    <style>
      body { margin: 0; width: 1280px; height: 720px; background: #000; overflow: hidden; font-family: sans-serif; }
      #idle { position: absolute; left: 0; top: 0; width: 1280px; height: 720px; background: #121214; color: #fff; text-align: center; }
      #idle h1 { margin-top: 270px; font-size: 64px; color: #ee2e45; }
      #idle p { font-size: 26px; color: #aaa; }
      #img { position: absolute; left: 0; top: 0; width: 1280px; height: 720px; object-fit: contain; display: none; }
    </style>
    </head>
    <body>
    <object type="application/oipfApplicationManager" id="appmgr" style="position:absolute;width:0;height:0"></object>
    <div id="idle"><h1>Pilsiz</h1><p>Mac'ten gönderilecek içerik bekleniyor</p></div>
    <img id="img" alt="" />
    <script type="text/javascript">//<![CDATA[
      var app = null;
      try { app = document.getElementById('appmgr').getOwnerApplication(document); app.show(); } catch (e) {}
      var streaming = false, mode = 'idle';
      var seen = location.search.match(/seen=(\\d+)/);
      var shownVideo = seen ? parseInt(seen[1], 10) : 0;
      var img = document.getElementById('img');
      function show(id) {
        document.getElementById('idle').style.display = id === 'idle' ? 'block' : 'none';
        img.style.display = id === 'img' ? 'block' : 'none';
      }
      // Kareler tek bir MJPEG bağlantısından gelir; koparsa bir sonraki yoklamada yeniden açılır.
      img.onload = function () { show('img'); };
      img.onerror = function () { streaming = false; };
      function startStream() {
        if (streaming) { return; }
        streaming = true;
        img.src = '/stream.mjpg?t=' + new Date().getTime();
      }
      function stopStream() {
        if (!streaming) { return; }
        streaming = false;
        img.src = '';
      }
      function apply(state) {
        mode = state.mode;
        if (mode === 'close') { try { app.destroyApplication(); } catch (e) {} return; }
        if (mode === 'dashboard') { stopStream(); location.href = '/pano.html'; return; }
        if (mode === 'frames') { startStream(); }
        if (mode === 'video' && state.video !== shownVideo) { stopStream(); location.href = '/video.html'; return; }
        if (mode === 'idle') { stopStream(); show('idle'); }
      }
      function poll() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
          if (x.readyState !== 4) { return; }
          if (x.status === 200) { try { apply(JSON.parse(x.responseText)); } catch (e) {} }
          setTimeout(poll, 500);
        };
        x.open('GET', '/state?t=' + new Date().getTime());
        x.send(null);
      }
      poll();
    //]]></script>
    </body>
    </html>
    """

    /// Yalnızca video: `<video>` doğrudan yazılı. Mod değişince ya da video bitince ana sayfaya döner.
    static func videoPage(version: Int) -> String {
        """
        <!DOCTYPE html PUBLIC "-//HbbTV//1.1.1//EN" "http://www.hbbtv.org/dtd/HbbTV-1.1.1.dtd">
        <html xmlns="http://www.w3.org/1999/xhtml">
        <head>
        <meta http-equiv="Content-Type" content="application/vnd.hbbtv.xhtml+xml; charset=UTF-8" />
        <title>Pilsiz</title>
        <style>body { margin: 0; width: 1280px; height: 720px; background: #000; overflow: hidden; }</style>
        </head>
        <body>
        <object type="application/oipfApplicationManager" id="appmgr" style="position:absolute;width:0;height:0"></object>
        <video id="v" src="/video.mp4?v=\(version)" width="1280" height="720" autoplay="autoplay"></video>
        <script type="text/javascript">//<![CDATA[
          var app = null;
          try { app = document.getElementById('appmgr').getOwnerApplication(document); app.show(); } catch (e) {}
          var mine = \(version), v = document.getElementById('v'), leaving = false;
          function leave(note) {
            if (leaving) { return; }
            leaving = true;
            if (note) { var y = new XMLHttpRequest(); y.open('GET', '/ended?v=' + mine); y.send(null); }
            location.href = '/?seen=' + mine;
          }
          function poll() {
            if (v.ended) { leave(true); return; }
            var x = new XMLHttpRequest();
            x.onreadystatechange = function () {
              if (x.readyState !== 4) { return; }
              if (x.status === 200) {
                try {
                  var s = JSON.parse(x.responseText);
                  if (s.mode === 'close') { try { app.destroyApplication(); } catch (e) {} return; }
                  if (s.mode !== 'video' || s.video !== mine) { leave(false); return; }
                } catch (e) {}
              }
              setTimeout(poll, 500);
            };
            x.open('GET', '/state?t=' + new Date().getTime());
            x.send(null);
          }
          poll();
        //]]></script>
        </body>
        </html>
        """
    }
}
