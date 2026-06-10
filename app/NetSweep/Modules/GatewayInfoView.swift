import SwiftUI

// MARK: - Gateway info
// Details about the network's gateway/router and the local link, reachable by
// tapping the central star on the canvas. Offers a deep scan of the gateway.

struct GatewayInfoView: View {
    @StateObject private var path = PathMonitor()
    @StateObject private var lookup = PublicEndpointLookup()
    @StateObject private var gwScanner = DeepScanner()
    @State private var interfaces: [InterfaceInfo] = []
    @State private var radio: RadioInfo?
    @State private var gwScanStarted = false

    private var primary: InterfaceInfo? {
        interfaces.first { $0.isWiFi && $0.ipv4 != nil }
            ?? interfaces.first { $0.ipv4 != nil && !$0.isCellular }
            ?? interfaces.first { $0.ipv4 != nil }
    }
    private var gateway: String? {
        guard let p = primary, let ip = p.ipv4, let mask = p.netmask else { return nil }
        return NetInfo.gatewayIP(ip: ip, netmask: mask)
    }
    // On cellular when the active path is cellular and there's no Wi-Fi gateway.
    private var onCellular: Bool {
        path.interfaceType == "CELLULAR" || (gateway == nil && radio != nil)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if onCellular {
                    cellularSection
                } else {
                    wifiSection
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle(onCellular ? "Cellular" : "Gateway")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            path.start(); interfaces = NetInfo.interfaces(); radio = Cellular.current()
            if lookup.endpoint == nil { lookup.fetch() }
        }
        // Kick off the auto-fingerprint as soon as we know the gateway IP. On
        // cellular `gateway` stays nil (there's no LAN router to probe), so this
        // simply never fires.
        .onChange(of: gateway, initial: true) { _, new in
            guard !gwScanStarted, let gw = new else { return }
            gwScanStarted = true
            gwScanner.scan(ip: gw, hostname: "Gateway", quick: true)
        }
        .onDisappear { path.stop(); gwScanner.cancel() }
    }

    // MARK: Cellular mode

    @ViewBuilder
    private var cellularSection: some View {
        Panel(accent: Theme.info) {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right").font(.title)
                    .foregroundStyle(Theme.info)
                    .frame(width: 48, height: 48)
                    .background(Theme.info.opacity(0.14), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cellular Connection").font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(radio?.detail ?? "Mobile data")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(Theme.info)
                }
                Spacer()
            }
        }

        Panel(title: "Radio") {
            VStack(spacing: 8) {
                HStack {
                    Pill(text: path.status, color: path.status == "ONLINE" ? Theme.good : Theme.danger)
                    Pill(text: radio?.technology ?? "Cellular", color: Theme.info)
                    if path.isExpensive { Pill(text: "Metered", color: Theme.amber) }
                    if path.isConstrained { Pill(text: "Low Data", color: Theme.amber) }
                    Spacer()
                }
                DataRow(key: "radio access", value: radio?.detail ?? "Unknown", valueColor: Theme.info)
                if let c = radio?.carrier { DataRow(key: "carrier", value: c) }
                DataRow(key: "IPv4", value: path.supportsIPv4 ? "supported" : "no",
                        valueColor: path.supportsIPv4 ? Theme.good : Theme.textDim)
                DataRow(key: "IPv6", value: path.supportsIPv6 ? "supported" : "no",
                        valueColor: path.supportsIPv6 ? Theme.good : Theme.textDim)
            }
        }

        Panel(title: "What The Internet Sees", accent: Theme.amber) {
            VStack(spacing: 8) {
                if lookup.isLoading {
                    HStack { ProgressView().controlSize(.small).tint(Theme.amber)
                        Text("Looking up…").font(Theme.monoSm).foregroundStyle(Theme.textDim); Spacer() }
                } else if let e = lookup.endpoint {
                    DataRow(key: "public IP", value: e.ip ?? "—", valueColor: Theme.accent)
                    DataRow(key: "carrier / ISP", value: e.org ?? "—")
                    if let asn = e.asn { DataRow(key: "ASN", value: asn) }
                }
            }
        }

        Panel(title: "Note", accent: Theme.textDim) {
            Text("On cellular there's no local network to map — your device connects directly to your carrier, not a router with other devices. iOS also restricts cellular details (signal strength, tower info, and bands are off-limits to apps), so this shows everything the system allows.")
                .font(.footnote).foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Wi-Fi mode

    @ViewBuilder
    private var wifiSection: some View {
                Panel(accent: Theme.accent) {
                    HStack(spacing: 12) {
                        Image(systemName: "wifi.router").font(.title).foregroundStyle(Theme.accent)
                            .frame(width: 48, height: 48)
                            .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Gateway").font(.headline).foregroundStyle(Theme.textPrimary)
                            Text(gateway ?? "Unknown")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Theme.accent).textSelection(.enabled)
                        }
                        Spacer()
                    }
                }

                Panel(title: "Local Link") {
                    VStack(spacing: 8) {
                        HStack {
                            Pill(text: path.status, color: path.status == "ONLINE" ? Theme.good : Theme.danger)
                            Pill(text: path.interfaceType, color: Theme.info)
                            Spacer()
                        }
                        if let p = primary, let ip = p.ipv4 {
                            DataRow(key: "your IP", value: ip, valueColor: Theme.textPrimary)
                            if let mask = p.netmask {
                                DataRow(key: "subnet", value: "\(ip)/\(NetInfo.cidr(from: mask))", valueColor: Theme.purple)
                                DataRow(key: "netmask", value: mask, valueColor: Theme.textDim)
                            }
                            DataRow(key: "interface", value: p.name, valueColor: Theme.textDim)
                        }
                    }
                }

                gatewayFingerprintCard

                Panel(title: "What The Internet Sees", accent: Theme.amber) {
                    VStack(spacing: 8) {
                        if lookup.isLoading {
                            HStack { ProgressView().controlSize(.small).tint(Theme.amber)
                                Text("Looking up…").font(Theme.monoSm).foregroundStyle(Theme.textDim); Spacer() }
                        } else if let e = lookup.endpoint {
                            DataRow(key: "public IP", value: e.ip ?? "—", valueColor: Theme.accent)
                            DataRow(key: "ISP", value: e.org ?? "—")
                            if let asn = e.asn { DataRow(key: "ASN", value: asn) }
                        }
                    }
                }

                if let gw = gateway {
                    NavigationLink {
                        DeviceProfileView(ip: gw, hostname: "Gateway", vendorGuess: "Router")
                            .zoomDestination("gw-\(gw)")
                    } label: {
                        Panel(accent: Theme.accent) {
                            HStack {
                                Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
                                Text("Full scan · every common port").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                    .zoomSource("gw-\(gw)")
                }
    }

    // MARK: Auto-fingerprint card
    // Runs a quick deep-scan on the gateway IP as soon as we know it, then
    // shows the inferred device type, OS, vendor, and open ports with banners
    // — all in-place, no drill-in required. Tapping the "Full scan" button
    // still pushes the rich DeviceProfileView for everything we couldn't fit.

    @ViewBuilder
    private var gatewayFingerprintCard: some View {
        Panel(title: "Gateway Fingerprint", accent: Theme.info) {
            VStack(alignment: .leading, spacing: 10) {
                if gwScanner.isScanning {
                    HStack {
                        ProgressView().controlSize(.small).tint(Theme.info)
                        Text(gwScanner.phase.isEmpty ? "Probing…" : gwScanner.phase)
                            .font(Theme.monoSm).foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                    ProgressView(value: gwScanner.progress).tint(Theme.info)
                } else if let r = gwScanner.result {
                    DataRow(key: "device type",
                            value: r.deviceType ?? "Unknown",
                            valueColor: Theme.accent)
                    DataRow(key: "OS guess",
                            value: r.osGuess ?? "Unknown",
                            valueColor: Theme.info)
                    DataRow(key: "vendor",
                            value: routerVendor(from: r) ?? "Unknown",
                            valueColor: Theme.amber)
                    if let rtt = r.rttMs {
                        DataRow(key: "RTT",
                                value: String(format: "%.0f ms", rtt),
                                valueColor: Theme.textDim)
                    }
                    Divider().overlay(Theme.stroke)
                    Text("Open ports · \(r.openPorts.count)")
                        .font(.system(.caption, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.textDim)
                    if r.openPorts.isEmpty {
                        Text("No common ports responded. The router is probably firewalled to the LAN.")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(r.openPorts) { p in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(p.port)")
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .foregroundStyle(Theme.amber)
                                        .frame(width: 56, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.service)
                                            .font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                                        if let b = p.banner {
                                            Text(b)
                                                .font(.system(.footnote, design: .monospaced))
                                                .foregroundStyle(Theme.info)
                                                .lineLimit(2)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    Spacer()
                                }
                            }
                        }
                    }
                } else {
                    Text("Waiting on gateway address…")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    // Best-effort router brand inference from collected banners. iOS doesn't
    // expose MAC addresses to apps, so we can't do OUI lookup — banners (SSH,
    // HTTP Server:, FTP welcome lines) are what we have.
    private func routerVendor(from result: DeepScanResult) -> String? {
        let bag = result.openPorts
            .compactMap { $0.banner?.lowercased() }
            .joined(separator: " ")
        guard !bag.isEmpty else { return nil }
        let brands: [(String, String)] = [
            ("mikrotik", "MikroTik"), ("routeros", "MikroTik"),
            ("asuswrt", "ASUS"), ("asus", "ASUS"),
            ("netgear", "Netgear"),
            ("tp-link", "TP-Link"), ("tplink", "TP-Link"), ("archer", "TP-Link"),
            ("d-link", "D-Link"), ("dlink", "D-Link"),
            ("ubnt", "Ubiquiti"), ("ubiquiti", "Ubiquiti"), ("edgerouter", "Ubiquiti"),
            ("openwrt", "OpenWrt"), ("dd-wrt", "DD-WRT"), ("lede", "OpenWrt"),
            ("draytek", "DrayTek"),
            ("huawei", "Huawei"), ("zte", "ZTE"),
            ("linksys", "Linksys"), ("cisco", "Cisco"),
            ("synology", "Synology"), ("qnap", "QNAP"),
            ("eero", "eero"), ("google wifi", "Google"), ("nest wifi", "Google"),
            ("xfinity", "Comcast/Xfinity"), ("att", "AT&T"),
            ("verizon", "Verizon"), ("fritz", "AVM Fritz!Box"),
            ("pfsense", "pfSense"), ("opnsense", "OPNsense")
        ]
        for (needle, label) in brands where bag.contains(needle) {
            return label
        }
        return nil
    }
}
