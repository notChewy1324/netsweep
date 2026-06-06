import Foundation
import SwiftData

// MARK: - Persistent models (SwiftData)
// A ScanSession is one full network sweep. Each DeviceRecord is a device seen
// during that sweep. Tracking devices across sessions is what powers
// "new device joined your network" detection and the history timeline.

@Model
final class ScanSession {
    var id: UUID
    var date: Date
    var networkName: String        // SSID or subnet label
    var subnet: String
    var deviceCount: Int
    var healthScore: Int           // 0–100
    var newDeviceCount: Int
    @Relationship(deleteRule: .cascade, inverse: \DeviceRecord.session)
    var devices: [DeviceRecord]
    @Relationship(deleteRule: .cascade, inverse: \Finding.session)
    var findings: [Finding]

    init(id: UUID = UUID(), date: Date = .now, networkName: String, subnet: String,
         deviceCount: Int = 0, healthScore: Int = 100, newDeviceCount: Int = 0) {
        self.id = id
        self.date = date
        self.networkName = networkName
        self.subnet = subnet
        self.deviceCount = deviceCount
        self.healthScore = healthScore
        self.newDeviceCount = newDeviceCount
        self.devices = []
        self.findings = []
    }
}

@Model
final class DeviceRecord {
    var id: UUID
    var ip: String
    var hostname: String?
    var vendorGuess: String?
    var openPorts: [Int]
    var rttMs: Double?
    var firstSeen: Date
    var isNew: Bool                // first time we've ever seen this device
    var session: ScanSession?

    init(id: UUID = UUID(), ip: String, hostname: String? = nil, vendorGuess: String? = nil,
         openPorts: [Int] = [], rttMs: Double? = nil, firstSeen: Date = .now, isNew: Bool = false) {
        self.id = id
        self.ip = ip
        self.hostname = hostname
        self.vendorGuess = vendorGuess
        self.openPorts = openPorts
        self.rttMs = rttMs
        self.firstSeen = firstSeen
        self.isNew = isNew
    }
}

// A security observation surfaced from a scan (open telnet, expired cert, etc).
@Model
final class Finding {
    var id: UUID
    var severityRaw: Int           // 0 info, 1 low, 2 medium, 3 high
    var title: String
    var detail: String
    var deviceIP: String?
    var session: ScanSession?

    init(id: UUID = UUID(), severity: Severity, title: String, detail: String, deviceIP: String? = nil) {
        self.id = id
        self.severityRaw = severity.rawValue
        self.title = title
        self.detail = detail
        self.deviceIP = deviceIP
    }

    var severity: Severity { Severity(rawValue: severityRaw) ?? .info }
}

enum Severity: Int, CaseIterable, Comparable {
    case info = 0, low = 1, medium = 2, high = 3
    static func < (l: Severity, r: Severity) -> Bool { l.rawValue < r.rawValue }
    var label: String { ["INFO", "LOW", "MEDIUM", "HIGH"][rawValue] }
}

// MARK: - Device tag
// Persistent, user-assigned identity for a device, keyed by IP so it survives
// across scans. Holds a custom name and a trust level. This is what makes
// new-device detection meaningful ("an UNTRUSTED device joined").

@Model
final class DeviceTag {
    @Attribute(.unique) var ip: String
    var customName: String?
    var trustRaw: Int       // 0 unknown, 1 trusted, 2 blocked
    var noteText: String
    var updated: Date

    init(ip: String, customName: String? = nil, trust: TrustLevel = .unknown, noteText: String = "") {
        self.ip = ip
        self.customName = customName
        self.trustRaw = trust.rawValue
        self.noteText = noteText
        self.updated = .now
    }

    var trust: TrustLevel {
        get { TrustLevel(rawValue: trustRaw) ?? .unknown }
        set { trustRaw = newValue.rawValue; updated = .now }
    }
}

enum TrustLevel: Int, CaseIterable, Identifiable {
    case unknown = 0, trusted = 1, blocked = 2
    var id: Int { rawValue }
    var label: String { ["Unknown", "Trusted", "Blocked"][rawValue] }
    var icon: String { ["questionmark.circle", "checkmark.shield.fill", "hand.raised.fill"][rawValue] }
}

// MARK: - Connection test history
// Persists each connection quality test so the user can see trends over time.

@Model
final class ConnectionTest {
    var date: Date
    var latencyMs: Double?
    var jitterMs: Double?
    var throughputMbps: Double?
    var network: String

    init(date: Date = .now, latencyMs: Double?, jitterMs: Double?, throughputMbps: Double?, network: String) {
        self.date = date
        self.latencyMs = latencyMs
        self.jitterMs = jitterMs
        self.throughputMbps = throughputMbps
        self.network = network
    }
}
