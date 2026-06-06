import Foundation

// MARK: - Scan export (JSON)
// Serializes a session to a shareable JSON file written to a temp URL.

enum ScanExport {
    struct ExportDevice: Codable {
        let ip: String
        let hostname: String?
        let vendor: String?
        let openPorts: [Int]
        let isNew: Bool
    }
    struct ExportFinding: Codable {
        let severity: String
        let title: String
        let detail: String
        let deviceIP: String?
    }
    struct ExportSession: Codable {
        let date: Date
        let subnet: String
        let healthScore: Int
        let deviceCount: Int
        let newDeviceCount: Int
        let devices: [ExportDevice]
        let findings: [ExportFinding]
    }

    static func json(for session: ScanSession) -> URL? {
        let payload = ExportSession(
            date: session.date,
            subnet: session.subnet,
            healthScore: session.healthScore,
            deviceCount: session.deviceCount,
            newDeviceCount: session.newDeviceCount,
            devices: session.devices.map {
                ExportDevice(ip: $0.ip, hostname: $0.hostname, vendor: $0.vendorGuess,
                             openPorts: $0.openPorts, isNew: $0.isNew)
            },
            findings: session.findings.map {
                ExportFinding(severity: $0.severity.label, title: $0.title,
                              detail: $0.detail, deviceIP: $0.deviceIP)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(payload) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: session.date)
            .replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("netsweep-scan-\(stamp).json")
        do { try data.write(to: url); return url } catch { return nil }
    }
}
