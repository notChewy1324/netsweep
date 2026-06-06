import Foundation

// MARK: - DNS (forward + reverse) via getaddrinfo/getnameinfo

enum DNS {
    /// Forward lookup: hostname -> [IPs]
    static func resolve(host: String) async -> [String] {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC,
                                     ai_socktype: SOCK_STREAM, ai_protocol: 0,
                                     ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
                var res: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else {
                    cont.resume(returning: []); return
                }
                defer { freeaddrinfo(res) }
                var out: [String] = []
                var p: UnsafeMutablePointer<addrinfo>? = first
                while let cur = p {
                    var buf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(cur.pointee.ai_addr, cur.pointee.ai_addrlen,
                                   &buf, socklen_t(buf.count), nil, 0, NI_NUMERICHOST) == 0 {
                        let s = String(cString: buf)
                        if !out.contains(s) { out.append(s) }
                    }
                    p = cur.pointee.ai_next
                }
                cont.resume(returning: out)
            }
        }
    }

    /// Reverse lookup: IP -> hostname (best effort, short timeout in practice)
    static func reverse(ip: String) async -> String? {
        await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var sa = sockaddr_in()
                sa.sin_family = sa_family_t(AF_INET)
                sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
                inet_pton(AF_INET, ip, &sa.sin_addr)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let result = withUnsafePointer(to: &sa) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size),
                                    &host, socklen_t(host.count), nil, 0, NI_NAMEREQD)
                    }
                }
                if result == 0 {
                    let name = String(cString: host)
                    cont.resume(returning: name.isEmpty ? nil : name)
                } else {
                    cont.resume(returning: nil)
                }
            }
        }
    }
}

// MARK: - Common service names

enum Services {
    static let map: [UInt16: String] = [
        20: "ftp-data", 21: "ftp", 22: "ssh", 23: "telnet", 25: "smtp",
        53: "dns", 67: "dhcp", 68: "dhcp", 80: "http", 110: "pop3",
        123: "ntp", 135: "msrpc", 137: "netbios", 139: "netbios-ssn",
        143: "imap", 161: "snmp", 389: "ldap", 443: "https", 445: "smb",
        465: "smtps", 514: "syslog", 515: "printer", 548: "afp", 554: "rtsp",
        587: "submission", 631: "ipp", 636: "ldaps", 873: "rsync",
        989: "ftps", 990: "ftps", 993: "imaps", 995: "pop3s",
        1080: "socks", 1433: "mssql", 1521: "oracle", 1883: "mqtt",
        1900: "ssdp", 2049: "nfs", 3000: "dev-http", 3306: "mysql",
        3389: "rdp", 5000: "upnp/airplay", 5060: "sip", 5353: "mdns",
        5432: "postgres", 5555: "adb", 5900: "vnc", 6379: "redis",
        7000: "airplay", 8000: "http-alt", 8080: "http-proxy",
        8443: "https-alt", 8888: "http-alt", 9000: "http-alt",
        9100: "jetdirect", 9200: "elastic", 11211: "memcached",
        27017: "mongodb", 32400: "plex", 49152: "upnp", 62078: "iphone-sync"
    ]
    static func name(_ port: UInt16) -> String { map[port] ?? "unknown" }
}

// MARK: - Device fingerprint heuristics (port-signature guessing)

enum Fingerprint {
    static func guess(openPorts: Set<UInt16>) -> String? { guess(openPorts: Array(openPorts)) }
    static func guess(openPorts: [UInt16]) -> String? {
        let p = Set(openPorts)
        if p.contains(62078) { return "Apple device (iPhone/iPad)" }
        if p.contains(7000) || p.contains(5000) { return "AirPlay / Apple TV / HomePod" }
        if p.contains(9100) || p.contains(515) || p.contains(631) { return "Network printer" }
        if p.contains(32400) { return "Plex media server" }
        if p.contains(445) && p.contains(139) { return "Windows / SMB host" }
        if p.contains(22) && p.contains(80) { return "Linux server / router" }
        if p.contains(53) && (p.contains(80) || p.contains(443)) { return "Router / gateway" }
        if p.contains(8080) || p.contains(80) { return "Web service / IoT device" }
        if p.contains(22) { return "SSH host (server/Pi)" }
        return nil
    }
}

// MARK: - Port set presets

enum PortSets {
    static let top20: [UInt16] = [21,22,23,25,53,80,110,139,143,443,445,993,995,1723,3306,3389,5900,8080,8443,62078]
    static let web: [UInt16] = [80,443,3000,8000,8080,8443,8888,9000]
    static func range(_ lo: UInt16, _ hi: UInt16) -> [UInt16] { Array(lo...hi) }
    // Common services on a typical home/office network — routers, IoT, media,
    // NAS, printers, cameras, smart-home hubs.
    static let common: [UInt16] = [
        22,23,53,80,443, 139,445, 548,2049, 3389,5900,
        1883,8883, 5353,1900, 9100,631, 554,8554,
        32400,8096, 5000,5001, 8123,1400, 62078
    ]
}
