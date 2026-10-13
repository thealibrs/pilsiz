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
        body: String? = nil, origin: String? = nil, timeout: TimeInterval = 3
    ) async throws -> HTTPResponse {
        let bodyData = Data((body ?? "").utf8)
        var head = "\(method) \(path) HTTP/1.1\r\nHost: \(host):\(port)\r\nConnection: close\r\n"
        if let origin { head += "Origin: \(origin)\r\n" }
        if body != nil { head += "Content-Type: application/xml\r\n" }
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
    private let queue = DispatchQueue(label: "tvkumanda.http")
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

    static func send(_ code: Int, to host: String) async throws {
        // Not: TV, kod değerinin tırnaksız gönderilmesini bekliyor.
        let response = try await RawHTTP.request(
            host: host, port: port, method: "POST", path: "/apps/SmartCenter",
            body: "<remote><key code=\(code) /></remote>"
        )
        guard (200..<300).contains(response.status) else { throw TVError.http(response.status) }
    }

    /// DIAL ile bir uygulama başlatır (ör. "Netflix").
    static func launch(app: String, on host: String) async throws {
        let response = try await RawHTTP.request(
            host: host, port: port, method: "POST", path: "/apps/\(app)", origin: origin(for: app)
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
