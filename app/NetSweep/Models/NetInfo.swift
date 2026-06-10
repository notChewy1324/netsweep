import Foundation
import Network

// MARK: - Local interface introspection
// Uses BSD getifaddrs() (allowed in the sandbox) to read this device's own
// addresses + netmask, which lets us compute the subnet for host discovery.

struct InterfaceInfo: Identifiable {
    let id = UUID()
    let name: String          // en0, pdp_ip0, etc.
    let ipv4: String?
    let ipv6: String?
    let netmask: String?
    var isWiFi: Bool { name == "en0" }
    var isCellular: Bool { name.hasPrefix("pdp_ip") }
}

enum NetInfo {

    /// All active IPv4/IPv6 interfaces with addresses.
    static func interfaces() -> [InterfaceInfo] {
        var results: [String: (v4: String?, v6: String?, mask: String?)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let flags = Int32(p.pointee.ifa_flags)
            let family = p.pointee.ifa_addr.pointee.sa_family
            let up = (flags & IFF_UP) == IFF_UP && (flags & IFF_LOOPBACK) == 0
            if up, family == UInt8(AF_INET) || family == UInt8(AF_INET6) {
                let name = String(cString: p.pointee.ifa_name)
                let addr = sockaddrToString(p.pointee.ifa_addr)
                var cur = results[name] ?? (nil, nil, nil)
                if family == UInt8(AF_INET) {
                    cur.v4 = addr
                    if let mask = p.pointee.ifa_netmask {
                        cur.mask = sockaddrToString(mask)
                    }
                } else {
                    if cur.v6 == nil { cur.v6 = addr }
                }
                results[name] = cur
            }
            ptr = p.pointee.ifa_next
        }

        return results.map { InterfaceInfo(name: $0.key, ipv4: $0.value.v4,
                                           ipv6: $0.value.v6, netmask: $0.value.mask) }
            .sorted { ($0.isWiFi ? 0 : 1, $0.name) < ($1.isWiFi ? 0 : 1, $1.name) }
    }

    private static func sockaddrToString(_ sa: UnsafeMutablePointer<sockaddr>) -> String? {
        var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let len = socklen_t(sa.pointee.sa_len)
        guard getnameinfo(sa, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
        else { return nil }
        var s = String(cString: host)
        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) } // strip zone id
        return s
    }

    /// Compute a scannable host range for an IPv4 + netmask.
    /// For normal home subnets (/23 and smaller) we scan the whole thing. For
    /// larger subnets we don't refuse — we scan the local /24 window around the
    /// device's own address, which covers virtually all real-world cases without
    /// trying to sweep tens of thousands of hosts.
    static func hostRange(ip: String, netmask: String) -> [String] {
        guard let ipInt = ipToUInt32(ip), let maskInt = ipToUInt32(netmask) else { return [] }
        let network = ipInt & maskInt
        let broadcast = network | ~maskInt
        let span = broadcast - network

        let lo: UInt32, hi: UInt32
        if span > 512 {
            // Too big to sweep fully: scan the /24 the device sits in.
            let net24 = ipInt & 0xFFFFFF00
            lo = net24 + 1
            hi = net24 + 254
        } else if span > 1 {
            lo = network + 1
            hi = broadcast - 1
        } else {
            // /31 or /32 — just the address(es) present.
            lo = network
            hi = broadcast
        }

        var hosts: [String] = []
        var addr = lo
        while addr <= hi {
            hosts.append(uint32ToIP(addr))
            if addr == hi { break }   // avoid overflow at 255.255.255.255
            addr += 1
        }
        return hosts
    }

    static func ipToUInt32(_ ip: String) -> UInt32? {
        let parts = ip.split(separator: ".").compactMap { UInt32($0) }
        guard parts.count == 4, parts.allSatisfy({ $0 <= 255 }) else { return nil }
        return (parts[0] << 24) | (parts[1] << 16) | (parts[2] << 8) | parts[3]
    }

    static func uint32ToIP(_ n: UInt32) -> String {
        "\((n >> 24) & 255).\((n >> 16) & 255).\((n >> 8) & 255).\(n & 255)"
    }

    static func cidr(from netmask: String) -> Int {
        guard let m = ipToUInt32(netmask) else { return 0 }
        return m.nonzeroBitCount
    }

    /// The conventional gateway address: network base + 1 (e.g. 192.168.1.1).
    /// iOS doesn't expose the real routing table to apps, so this is the standard
    /// convention rather than a guaranteed lookup.
    static func gatewayIP(ip: String, netmask: String) -> String? {
        guard let ipInt = ipToUInt32(ip), let maskInt = ipToUInt32(netmask) else { return nil }
        let network = ipInt & maskInt
        return uint32ToIP(network + 1)
    }

    /// True if `candidate` is within an RFC1918 / link-local / shared-address
    /// private range. Used as a safety net for non-routed scanning targets.
    static func isPrivateIPv4(_ candidate: String) -> Bool {
        guard let ip = ipToUInt32(candidate) else { return false }
        // 10.0.0.0/8
        if (ip & 0xFF000000) == 0x0A000000 { return true }
        // 172.16.0.0/12
        if (ip & 0xFFF00000) == 0xAC100000 { return true }
        // 192.168.0.0/16
        if (ip & 0xFFFF0000) == 0xC0A80000 { return true }
        // 100.64.0.0/10 (carrier-grade NAT / shared)
        if (ip & 0xFFC00000) == 0x64400000 { return true }
        // 169.254.0.0/16 (link-local)
        if (ip & 0xFFFF0000) == 0xA9FE0000 { return true }
        // 127.0.0.0/8 (loopback)
        if (ip & 0xFF000000) == 0x7F000000 { return true }
        return false
    }

    /// True if `candidate` sits inside the local subnet for the given
    /// interface IP + netmask.
    static func isOnLocalSubnet(_ candidate: String, ip: String, netmask: String) -> Bool {
        guard let c = ipToUInt32(candidate),
              let i = ipToUInt32(ip),
              let m = ipToUInt32(netmask) else { return false }
        return (c & m) == (i & m)
    }
}

// MARK: - Local-network scope guard
// Ensures that probing tools only ever target devices on the user's own
// local network. Centralized so every tool applies the same rule.

enum LocalNetworkGuard {

    enum ScopeError: LocalizedError {
        case noInterface
        case notLocal(host: String)

        var errorDescription: String? {
            switch self {
            case .noInterface:
                return "Connect to Wi-Fi to use this tool. NetSweep only runs on the local network you're connected to."
            case .notLocal(let host):
                return "\"\(host)\" isn't on your local network. NetSweep is limited to devices on the Wi-Fi network you're connected to — public hosts can't be targeted."
            }
        }
    }

    /// Returns the active local IPv4 / netmask, preferring Wi-Fi.
    static func localInterface() -> (ip: String, netmask: String)? {
        let ifaces = NetInfo.interfaces()
        let chosen = ifaces.first(where: { $0.isWiFi && $0.ipv4 != nil })
            ?? ifaces.first(where: { $0.ipv4 != nil && !$0.isCellular })
            ?? ifaces.first(where: { $0.ipv4 != nil })
        guard let iface = chosen, let ip = iface.ipv4 else { return nil }
        return (ip, iface.netmask ?? "255.255.255.0")
    }

    /// True if `target` is a literal IPv4 address inside the user's current
    /// local subnet, or an unqualified ".local"/bare hostname (mDNS-style)
    /// that can only resolve on the LAN.
    static func isLocalTarget(_ target: String) -> Bool {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Numeric IP path: must sit inside our own subnet.
        if NetInfo.ipToUInt32(trimmed) != nil {
            guard let iface = localInterface() else { return false }
            // Belt-and-braces: also reject anything that isn't private.
            guard NetInfo.isPrivateIPv4(trimmed) else { return false }
            return NetInfo.isOnLocalSubnet(trimmed, ip: iface.ip, netmask: iface.netmask)
        }
        // Hostname path: only mDNS / unqualified names. A ".local" suffix
        // is the standard Bonjour TLD. A bare single-label hostname
        // (no dots) is also resolved on the LAN. Anything else (e.g.
        // example.com, 8.8.8.8.nip.io) is rejected.
        let lower = trimmed.lowercased()
        if lower.hasSuffix(".local") { return true }
        if !lower.contains(".") {
            // Reject anything that looks like a public hostname or
            // contains characters outside RFC 1123 hostname syntax.
            let ok = lower.unicodeScalars.allSatisfy {
                ("a"..."z").contains(Character($0)) ||
                ("0"..."9").contains(Character($0)) ||
                $0 == "-"
            }
            return ok
        }
        return false
    }

    /// Throws if `target` falls outside the local network.
    static func ensureLocal(_ target: String) throws {
        guard localInterface() != nil else { throw ScopeError.noInterface }
        guard isLocalTarget(target) else { throw ScopeError.notLocal(host: target) }
    }
}

// MARK: - Live path monitor (WiFi vs Cellular vs none, expensive/constrained flags)

@MainActor
final class PathMonitor: ObservableObject {
    @Published var status: String = "—"
    @Published var interfaceType: String = "—"
    @Published var isExpensive = false
    @Published var isConstrained = false
    @Published var supportsIPv4 = false
    @Published var supportsIPv6 = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "PathMonitor")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.status = path.status == .satisfied ? "ONLINE" : "OFFLINE"
                if path.usesInterfaceType(.wifi) { self.interfaceType = "WI-FI" }
                else if path.usesInterfaceType(.cellular) { self.interfaceType = "CELLULAR" }
                else if path.usesInterfaceType(.wiredEthernet) { self.interfaceType = "ETHERNET" }
                else { self.interfaceType = "OTHER" }
                self.isExpensive = path.isExpensive
                self.isConstrained = path.isConstrained
                self.supportsIPv4 = path.supportsIPv4
                self.supportsIPv6 = path.supportsIPv6
            }
        }
        monitor.start(queue: queue)
    }

    func stop() { monitor.cancel() }
}
