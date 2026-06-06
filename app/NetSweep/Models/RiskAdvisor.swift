import Foundation

// MARK: - Service risk guidance
// Where we only know a port (not a product version), we can't honestly name a
// specific CVE. Instead we give confidence-labeled guidance: what the exposed
// service is, why it can be risky, and what to check. This keeps the app
// truthful rather than inventing vulnerabilities.

struct RiskGuidance {
    let port: UInt16
    let service: String
    let concern: String        // why it matters
    let recommendation: String // what to do
    let severity: Severity
}

enum RiskAdvisor {
    private static let table: [UInt16: (String, String, String, Severity)] = [
        23:   ("Telnet", "Transmits credentials and data in plaintext — trivially intercepted.", "Disable Telnet; use SSH instead.", .high),
        21:   ("FTP", "Plain FTP is unencrypted; credentials can be sniffed.", "Switch to SFTP or FTPS, or disable if unused.", .medium),
        445:  ("SMB", "File-sharing protocol historically targeted by worms (e.g. EternalBlue-class issues).", "Ensure the device is fully patched and SMB is password-protected; disable SMBv1.", .medium),
        139:  ("NetBIOS", "Legacy Windows networking, rarely needed and a common info-leak vector.", "Disable NetBIOS over TCP/IP if not required.", .low),
        3389: ("RDP", "Remote Desktop is a frequent ransomware entry point when exposed.", "Restrict to VPN, enable Network Level Authentication, use strong credentials.", .high),
        5900: ("VNC", "Screen sharing; some implementations allow weak or no authentication.", "Require a strong password; tunnel over SSH/VPN.", .medium),
        1900: ("UPnP/SSDP", "UPnP can let devices auto-open router ports, expanding attack surface.", "Disable UPnP on the router unless specifically needed.", .low),
        5555: ("Android ADB", "Network ADB allows remote device control if left open.", "Disable ADB-over-network; it should never be exposed.", .high),
        6379: ("Redis", "Often ships with no authentication by default.", "Bind to localhost, enable auth, never expose to the LAN/Internet.", .high),
        27017:("MongoDB", "Historically shipped unauthenticated, a frequent breach source.", "Enable authentication and bind to trusted interfaces only.", .high),
        3306: ("MySQL", "Database directly reachable on the network.", "Require strong auth; restrict bind address to trusted hosts.", .medium),
        5432: ("PostgreSQL", "Database directly reachable on the network.", "Require strong auth; restrict listen addresses.", .medium),
        9100: ("Raw printing", "Open print port; usually benign but can leak documents.", "Acceptable for a trusted shared printer; restrict otherwise.", .info),
        80:   ("HTTP", "Unencrypted web service; admin pages over HTTP expose credentials.", "Prefer HTTPS; ensure any admin UI uses a strong password.", .low)
    ]

    static func guidance(for port: UInt16) -> RiskGuidance? {
        guard let (svc, concern, rec, sev) = table[port] else { return nil }
        return RiskGuidance(port: port, service: svc, concern: concern,
                            recommendation: rec, severity: sev)
    }

    /// Build a keyword string for an NVD lookup from a parsed banner, if it
    /// looks specific enough to be meaningful (product + something version-like).
    static func nvdKeyword(fromBanner banner: String?) -> String? {
        guard let banner, !banner.isEmpty else { return nil }
        // Only attempt a CVE lookup when the banner contains a version-like token,
        // otherwise the result would be noise.
        let hasVersionToken = banner.range(of: #"\d+\.\d+"#, options: .regularExpression) != nil
        guard hasVersionToken else { return nil }
        // Trim to the leading "product version" portion.
        return String(banner.prefix(40))
    }
}
