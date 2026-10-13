import Foundation
import Network

/// TV'deki "Pilsiz Ekranı" HbbTV sayfasının bağlandığı yerel HTTP sunucusu.
///
/// Uç noktalar:
/// - `GET /`            HbbTV sayfası
/// - `GET /state`       `{"mode":…, "frame":n, "video":n}` (sayfa ~300 ms'de bir sorar)
/// - `GET /frame.jpg`   son kare (ekran yansıtma ya da fotoğraf)
/// - `GET /video.mp4`   gönderilen video, Range destekli
///
/// Tüm durum tek bir seri kuyrukta tutulur.
final class ShareServer: @unchecked Sendable {
    enum Mode: String, Sendable { case idle, frames, video, close }

    static let port: UInt16 = 8765

    private let queue = DispatchQueue(label: "pilsiz.share")
    private var listener: NWListener?
    private var mode: Mode = .idle
    private var frame: Data?
    private var frameVersion = 0
    private var videoURL: URL?
    private var videoVersion = 0
    private var lastPoll: Date?
    private var pageFetched: Date?

    var isRunning: Bool { queue.sync { listener != nil } }

    /// TV sayfası son 2 saniyede durum sorduysa bağlıdır.
    var isConnected: Bool { queue.sync { lastPoll.map { Date().timeIntervalSince($0) < 2 } ?? false } }

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
        }
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
        let path = parts.count > 1 ? String(parts[1].split(separator: "?").first ?? "") : "/"
        let range = lines.first { $0.lowercased().hasPrefix("range:") }

        switch path {
        case "/", "/index.html":
            pageFetched = Date()
            send(status: "200 OK", type: "application/vnd.hbbtv.xhtml+xml; charset=UTF-8", body: Data(Self.page.utf8), on: connection)
        case "/video.html":
            send(status: "200 OK", type: "application/vnd.hbbtv.xhtml+xml; charset=UTF-8",
                 body: Data(Self.videoPage(version: videoVersion).utf8), on: connection)
        case "/ended":
            // Video bitti: aynı video tekrar açılmasın.
            if mode == .video { mode = .idle }
            send(status: "204 No Content", type: "text/plain", body: Data(), on: connection)
        case "/state":
            lastPoll = Date()
            let json = #"{"mode":"\#(mode.rawValue)","frame":\#(frameVersion),"video":\#(videoVersion)}"#
            send(status: "200 OK", type: "application/json", body: Data(json.utf8), on: connection)
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
      var shownFrame = -1, wantedFrame = 0, loading = false, mode = 'idle';
      var seen = location.search.match(/seen=(\\d+)/);
      var shownVideo = seen ? parseInt(seen[1], 10) : 0;
      var img = document.getElementById('img');
      function show(id) {
        document.getElementById('idle').style.display = id === 'idle' ? 'block' : 'none';
        img.style.display = id === 'img' ? 'block' : 'none';
      }
      img.onload = function () { loading = false; show('img'); nextFrame(); };
      img.onerror = function () { loading = false; };
      function nextFrame() {
        if (mode !== 'frames' || loading || shownFrame === wantedFrame) { return; }
        loading = true; shownFrame = wantedFrame;
        img.src = '/frame.jpg?v=' + wantedFrame;
      }
      function apply(state) {
        mode = state.mode;
        if (mode === 'close') { try { app.destroyApplication(); } catch (e) {} return; }
        if (mode === 'frames') { wantedFrame = state.frame; nextFrame(); }
        if (mode === 'video' && state.video !== shownVideo) { location.href = '/video.html'; return; }
        if (mode === 'idle') { show('idle'); }
      }
      function poll() {
        var x = new XMLHttpRequest();
        x.onreadystatechange = function () {
          if (x.readyState !== 4) { return; }
          if (x.status === 200) { try { apply(JSON.parse(x.responseText)); } catch (e) {} }
          setTimeout(poll, mode === 'frames' ? 150 : 400);
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
