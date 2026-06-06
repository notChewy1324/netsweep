import Foundation
import Network

// MARK: - Connection quality
// Active measurement that works over WiFi OR cellular: TCP-connect latency to a
// reliable host (jitter from repeated samples) plus a lightweight download to
// estimate throughput. No private APIs — we measure behavior, not the radio.

struct ConnectionQuality {
    var latencyMs: Double?       // median RTT
    var jitterMs: Double?        // mean abs deviation between samples
    var throughputMbps: Double?  // rough download estimate
    var samples: [Double] = []   // raw RTTs for the sparkline
    var grade: String {
        guard let l = latencyMs else { return "—" }
        switch l {
        case ..<40:  return "EXCELLENT"
        case ..<90:  return "GOOD"
        case ..<160: return "FAIR"
        default:     return "POOR"
        }
    }
    var gradeColorIndex: Int {     // 0 danger,1 amber,2 accent
        guard let l = latencyMs else { return 1 }
        switch l { case ..<90: return 2; case ..<160: return 1; default: return 0 }
    }
}

@MainActor
final class ConnectionTester: ObservableObject {
    @Published var quality = ConnectionQuality()
    @Published var isRunning = false
    @Published var phase = ""

    // Anycast / globally reliable endpoints.
    private let latencyHost = "1.1.1.1"
    private let latencyPort: UInt16 = 443
    // A download from Cloudflare's speed endpoint for a throughput estimate.
    // ~1MB gives a more stable sample than 200KB while staying reasonable on
    // cellular. This is an estimate of download behavior, not a lab-grade test.
    private let throughputURL = URL(string: "https://speed.cloudflare.com/__down?bytes=1000000")!

    func run() {
        guard !isRunning else { return }
        isRunning = true
        quality = ConnectionQuality()
        Task {
            phase = "Measuring latency…"
            await measureLatency(samples: 8)
            phase = "Measuring throughput…"
            await measureThroughput()
            phase = ""
            isRunning = false
        }
    }

    private func measureLatency(samples: Int) async {
        var rtts: [Double] = []
        for _ in 0..<samples {
            if let rtt = await TCPProbe.connect(host: latencyHost, port: latencyPort, timeout: 2) {
                rtts.append(rtt)
                quality.samples = rtts
            }
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        guard !rtts.isEmpty else { return }
        let sorted = rtts.sorted()
        let median = sorted[sorted.count / 2]
        let mean = rtts.reduce(0, +) / Double(rtts.count)
        let jitter = rtts.map { abs($0 - mean) }.reduce(0, +) / Double(rtts.count)
        quality.latencyMs = median
        quality.jitterMs = jitter
    }

    private func measureThroughput() async {
        let start = Date()
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: config)
        do {
            let (data, _) = try await session.data(from: throughputURL)
            let seconds = Date().timeIntervalSince(start)
            guard seconds > 0 else { return }
            let megabits = Double(data.count) * 8 / 1_000_000
            quality.throughputMbps = megabits / seconds
        } catch {
            quality.throughputMbps = nil
        }
    }
}
