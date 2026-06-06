import Foundation
import SwiftData

// MARK: - Full-network scan orchestration
// One call: detect subnet, sweep hosts, analyze findings, diff against the
// devices we've ever seen (for "new device" alerts), compute health, persist.

@MainActor
final class NetworkScanService: ObservableObject {
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var statusLine = ""
    @Published var lastSession: ScanSession?
    @Published var liveFoundCount = 0

    private let scanner = HostScanner()

    func runFullScan(context: ModelContext, intensity: ScanIntensity = .balanced,
                     notify: Bool = true) async {
        guard !isScanning else { return }
        isScanning = true
        progress = 0
        statusLine = "Detecting network…"

        // Prefer Wi-Fi, but fall back to any active IPv4 interface so the scan
        // still runs on unusual setups (Ethernet adapters, hotspots, etc.).
        let ifaces = NetInfo.interfaces()
        let chosen = ifaces.first(where: { $0.isWiFi && $0.ipv4 != nil })
            ?? ifaces.first(where: { $0.ipv4 != nil && !$0.isCellular })
            ?? ifaces.first(where: { $0.ipv4 != nil })
        guard let iface = chosen, let ip = iface.ipv4 else {
            statusLine = "No local network found. Connect to Wi-Fi and try again."
            isScanning = false
            return
        }
        let mask = iface.netmask ?? "255.255.255.0"   // assume /24 if unknown
        let subnet = "\(ip)/\(NetInfo.cidr(from: mask))"
        var hostList = NetInfo.hostRange(ip: ip, netmask: mask)
        // Last-resort fallback: synthesize the /24 around our own IP.
        if hostList.isEmpty {
            hostList = NetInfo.hostRange(ip: ip, netmask: "255.255.255.0")
        }
        guard !hostList.isEmpty else {
            statusLine = "Couldn't determine a scannable range."
            isScanning = false
            return
        }

        statusLine = "Scanning \(hostList.count) addresses…"
        let hosts = await sweep(hostList, intensity: intensity)

        statusLine = "Analyzing…"
        // Load every IP we've ever recorded to decide what's new.
        let known = knownIPs(context: context)
        let analyzed = SecurityAnalysis.findings(for: hosts)
        let score = SecurityAnalysis.healthScore(from: analyzed)

        // Capture how many sessions existed BEFORE this one (for first-scan
        // suppression of "new device" alerts).
        let priorSessionCount = (try? context.fetch(FetchDescriptor<ScanSession>()))?.count ?? 0

        var newCount = 0
        let session = ScanSession(networkName: subnet, subnet: subnet)
        session.deviceCount = hosts.count
        session.healthScore = score

        // Insert the session into the context FIRST, then attach related objects.
        // SwiftData relationship arrays must be mutated on managed objects — doing
        // it before insertion can corrupt the backing store and crash the
        // `devices` getter later (EXC_BREAKPOINT in _PersistedProperty).
        context.insert(session)

        for h in hosts {
            let isNew = !known.contains(h.ip)
            if isNew { newCount += 1 }
            let rec = DeviceRecord(ip: h.ip, hostname: h.hostname,
                                   vendorGuess: h.vendorGuess,
                                   openPorts: h.openPorts.map(Int.init),
                                   rttMs: h.rttMs, isNew: isNew)
            context.insert(rec)
            rec.session = session
        }
        for f in analyzed {
            let rec = Finding(severity: f.severity, title: f.title, detail: f.detail, deviceIP: f.deviceIP)
            context.insert(rec)
            rec.session = session
        }
        session.newDeviceCount = newCount

        try? context.save()

        lastSession = session
        statusLine = SecurityAnalysis.summary(score: score, deviceCount: hosts.count, newCount: newCount)
        isScanning = false

        // Tactile feedback keyed to the result.
        if score >= 85 { Haptics.success() } else { Haptics.warning() }

        // Notify only when this isn't the very first scan (everything is "new" then).
        if notify, newCount > 0, priorSessionCount >= 1 {
            await NotificationManager.shared.notifyNewDevices(count: newCount, networkName: subnet)
        }
    }

    // Drive HostScanner and await its completion, mirroring progress.
    private func sweep(_ hostList: [String], intensity: ScanIntensity) async -> [DiscoveredHost] {
        scanner.scan(hosts: hostList, timeout: intensity.timeout, concurrency: intensity.concurrency)
        liveFoundCount = 0
        while scanner.isScanning {
            progress = scanner.progress
            liveFoundCount = scanner.hosts.count
            try? await Task.sleep(nanoseconds: 120_000_000)
        }
        progress = 1
        liveFoundCount = scanner.hosts.count
        return scanner.hosts
    }

    private func knownIPs(context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<DeviceRecord>()
        let all = (try? context.fetch(descriptor)) ?? []
        return Set(all.map { $0.ip })
    }
}
