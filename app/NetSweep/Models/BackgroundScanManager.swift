import Foundation
import BackgroundTasks
import SwiftData

// MARK: - Background scan manager
// Uses BGAppRefreshTask — the ONLY legitimate background mechanism on iOS for
// this. Important honest caveats baked into the design:
//   • iOS schedules these OPPORTUNISTICALLY (often hours apart, sometimes not at
//     all). There is no guaranteed interval. This is NOT continuous monitoring.
//   • Background runtime is short (seconds), so we run a fast, lightweight sweep
//     of the local /24, compare against the last known device set, and notify
//     only if something new appears.
//   • Requires the user to have scanned at least once on Wi-Fi so we know the
//     subnet, and only runs meaningfully when on Wi-Fi.
//
// The UI is explicit that this is "occasional background checks," not a watchdog.

enum BackgroundScanManager {
    static let taskIdentifier = "com.camgarrison.netsweep.devicecheck"

    /// Register the launch handler. Call once at app launch.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask)
        }
    }

    /// Ask iOS to schedule the next opportunistic refresh (earliest ~hours out).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 60 * 60) // ~2h, a floor not a guarantee
        try? BGTaskScheduler.shared.submit(request)
    }

    static func cancel() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
    }

    private static func handle(_ task: BGAppRefreshTask) {
        // Always schedule the next one first.
        schedule()

        let work = Task {
            await runQuietSweep()
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = {
            work.cancel()
            task.setTaskCompleted(success: false)
        }
    }

    /// A fast, best-effort sweep that notifies only on newly-seen devices.
    private static func runQuietSweep() async {
        // Find the primary IPv4 interface (prefer Wi-Fi).
        let ifaces = NetInfo.interfaces()
        let primary = ifaces.first { $0.isWiFi && $0.ipv4 != nil }
            ?? ifaces.first { $0.ipv4 != nil && !$0.isCellular }
        guard let info = primary, let ip = info.ipv4, let mask = info.netmask else { return }

        let hosts = NetInfo.hostRange(ip: ip, netmask: mask)
        guard !hosts.isEmpty else { return }

        // Lightweight reachability probe on a couple of common ports per host,
        // bounded concurrency to respect the short background budget.
        let probePorts: [UInt16] = [80, 443, 22, 53]
        var found: [String] = []
        await withTaskGroup(of: String?.self) { group in
            var active = 0
            for host in hosts {
                if active >= 16 {
                    if let r = await group.next(), let ip = r { found.append(ip) }
                    active -= 1
                }
                group.addTask {
                    for p in probePorts {
                        if await TCPProbe.connect(host: host, port: p, timeout: 0.4) != nil {
                            return host
                        }
                    }
                    return nil
                }
                active += 1
            }
            for await r in group { if let ip = r { found.append(ip) } }
        }

        // Compare against the persisted "known IPs" snapshot.
        let knownKey = "bg.knownIPs"
        let prior = Set(UserDefaults.standard.stringArray(forKey: knownKey) ?? [])
        let current = Set(found)
        let newOnes = current.subtracting(prior)

        // Persist the union so we don't re-alert on the same device.
        UserDefaults.standard.set(Array(prior.union(current)), forKey: knownKey)

        // Only alert if we have a prior baseline (don't flood on first run).
        if !prior.isEmpty && !newOnes.isEmpty {
            await NotificationManager.shared.notifyNewDevices(
                count: newOnes.count, networkName: "your network")
        }
    }
}
