import Foundation

// MARK: - Per-device deep scan
// Takes a single host and does a thorough pass: scans a broad port range,
// grabs banners on each open port, derives findings, and infers a device
// profile (type, likely OS) from the combined signal.

struct DeepScanResult {
    let ip: String
    var hostname: String?
    var openPorts: [PortDetail] = []
    var deviceType: String?
    var osGuess: String?
    var findings: [AnalyzedFinding] = []
    var rttMs: Double?
}

struct PortDetail: Identifiable {
    let id = UUID()
    let port: UInt16
    let service: String
    var banner: String?
}

@MainActor
final class DeepScanner: ObservableObject {
    @Published var result: DeepScanResult?
    @Published var progress: Double = 0
    @Published var isScanning = false
    @Published var phase = ""

    private var task: Task<Void, Never>?

    func scan(ip: String, hostname: String?, quick: Bool = false) {
        cancel()
        isScanning = true
        progress = 0
        phase = "Probing ports…"
        var detail = DeepScanResult(ip: ip, hostname: hostname)

        // Broad-but-bounded port set: well-known + common alt ports.
        let ports: [UInt16] = quick ? PortSets.top20 : PortSets.common

        task = Task {
            // 1. Reachability / RTT
            var rtt = await TCPProbe.connect(host: ip, port: 80, timeout: 1)
            if rtt == nil { rtt = await TCPProbe.connect(host: ip, port: 443, timeout: 1) }
            if let rtt { detail.rttMs = rtt }

            // 2. Port sweep with banners
            var found: [PortDetail] = []
            let total = ports.count
            var done = 0
            await withTaskGroup(of: PortDetail?.self) { group in
                let sem = AsyncSemaphore(value: 30)
                for port in ports {
                    await sem.wait()
                    group.addTask {
                        defer { Task { await sem.signal() } }
                        if await TCPProbe.connect(host: ip, port: port, timeout: 0.8) != nil {
                            var pd = PortDetail(port: port, service: Services.name(port))
                            if let b = await BannerGrabber.grab(host: ip, port: port) {
                                pd.banner = b.summary
                            }
                            return pd
                        }
                        return nil
                    }
                }
                for await pd in group {
                    done += 1
                    progress = Double(done) / Double(total)
                    if let pd { found.append(pd); found.sort { $0.port < $1.port } }
                    if Task.isCancelled { break }
                }
            }
            detail.openPorts = found

            // 3. Inference
            phase = "Analyzing…"
            let openSet = found.map { $0.port }
            detail.deviceType = Fingerprint.guess(openPorts: openSet)
            detail.osGuess = inferOS(from: found)

            // 4. Findings (reuse the shared analysis on a synthetic host)
            let synthetic = DiscoveredHost(ip: ip, hostname: hostname, openPorts: openSet)
            detail.findings = SecurityAnalysis.findings(for: [synthetic])

            result = detail
            phase = ""
            isScanning = false
        }
    }

    func cancel() { task?.cancel(); task = nil; isScanning = false }

    // Infer OS from banners (SSH/HTTP server strings are the richest signal).
    private func inferOS(from ports: [PortDetail]) -> String? {
        let banners = ports.compactMap { $0.banner?.lowercased() }.joined(separator: " ")
        if banners.contains("ubuntu") { return "Linux (Ubuntu)" }
        if banners.contains("debian") { return "Linux (Debian)" }
        if banners.contains("raspbian") || banners.contains("raspberry") { return "Raspberry Pi OS" }
        if banners.contains("windows") || banners.contains("microsoft-iis") { return "Windows" }
        if banners.contains("openssh") && banners.contains("freebsd") { return "FreeBSD" }
        if banners.contains("openssh") { return "Unix-like (OpenSSH)" }
        if banners.contains("darwin") || banners.contains("macos") { return "macOS" }
        let openSet = Set(ports.map { $0.port })
        if openSet.contains(62078) { return "iOS / iPadOS" }
        return nil
    }
}
