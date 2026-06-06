import SwiftUI

struct HostScannerView: View {
    @StateObject private var scanner = HostScanner()
    @State private var subnetLabel = "—"
    @State private var hostList: [String] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel(title: "Target Subnet") {
                    VStack(spacing: 10) {
                        DataRow(key: "auto-detected", value: subnetLabel, valueColor: Theme.accent)
                        DataRow(key: "host candidates", value: "\(hostList.count)", valueColor: Theme.textDim)
                        if scanner.isScanning {
                            VStack(spacing: 6) {
                                ProgressView(value: scanner.progress).tint(Theme.accent)
                                Text("\(scanner.scannedCount)/\(scanner.totalCount) probed · \(scanner.hosts.count) alive")
                                    .font(Theme.monoSm).foregroundStyle(Theme.textDim)
                            }
                        }
                        if scanner.isScanning {
                            ActionButton(title: "Stop", systemImage: "stop.fill", color: Theme.danger) {
                                scanner.cancel()
                            }
                        } else {
                            ActionButton(title: "Start Sweep", systemImage: "play.fill") {
                                scanner.scan(hosts: hostList)
                            }
                        }
                    }
                }

                if !scanner.hosts.isEmpty {
                    Panel(title: "Live Hosts · \(scanner.hosts.count)") {
                        VStack(spacing: 0) {
                            ForEach(scanner.hosts) { host in
                                HostRow(host: host)
                                if host.id != scanner.hosts.last?.id {
                                    Divider().overlay(Theme.stroke)
                                }
                            }
                        }
                    }
                } else if !scanner.isScanning {
                    emptyState
                }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Host Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: detectSubnet)
    }

    private func detectSubnet() {
        let ifaces = NetInfo.interfaces()
        let chosen = ifaces.first(where: { $0.isWiFi && $0.ipv4 != nil })
            ?? ifaces.first(where: { $0.ipv4 != nil && !$0.isCellular })
            ?? ifaces.first(where: { $0.ipv4 != nil })
        guard let iface = chosen, let ip = iface.ipv4 else {
            subnetLabel = "No local network"
            return
        }
        let mask = iface.netmask ?? "255.255.255.0"
        subnetLabel = "\(ip)/\(NetInfo.cidr(from: mask))"
        hostList = NetInfo.hostRange(ip: ip, netmask: mask)
        if hostList.isEmpty { hostList = NetInfo.hostRange(ip: ip, netmask: "255.255.255.0") }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.largeTitle).foregroundStyle(Theme.textDim)
            Text("Run a sweep to map devices on your Wi-Fi.")
                .font(Theme.monoSm).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

struct HostRow: View {
    let host: DiscoveredHost
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(host.ip)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let rtt = host.rttMs {
                    Text(String(format: "%.0f ms", rtt))
                        .font(Theme.monoSm).foregroundStyle(Theme.textDim)
                }
            }
            if let name = host.hostname {
                Text(name).font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
            }
            if let vendor = host.vendorGuess {
                Text(vendor).font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(Theme.info)
            }
            if !host.openPorts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        ForEach(host.openPorts, id: \.self) { port in
                            Pill(text: "\(port) \(Services.name(port))", color: Theme.amber)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}
