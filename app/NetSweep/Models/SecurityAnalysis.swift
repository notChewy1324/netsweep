import Foundation
import SwiftUI

// MARK: - Security analysis
// Turns raw scan data (open ports per host) into human-readable security
// findings and a single 0–100 health score. This is the layer that makes the
// app feel like a security tool rather than a port list.

struct AnalyzedFinding {
    let severity: Severity
    let title: String
    let detail: String
    let deviceIP: String?
}

enum SecurityAnalysis {

    // Ports that warrant a flag when exposed on a home network, with rationale.
    private static let riskyPorts: [Int: (Severity, String, String)] = [
        23:   (.high,   "Telnet exposed", "Telnet sends credentials in plaintext. Disable it and use SSH."),
        21:   (.medium, "FTP exposed", "Plain FTP is unencrypted. Prefer SFTP/FTPS."),
        445:  (.medium, "SMB file sharing exposed", "Windows file sharing is reachable. Ensure it's password-protected and patched."),
        139:  (.low,    "NetBIOS exposed", "Legacy Windows networking is open; usually unnecessary."),
        3389: (.high,   "Remote Desktop exposed", "RDP is a common attack target. Restrict or VPN-gate it."),
        5900: (.medium, "VNC screen sharing exposed", "Screen sharing is reachable; verify it requires a strong password."),
        1900: (.low,    "UPnP/SSDP exposed", "UPnP can auto-open router ports; consider disabling on the router."),
        9100: (.info,   "Network printer", "Raw printing port open, expected for a shared printer."),
        5555: (.high,   "Android ADB exposed", "Android Debug Bridge over network is a serious risk if unintended."),
        6379: (.high,   "Redis exposed", "Redis often ships with no auth. Verify it's bound/locked down."),
        27017:(.high,   "MongoDB exposed", "Unauthenticated MongoDB is a classic breach vector."),
        3306: (.medium, "MySQL exposed", "Database reachable on the LAN; confirm it requires auth."),
        5432: (.medium, "PostgreSQL exposed", "Database reachable on the LAN; confirm it requires auth.")
    ]

    /// Build findings from a set of discovered hosts.
    static func findings(for hosts: [DiscoveredHost]) -> [AnalyzedFinding] {
        var out: [AnalyzedFinding] = []
        for host in hosts {
            let label = host.hostname ?? host.ip
            for port in host.openPorts {
                if let (sev, title, detail) = riskyPorts[Int(port)] {
                    out.append(AnalyzedFinding(severity: sev,
                                               title: "\(title) on \(label)",
                                               detail: detail, deviceIP: host.ip))
                }
            }
            // Many open ports on one host can indicate a server or a compromised device.
            if host.openPorts.count >= 6 {
                out.append(AnalyzedFinding(severity: .low,
                    title: "\(label) exposes \(host.openPorts.count) ports",
                    detail: "A high number of open ports. Expected for a server, worth checking otherwise.",
                    deviceIP: host.ip))
            }
        }
        if out.isEmpty {
            out.append(AnalyzedFinding(severity: .info, title: "No risky services detected",
                                       detail: "None of the scanned hosts exposed commonly risky ports.",
                                       deviceIP: nil))
        }
        return out.sorted { $0.severity > $1.severity }
    }

    /// 0–100 health score. Starts at 100, subtracts per finding by severity.
    static func healthScore(from findings: [AnalyzedFinding]) -> Int {
        var score = 100
        for f in findings {
            switch f.severity {
            case .high:   score -= 25
            case .medium: score -= 12
            case .low:    score -= 5
            case .info:   break
            }
        }
        return max(0, min(100, score))
    }

    static func grade(_ score: Int) -> (String, Int) {     // (letter, colorIndex 0..2)
        switch score {
        case 85...100: return ("SECURE", 2)
        case 60..<85:  return ("FAIR", 1)
        default:       return ("AT RISK", 0)
        }
    }

    /// Canonical brand color for a health score. Use this everywhere a grade
    /// drives a tint — keeps the dashboard, history, and trends visually
    /// consistent (SECURE → green, FAIR → amber, AT RISK → red).
    static func color(for score: Int) -> Color {
        [Theme.danger, Theme.amber, Theme.good][grade(score).1]
    }

    static func summary(score: Int, deviceCount: Int, newCount: Int) -> String {
        let (grade, _) = grade(score)
        var s = "\(deviceCount) device\(deviceCount == 1 ? "" : "s") on your network. "
        switch grade {
        case "SECURE": s += "Everything looks healthy."
        case "FAIR":   s += "A few things are worth a look."
        default:       s += "Some issues need attention."
        }
        if newCount > 0 { s += " \(newCount) new device\(newCount == 1 ? "" : "s") since last scan." }
        return s
    }
}
