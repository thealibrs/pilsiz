import Foundation
import Network

enum TVError: LocalizedError, Equatable {
    case timeout
    case badResponse
    case http(Int)
    case badMAC
    case socket

    var errorDescription: String? {
        switch self {
        case .timeout: "TV yanıt vermedi"
        case .badResponse: "TV'den anlaşılmayan yanıt"
        case .http(let code): "TV hata döndürdü (HTTP \(code))"
        case .badMAC: "MAC adresi geçersiz"
        case .socket: "Ağ soketi açılamadı"
        }
    }
}

struct HTTPResponse: Sendable {
    let status: Int
    let body: String
}

/// Minimal HTTP/1.1 istemcisi. TV'nin gömülü sunucusu bağlantı tekrar kullanımında
/// takılabildiği için her istek kendi TCP bağlantısını açar ve `Connection: close` gönderir.
enum RawHTTP {
    static func request(
        host: String, port: UInt16, method: String, path: String,
        body: String? = nil, contentType: String = "application/xml", origin: String? = nil,
        headers: [String: String] = [:], timeout: TimeInterval = 3
    ) async throws -> HTTPResponse {
        let bodyData = Data((body ?? "").utf8)
        var head = "\(method) \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nConnection: close\r\n"
        if let origin { head += "Origin: \(origin)\r\n" }
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        if body != nil { head += "Content-Type: \(contentType)\r\n" }
        if body != nil || method == "POST" { head += "Content-Length: \(bodyData.count)\r\n" }
        head += "\r\n"

        // IP adresleri doğrudan kullanılır; DNS çözümleyicisine gerek yok.
        let endpointHost: NWEndpoint.Host = IPv4Address(host).map { .ipv4($0) } ?? NWEndpoint.Host(host)
        let conn = NWConnection(
            host: endpointHost,
            port: NWEndpoint.Port(rawValue: port)!,
            using: .tcp
        )
        return try await HTTPExchange(conn: conn).run(payload: Data(head.utf8) + bodyData, timeout: timeout)
    }
}

/// Tüm callback'ler tek bir seri kuyrukta çalışır; bu yüzden durum güvenle değiştirilebilir.
private final class HTTPExchange: @unchecked Sendable {
    private let conn: NWConnection
    private let queue = DispatchQueue(label: "pilsiz.http")
    private var buffer = Data()
    private var continuation: CheckedContinuation<HTTPResponse, Error>?

    init(conn: NWConnection) { self.conn = conn }

    func run(payload: Data, timeout: TimeInterval) async throws -> HTTPResponse {
        try await withCheckedThrowingContinuation { cont in
            queue.async {
                self.continuation = cont
                self.conn.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        self.conn.send(content: payload, completion: .contentProcessed { error in
                            if let error { self.finish(.failure(error)) } else { self.receive() }
                        })
                    case .failed(let error), .waiting(let error):
                        self.finish(.failure(error))
                    default:
                        break
                    }
                }
                self.conn.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + timeout) { self.finish(.failure(TVError.timeout)) }
            }
        }
    }

    private func receive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            if let data { self.buffer.append(data) }
            if isComplete || error != nil { self.finish(self.parse()) } else { self.receive() }
        }
    }

    private func parse() -> Result<HTTPResponse, Error> {
        let text = String(decoding: buffer, as: UTF8.self)
        guard let headerEnd = text.range(of: "\r\n\r\n") else { return .failure(TVError.badResponse) }
        let statusLine = text[..<headerEnd.lowerBound].prefix { $0 != "\r" }
        let parts = statusLine.split(separator: " ")
        guard parts.count >= 2, let code = Int(parts[1]) else { return .failure(TVError.badResponse) }
        return .success(HTTPResponse(status: code, body: String(text[headerEnd.upperBound...])))
    }

    private func finish(_ result: Result<HTTPResponse, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        conn.stateUpdateHandler = nil
        conn.cancel()
        cont.resume(with: result)
    }
}

/// Vestel SmartCenter (DIAL) protokolü.
enum SmartCenter {
    static let port: UInt16 = 56789

    /// SmartCenter uygulamasının kendini tanıttığı başlık; komutlar bununla gönderilir.
    private static let appHeader = ["application_name": "tv smart centre"]

    private static func post(_ body: String, to host: String) async throws {
        let response = try await RawHTTP.request(
            host: host, port: port, method: "POST", path: "/apps/SmartCenter", body: body, headers: appHeader
        )
        guard (200..<300).contains(response.status) else { throw TVError.http(response.status) }
    }

    /// Metni TV'deki etkin yazı alanına harf harf yazar.
    static func type(_ text: String, to host: String) async throws {
        for scalar in text.unicodeScalars {
            try await post("<?xml version='1.0' ?><keyboard><key value='\(scalar.value)'/></keyboard>", to: host)
        }
    }

    /// İmleci göreli olarak taşır (telefon uygulaması gibi ~60 Hz küçük adımlar).
    static func moveCursor(dx: Double, dy: Double, on host: String) async throws {
        let body = String(format: "<?xml version='1.0'?><mouseevent><event_data dx='%.1f' dy='%.1f' button='0'/></mouseevent>", dx, dy)
        try await post(body, to: host)
    }

    struct Service: Sendable {
        let number: Int
        let name: String
        let type: Int

        /// 2 = radyo; geri kalanlar (1, 22, 25 yayın, 131 internet kanalı) izlenebilir.
        var isTV: Bool { type != 2 }
    }

    /// TV'nin kanal listesini ister. Yanıt HTTP'den değil, 7681 portundaki WebSocket'ten gelir.
    static func channelList(from host: String) async throws -> [Service] {
        guard let url = URL(string: "ws://\(host):7681/") else { throw TVError.badResponse }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.maximumMessageSize = 4 * 1024 * 1024
        socket.resume()
        defer { socket.cancel(with: .goingAway, reason: nil) }

        // TV listeyi yalnızca o an bağlı istemcilere yollar: komuttan önce bağlantı açılmış olmalı.
        // Ping'in yanıtı bağlantının kurulduğunu gösterir.
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            socket.sendPing { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        try await post("<?xml version='1.0'?><command>activechannellist</command>", to: host)
        return try await withThrowingTaskGroup(of: [Service].self) { group in
            group.addTask {
                while true {
                    let text: String
                    switch try await socket.receive() {
                    case .string(let string): text = string
                    case .data(let data): text = String(decoding: data, as: UTF8.self)
                    @unknown default: continue
                    }
                    if text.hasPrefix("<active_list") { return parseServices(text) }
                }
            }
            group.addTask {
                try await Task.sleep(for: .seconds(10))
                throw TVError.timeout
            }
            // receive() iptali dinlemediği için grup kapanmadan önce soket de kapatılır.
            defer {
                group.cancelAll()
                socket.cancel(with: .goingAway, reason: nil)
            }
            return try await group.next() ?? []
        }
    }

    /// TV adlarda "&" karakterini kaçırmadan gönderdiği için XML ayrıştırıcı yerine esnek okuma.
    static func parseServices(_ text: String) -> [Service] {
        let attribute = /(\w+)='([^']*)'/
        return text.matches(of: /<service ([^>]*)\/>/).compactMap { match in
            var values: [String: String] = [:]
            for pair in String(match.output.1).matches(of: attribute) {
                values[String(pair.output.1)] = String(pair.output.2)
            }
            guard let number = values["rsn"].flatMap(Int.init), let name = values["name"] else { return nil }
            let cleaned = name
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&apos;", with: "'")
                .trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
            return Service(number: number, name: cleaned, type: values["type"].flatMap(Int.init) ?? 0)
        }
    }

    static func send(_ code: Int, to host: String) async throws {
        // Not: TV, kod değerinin tırnaksız gönderilmesini bekliyor.
        let response = try await RawHTTP.request(
            host: host, port: port, method: "POST", path: "/apps/SmartCenter",
            body: "<remote><key code=\(code) /></remote>"
        )
        guard (200..<300).contains(response.status) else { throw TVError.http(response.status) }
    }

    /// DIAL ile bir uygulama başlatır (ör. "Netflix").
    /// TV'de bir web sayfasını HbbTV uygulaması olarak açar (Vewd DIAL sunucusu, port 12345).
    /// TV her açılışta "Evet/Hayır" onayı sorar; yanıt onaya kadar bekleyebildiği için zaman aşımı hata sayılmaz.
    static func launchHbbTV(url: String, on host: String) async throws {
        let base = url.hasSuffix("/") ? url : url + "/"
        let ait = """
        <?xml version="1.0" encoding="UTF-8"?>
        <mhp:ServiceDiscovery xmlns:mhp="urn:dvb:mhp:2009" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
          <mhp:ApplicationDiscovery DomainName="pilsiz.local">
            <mhp:ApplicationList>
              <mhp:Application>
                <mhp:appName Language="tur">Pilsiz</mhp:appName>
                <mhp:applicationIdentifier><mhp:orgId>1</mhp:orgId><mhp:appId>1</mhp:appId></mhp:applicationIdentifier>
                <mhp:applicationDescriptor>
                  <mhp:type><mhp:OtherApp>application/vnd.hbbtv.xhtml+xml</mhp:OtherApp></mhp:type>
                  <mhp:controlCode>AUTOSTART</mhp:controlCode>
                  <mhp:visibility>VISIBLE_ALL</mhp:visibility>
                  <mhp:serviceBound>false</mhp:serviceBound>
                  <mhp:priority>1</mhp:priority>
                  <mhp:version>01</mhp:version>
                  <mhp:mhpVersion><mhp:profile>0</mhp:profile><mhp:versionMajor>1</mhp:versionMajor><mhp:versionMinor>3</mhp:versionMinor><mhp:versionMicro>1</mhp:versionMicro></mhp:mhpVersion>
                </mhp:applicationDescriptor>
                <mhp:applicationTransport xsi:type="mhp:HTTPTransportType"><mhp:URLBase>\(base)</mhp:URLBase></mhp:applicationTransport>
                <mhp:applicationLocation>index.html</mhp:applicationLocation>
              </mhp:Application>
            </mhp:ApplicationList>
          </mhp:ApplicationDiscovery>
        </mhp:ServiceDiscovery>
        """
        do {
            let response = try await RawHTTP.request(
                host: host, port: 12345, method: "POST", path: "/apps/HbbTV", body: ait,
                contentType: "text/plain; charset=utf-8", timeout: 3
            )
            guard (200..<300).contains(response.status) else { throw TVError.http(response.status) }
        } catch TVError.timeout {
            // Onay bekleniyor.
        }
    }

    /// Çalışan DIAL uygulamasını kapatır (DIAL: `DELETE` çalışma adresine; TV `allowStop="true"` bildiriyor).
    /// Çalışma adresi uygulamanın durum yanıtındaki `<link rel="run" href=…>` bağlantısından okunur.
    static func stop(app: String, on host: String) async throws {
        let state = try await RawHTTP.request(
            host: host, port: port, method: "GET", path: "/apps/\(app)", origin: origin(for: app)
        )
        let run = state.body.firstMatch(of: /<link[^>]*rel="run"[^>]*href="([^"]+)"/).map { String($0.output.1) } ?? "run"
        let response = try await RawHTTP.request(
            host: host, port: port, method: "DELETE", path: "/apps/\(app)/\(run)", origin: origin(for: app)
        )
        guard (200..<300).contains(response.status) else { throw TVError.http(response.status) }
    }

    static func launch(app: String, on host: String, body: String? = nil) async throws {
        let response = try await RawHTTP.request(
            host: host, port: port, method: "POST", path: "/apps/\(app)", body: body,
            contentType: "text/plain; charset=utf-8", origin: origin(for: app)
        )
        guard (200..<300).contains(response.status) else { throw TVError.http(response.status) }
    }

    static func isRunning(app: String, on host: String) async -> Bool {
        guard let response = try? await RawHTTP.request(
            host: host, port: port, method: "GET", path: "/apps/\(app)", origin: origin(for: app)
        ) else { return false }
        return response.status == 200 && response.body.contains("<state>running</state>")
    }

    /// YouTube'un DIAL servisi, YouTube kaynaklı görünmeyen isteklere 403 döndürüyor.
    private static func origin(for app: String) -> String? {
        app == "YouTube" ? "https://www.youtube.com" : nil
    }

    /// TV'nin kendini tanıttığı ad ve üretici (UPnP aygıt tanımı: `DAEWOO_43DE54F 43" SMART TV`, `VESTEL`).
    static func deviceInfo(_ host: String) async -> (name: String, manufacturer: String)? {
        guard let response = try? await RawHTTP.request(host: host, port: 56790, method: "GET", path: "/dd.xml"),
              response.status == 200 else { return nil }
        func tag(_ name: String) -> String {
            guard let regex = try? Regex("<\(name)>([^<]*)</\(name)>"),
                  let match = response.body.firstMatch(of: regex),
                  let value = match.output[1].substring else { return "" }
            return String(value).trimmingCharacters(in: .whitespaces)
        }
        let info = (name: tag("friendlyName"), manufacturer: tag("manufacturer"))
        return info.name.isEmpty && info.manufacturer.isEmpty ? nil : info
    }

    /// Panelde gösterilecek kısa ad: `DAEWOO_43DE54F 43" SMART TV` + `VESTEL` → "Daewoo 43DE54F · Vestel".
    static func modelLabel(name: String, manufacturer: String) -> String {
        var words = name.replacingOccurrences(of: "_", with: " ").split(separator: " ").map(String.init)
        // Sondaki ekran boyu ve "SMART TV" atılır.
        while let last = words.last, ["SMART", "TV"].contains(last.uppercased()) || last.hasSuffix("\"") || last.hasSuffix("”") {
            words.removeLast()
        }
        // Tamamı büyük harfli marka adları ("DAEWOO") düzeltilir; model kodları ("43DE54F") olduğu gibi kalır.
        let pretty = { (word: String) in word == word.uppercased() && word.allSatisfy(\.isLetter) ? word.capitalized : word }
        let model = words.map(pretty).joined(separator: " ")
        let maker = pretty(manufacturer)
        if maker.isEmpty || model.localizedCaseInsensitiveContains(maker) { return model.isEmpty ? maker : model }
        return model.isEmpty ? maker : "\(model) · \(maker)"
    }

    static func isOnline(_ host: String, timeout: TimeInterval = 2) async -> Bool {
        guard let response = try? await RawHTTP.request(
            host: host, port: port, method: "GET", path: "/apps/SmartCenter", timeout: timeout
        ) else { return false }
        return response.status == 200 && response.body.contains("SmartCenter")
    }

    /// Bağlı olunan /24 ağlarını tarar ve SmartCenter yanıtı veren cihazları döndürür.
    static func discover() async -> [String] {
        let candidates = LocalNetwork.interfaces().flatMap { iface -> [String] in
            let octets = iface.address.split(separator: ".")
            guard octets.count == 4 else { return [] }
            let prefix = octets.prefix(3).joined(separator: ".")
            return (1...254).map { "\(prefix).\($0)" }.filter { $0 != iface.address }
        }
        // Aynı anda en fazla 32 bağlantı: yüzlerce eşzamanlı bağlantı sistem kaynaklarını tüketiyor.
        let ips = Array(Set(candidates))
        var found: [String] = []
        for start in stride(from: 0, to: ips.count, by: 32) {
            let batch = ips[start..<min(start + 32, ips.count)]
            await withTaskGroup(of: String?.self) { group in
                for ip in batch {
                    group.addTask { await isOnline(ip, timeout: 1.2) ? ip : nil }
                }
                for await ip in group { if let ip { found.append(ip) } }
            }
        }
        return found.sorted()
    }
}

enum LocalNetwork {
    struct Interface {
        let address: String
        let broadcast: String?
    }

    static func interfaces() -> [Interface] {
        var result: [Interface] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let broadcast = (flags & IFF_BROADCAST != 0) ? ifa.ifa_dstaddr.flatMap(ipString) : nil
            if let ip = ipString(addr) { result.append(Interface(address: ip, broadcast: broadcast)) }
        }
        return result
    }

    private static func ipString(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        return String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// ARP tablosundan bir IP'nin MAC adresini okur (TV o an açıkken çalışır).
    static func macAddress(for ip: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/arp")
        process.arguments = ["-n", ip]
        let pipe = Pipe()
        process.standardOutput = pipe
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard let range = output.range(of: " at "),
              let raw = output[range.upperBound...].split(separator: " ").first,
              let mac = WakeOnLAN.normalize(String(raw)) else { return nil }
        return mac
    }
}

enum WakeOnLAN {
    /// "aa:bb:cc:4:dd:ee" → "aa:bb:cc:04:dd:ee"
    static func normalize(_ mac: String) -> String? {
        let bytes = parse(mac)
        guard bytes.count == 6 else { return nil }
        return bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
    }

    private static func parse(_ mac: String) -> [UInt8] {
        let parts = mac.split { $0 == ":" || $0 == "-" }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        return bytes.count == parts.count ? bytes : []
    }

    static func send(mac: String) throws {
        let target = parse(mac)
        guard target.count == 6 else { throw TVError.badMAC }
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: target, count: 16).joined())

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw TVError.socket }
        defer { close(fd) }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, socklen_t(MemoryLayout<Int32>.size))

        let targets = Set(["255.255.255.255"] + LocalNetwork.interfaces().compactMap(\.broadcast))
        for address in targets {
            for port: UInt16 in [9, 7] {
                var sin = sockaddr_in()
                sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                sin.sin_family = sa_family_t(AF_INET)
                sin.sin_port = port.bigEndian
                inet_pton(AF_INET, address, &sin.sin_addr)
                _ = withUnsafePointer(to: &sin) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        sendto(fd, packet, packet.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
            }
        }
    }
}
