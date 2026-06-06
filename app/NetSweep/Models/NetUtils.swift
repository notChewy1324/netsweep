import Foundation

// MARK: - Subnet calculator

struct SubnetResult {
    let network: String
    let broadcast: String
    let firstHost: String
    let lastHost: String
    let mask: String
    let wildcard: String
    let hostCount: Int
    let cidr: Int
}

enum SubnetCalc {
    static func compute(ip: String, cidr: Int) -> SubnetResult? {
        guard cidr >= 0, cidr <= 32, let ipInt = NetInfo.ipToUInt32(ip) else { return nil }
        let mask: UInt32 = cidr == 0 ? 0 : ~UInt32(0) << (32 - cidr)
        let network = ipInt & mask
        let broadcast = network | ~mask
        let usable = cidr >= 31 ? 0 : Int(broadcast - network) - 1
        let first = cidr >= 31 ? network : network + 1
        let last = cidr >= 31 ? broadcast : broadcast - 1
        return SubnetResult(
            network: NetInfo.uint32ToIP(network),
            broadcast: NetInfo.uint32ToIP(broadcast),
            firstHost: NetInfo.uint32ToIP(first),
            lastHost: NetInfo.uint32ToIP(last),
            mask: NetInfo.uint32ToIP(mask),
            wildcard: NetInfo.uint32ToIP(~mask),
            hostCount: max(0, usable),
            cidr: cidr
        )
    }
}

// MARK: - MAC vendor (OUI) lookup
// A small built-in table of common OUI prefixes. A full lookup would hit an
// external DB; this covers the vendors you'll most often see on a home network
// without a network call.

enum MACVendor {
    // First 3 octets (OUI) → vendor. Lowercased, no separators.
    private static let ouiTable: [String: String] = [
        "f0d1a9": "Apple", "ac87a3": "Apple", "a4b805": "Apple", "3c0754": "Apple",
        "001451": "Apple", "d8a25e": "Apple", "f86214": "Apple",
        "b827eb": "Raspberry Pi", "dca632": "Raspberry Pi", "e45f01": "Raspberry Pi",
        "001a11": "Google", "f4f5e8": "Google", "3c5ab4": "Google",
        "fcfbfb": "Cisco", "00000c": "Cisco", "0050f2": "Microsoft",
        "001dd8": "Microsoft", "7c1e52": "Microsoft",
        "001788": "Philips Hue", "ecb5fa": "Philips Hue",
        "d0737f": "Amazon", "f0272d": "Amazon", "747548": "Amazon",
        "00226b": "Cisco-Linksys", "c0562d": "TP-Link", "5067f0": "TP-Link",
        "001e2a": "Netgear", "204e7f": "Netgear", "002401": "D-Link",
        "001f3f": "AVM Fritz!Box", "e8de27": "TP-Link", "b0be76": "TP-Link",
        "001132": "Synology", "0011d8": "Asus", "2c56dc": "Asus",
        "bcaec5": "Samsung", "8425db": "Samsung", "5cf6dc": "Samsung"
    ]

    static func lookup(_ mac: String) -> String? {
        let clean = mac.lowercased().filter { $0.isHexDigit }
        guard clean.count >= 6 else { return nil }
        let oui = String(clean.prefix(6))
        return ouiTable[oui]
    }

    static func normalize(_ mac: String) -> String? {
        let clean = mac.lowercased().filter { $0.isHexDigit }
        guard clean.count == 12 else { return nil }
        return stride(from: 0, to: 12, by: 2).map { i in
            let start = clean.index(clean.startIndex, offsetBy: i)
            let end = clean.index(start, offsetBy: 2)
            return String(clean[start..<end])
        }.joined(separator: ":")
    }
}
