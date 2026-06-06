import Foundation
import Network

// MARK: - Wi-Fi / network security audit
// iOS won't tell us the Wi-Fi encryption type without the (entitlement-gated)
// hotspot APIs, so we audit what we CAN observe: interface posture, IPv6
// exposure, gateway reachability, captive-portal hints, and whether risky
// services are exposed on the local segment. Each check yields a pass/warn/fail.

struct AuditCheck: Identifiable {
    let id = UUID()
    let name: String
    let status: Status
    let detail: String
    enum Status: String { case pass, warn, fail, info
        var label: String { rawValue.uppercased() }
    }
}

@MainActor
final class WiFiAuditor: ObservableObject {
    @Published var checks: [AuditCheck] = []
    @Published var isRunning = false
    @Published var score = 0

    func run(path: PathMonitor, lastSession: ScanSession?) async {
        isRunning = true
        var results: [AuditCheck] = []

        // 1. Interface type
        if path.interfaceType == "WI-FI" {
            results.append(.init(name: "Connection type", status: .pass,
                                 detail: "On Wi-Fi."))
        } else {
            results.append(.init(name: "Connection type", status: .info,
                                 detail: "Not on Wi-Fi (\(path.interfaceType.lowercased())). Some checks need a Wi-Fi network."))
        }

        // 2. Metered / constrained
        if path.isExpensive || path.isConstrained {
            results.append(.init(name: "Data policy", status: .info,
                                 detail: "Network is metered or low-data mode."))
        }

        // 3. IPv6 exposure awareness
        if path.supportsIPv6 {
            results.append(.init(name: "IPv6", status: .info,
                                 detail: "IPv6 is active. Ensure your firewall covers IPv6, not just IPv4."))
        } else {
            results.append(.init(name: "IPv6", status: .pass,
                                 detail: "IPv6 not in use on this link."))
        }

        // 4. Gateway reachability (router responds)
        var gatewayOpen = false
        let gw = gatewayGuess()
        if let gw {
            if await TCPProbe.connect(host: gw, port: 80, timeout: 1) != nil {
                gatewayOpen = true
            } else if await TCPProbe.connect(host: gw, port: 443, timeout: 1) != nil {
                gatewayOpen = true
            }
        }
        if let gw, gatewayOpen {
            results.append(.init(name: "Router admin page", status: .warn,
                                 detail: "Gateway \(gw) serves a web admin page. Make sure it uses a strong, non-default password."))
        } else {
            results.append(.init(name: "Router admin page", status: .pass,
                                 detail: "No obvious open admin page on the gateway."))
        }

        // 5. Captive portal hint
        let captive = await detectCaptivePortal()
        results.append(captive
            ? .init(name: "Captive portal", status: .warn,
                    detail: "A captive portal may be intercepting traffic. Common on public Wi-Fi.")
            : .init(name: "Captive portal", status: .pass,
                    detail: "No captive portal interception detected."))

        // 6. Risky services on the segment (from last scan)
        if let session = lastSession {
            let highs = session.findings.filter { $0.severity >= .medium }
            if highs.isEmpty {
                results.append(.init(name: "Exposed services", status: .pass,
                                     detail: "Last scan found no medium/high-risk services."))
            } else {
                results.append(.init(name: "Exposed services", status: .fail,
                                     detail: "\(highs.count) medium/high-risk service(s) found in last scan. See Findings."))
            }
        } else {
            results.append(.init(name: "Exposed services", status: .info,
                                 detail: "Run a network scan to check for risky exposed services."))
        }

        checks = results
        score = computeScore(results)
        isRunning = false
    }

    private func computeScore(_ checks: [AuditCheck]) -> Int {
        var s = 100
        for c in checks {
            switch c.status {
            case .fail: s -= 30
            case .warn: s -= 12
            default: break
            }
        }
        return max(0, min(100, s))
    }

    // Best-effort gateway guess: .1 of the current /24.
    private func gatewayGuess() -> String? {
        guard let wifi = NetInfo.interfaces().first(where: { $0.isWiFi }),
              let ip = wifi.ipv4 else { return nil }
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return nil }
        return "\(parts[0]).\(parts[1]).\(parts[2]).1"
    }

    // Apple's captive check endpoint returns a known body when unintercepted.
    private func detectCaptivePortal() async -> Bool {
        guard let url = URL(string: "http://captive.apple.com/hotspot-detect.html") else { return false }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        do {
            let (data, response) = try await URLSession(configuration: config).data(from: url)
            let body = String(data: data, encoding: .utf8) ?? ""
            let ok = body.contains("Success")
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // If we didn't get Apple's exact success page, something's intercepting.
            return !(ok && status == 200)
        } catch {
            return false
        }
    }
}
