import Foundation
import Network

// MARK: - TCP connect engine
// Everything here uses NWConnection (TCP connect()), which the iOS sandbox allows
// WITHOUT special entitlements. No raw sockets, no ICMP, no ARP. This is the
// legitimate way to probe reachability and open ports on your own network.

enum TCPProbe {

    /// Attempt a TCP handshake. Returns RTT in ms if the port is open, nil otherwise.
    static func connect(host: String, port: UInt16, timeout: TimeInterval) async -> Double? {
        await withCheckedContinuation { cont in
            let resumed = Lock(false)
            let endpointHost = NWEndpoint.Host(host)
            guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
                cont.resume(returning: nil); return
            }
            let params = NWParameters.tcp
            let conn = NWConnection(host: endpointHost, port: endpointPort, using: params)
            let start = DispatchTime.now()

            @Sendable func finish(_ result: Double?) {
                if resumed.swap(true) == false {
                    conn.cancel()
                    cont.resume(returning: result)
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                    finish(ms)
                case .failed, .cancelled:
                    finish(nil)
                default: break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

// Tiny thread-safe flag so we only resume the continuation once.
final class Lock<T>: @unchecked Sendable {
    private var value: T
    private let l = NSLock()
    init(_ v: T) { value = v }
    @discardableResult
    func swap(_ new: T) -> T { l.lock(); defer { l.unlock() }; let old = value; value = new; return old }
    var current: T { l.lock(); defer { l.unlock() }; return value }
}

// MARK: - Discovered host model

struct DiscoveredHost: Identifiable, Hashable {
    let id = UUID()
    let ip: String
    var hostname: String?
    var rttMs: Double?
    var openPorts: [UInt16] = []
    var vendorGuess: String?      // from common-port fingerprint
}

// MARK: - Host discovery sweep

@MainActor
final class HostScanner: ObservableObject {
    @Published var hosts: [DiscoveredHost] = []
    @Published var progress: Double = 0
    @Published var isScanning = false
    @Published var scannedCount = 0
    @Published var totalCount = 0

    // Ports we knock on to decide "alive" + take a fingerprint guess.
    private let probePorts: [UInt16] = [80, 443, 22, 445, 139, 62078, 5353, 8080, 53, 9100]

    private var task: Task<Void, Never>?

    func scan(hosts hostList: [String], timeout: TimeInterval = 0.6, concurrency: Int = 24) {
        cancel()
        hosts = []
        progress = 0
        scannedCount = 0
        totalCount = hostList.count
        isScanning = true

        task = Task {
            await withTaskGroup(of: DiscoveredHost?.self) { group in
                let sem = AsyncSemaphore(value: concurrency)
                for ip in hostList {
                    await sem.wait()
                    group.addTask { [probePorts] in
                        defer { Task { await sem.signal() } }
                        var best: Double? = nil
                        var open: [UInt16] = []
                        for port in probePorts {
                            if let rtt = await TCPProbe.connect(host: ip, port: port, timeout: timeout) {
                                open.append(port)
                                best = min(best ?? rtt, rtt)
                            }
                        }
                        guard !open.isEmpty else { return nil }
                        var h = DiscoveredHost(ip: ip, rttMs: best, openPorts: open.sorted())
                        h.vendorGuess = Fingerprint.guess(openPorts: open)
                        h.hostname = await DNS.reverse(ip: ip)
                        return h
                    }
                }
                for await result in group {
                    scannedCount += 1
                    progress = totalCount == 0 ? 1 : Double(scannedCount) / Double(totalCount)
                    if let h = result {
                        hosts.append(h)
                        hosts.sort { (NetInfo.ipToUInt32($0.ip) ?? 0) < (NetInfo.ipToUInt32($1.ip) ?? 0) }
                    }
                    if Task.isCancelled { break }
                }
            }
            isScanning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isScanning = false
    }
}

// MARK: - Port scanner (single target, range)

@MainActor
final class PortScanner: ObservableObject {
    @Published var open: [PortResult] = []
    @Published var progress: Double = 0
    @Published var isScanning = false
    @Published var scopeError: String?

    struct PortResult: Identifiable {
        let id = UUID()
        let port: UInt16
        let service: String
        let rttMs: Double
        var banner: String? = nil
    }

    private var task: Task<Void, Never>?

    func scan(host: String, ports: [UInt16], timeout: TimeInterval = 0.8,
              concurrency: Int = 40, grabBanners: Bool = true) {
        cancel()
        open = []
        progress = 0
        scopeError = nil

        // Hard limit: only local-network targets are allowed. This is
        // enforced in the scanner itself (not just the UI) so the rule
        // can't be bypassed by future callers.
        do {
            try LocalNetworkGuard.ensureLocal(host)
        } catch {
            scopeError = error.localizedDescription
            isScanning = false
            return
        }

        isScanning = true
        var done = 0
        let total = ports.count

        task = Task {
            await withTaskGroup(of: PortResult?.self) { group in
                let sem = AsyncSemaphore(value: concurrency)
                for port in ports {
                    await sem.wait()
                    group.addTask {
                        defer { Task { await sem.signal() } }
                        if let rtt = await TCPProbe.connect(host: host, port: port, timeout: timeout) {
                            var result = PortResult(port: port, service: Services.name(port), rttMs: rtt)
                            if grabBanners, let b = await BannerGrabber.grab(host: host, port: port) {
                                result.banner = b.summary
                            }
                            return result
                        }
                        return nil
                    }
                }
                for await r in group {
                    done += 1
                    progress = Double(done) / Double(total)
                    if let r { open.append(r); open.sort { $0.port < $1.port } }
                    if Task.isCancelled { break }
                }
            }
            isScanning = false
        }
    }

    func cancel() { task?.cancel(); task = nil; isScanning = false }
}

// MARK: - Async semaphore (caps concurrency without blocking threads)

actor AsyncSemaphore {
    private var permits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    init(value: Int) { permits = value }
    func wait() async {
        if permits > 0 { permits -= 1; return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func signal() {
        if let w = waiters.first { waiters.removeFirst(); w.resume() }
        else { permits += 1 }
    }
}
