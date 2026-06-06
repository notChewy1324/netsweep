import Foundation
import Network

// MARK: - Banner grabbing
// Connect to a TCP port and read whatever the service announces. Many services
// send a banner immediately (SSH, FTP, SMTP, Redis). For HTTP we send a minimal
// HEAD request to elicit a Server: header. This gives real fingerprinting
// (software + version) instead of guessing from the port number alone.

struct Banner {
    let port: UInt16
    let raw: String
    var product: String?      // parsed software name
    var version: String?      // parsed version if present
    var summary: String {
        if let p = product {
            return version.map { "\(p) \($0)" } ?? p
        }
        return raw.isEmpty ? "—" : String(raw.prefix(60))
    }
}

enum BannerGrabber {

    // Ports where the server speaks first (we just read).
    private static let serverSpeaksFirst: Set<UInt16> = [21, 22, 25, 110, 143, 6379, 3306, 5432]

    static func grab(host: String, port: UInt16, timeout: TimeInterval = 3) async -> Banner? {
        let raw = await readBanner(host: host, port: port, timeout: timeout,
                                   probe: probeBytes(for: port))
        guard let raw, !raw.isEmpty else { return nil }
        var banner = Banner(port: port, raw: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        parse(&banner)
        return banner
    }

    // For HTTP-ish ports, send a HEAD so the server responds; otherwise nothing.
    private static func probeBytes(for port: UInt16) -> Data? {
        if serverSpeaksFirst.contains(port) { return nil }
        let httpPorts: Set<UInt16> = [80, 8080, 8000, 8888, 9000, 443, 8443]
        if httpPorts.contains(port) {
            return Data("HEAD / HTTP/1.0\r\n\r\n".utf8)
        }
        return Data("\r\n".utf8)   // nudge anything else
    }

    private static func readBanner(host: String, port: UInt16, timeout: TimeInterval,
                                   probe: Data?) async -> String? {
        await withCheckedContinuation { cont in
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                cont.resume(returning: nil); return
            }
            let conn = NWConnection(host: .init(host), port: nwPort, using: .tcp)
            let resumed = Lock(false)

            @Sendable func finish(_ s: String?) {
                if resumed.swap(true) == false { conn.cancel(); cont.resume(returning: s) }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let probe { conn.send(content: probe, completion: .idempotent) }
                    conn.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, _, _, _ in
                        if let data, let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) {
                            finish(s)
                        } else { finish(nil) }
                    }
                case .failed, .cancelled:
                    finish(nil)
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }

    // Pull product/version out of common banner shapes.
    private static func parse(_ b: inout Banner) {
        let raw = b.raw
        // SSH: "SSH-2.0-OpenSSH_8.9p1 Ubuntu"
        if raw.hasPrefix("SSH-") {
            let parts = raw.split(separator: "-", maxSplits: 2)
            if parts.count >= 3 {
                let sw = parts[2].split(separator: " ").first.map(String.init) ?? String(parts[2])
                let comps = sw.split(separator: "_")
                b.product = comps.first.map(String.init)
                if comps.count > 1 { b.version = String(comps[1]) }
            }
            return
        }
        // HTTP: find "Server:" header
        if let range = raw.range(of: "Server:", options: .caseInsensitive) {
            let line = raw[range.upperBound...].prefix { $0 != "\r" && $0 != "\n" }
            let server = line.trimmingCharacters(in: .whitespaces)
            let comps = server.split(separator: "/")
            b.product = comps.first.map(String.init)
            if comps.count > 1 { b.version = comps[1].split(separator: " ").first.map(String.init) }
            return
        }
        // FTP: "220 ProFTPD 1.3.5 Server"
        if raw.hasPrefix("220") {
            let tokens = raw.dropFirst(3).trimmingCharacters(in: .whitespaces).split(separator: " ")
            if let first = tokens.first { b.product = String(first) }
            if tokens.count > 1, tokens[1].first?.isNumber == true { b.version = String(tokens[1]) }
            return
        }
        // Redis: "-NOAUTH" or "+PONG" etc → at least identify it
        if raw.contains("Redis") || raw.hasPrefix("-NOAUTH") || raw.hasPrefix("-ERR") {
            b.product = "Redis"
            return
        }
        // SMTP: "220 mail.example.com ESMTP Postfix"
        if raw.hasPrefix("220"), raw.contains("SMTP") || raw.contains("ESMTP") {
            if raw.contains("Postfix") { b.product = "Postfix" }
            else if raw.contains("Exim") { b.product = "Exim" }
            else if raw.contains("Sendmail") { b.product = "Sendmail" }
            else { b.product = "SMTP" }
        }
    }
}
