import SwiftUI
import SwiftData

struct DeviceProfileView: View {
    let ip: String
    let hostname: String?
    var vendorGuess: String?

    @StateObject private var scanner = DeepScanner()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                headerCard
                if scanner.isScanning { progressCard } else { scanControl }
                if let r = scanner.result, !scanner.isScanning {
                    profileCard(r)
                    if !r.findings.isEmpty { findingsCard(r) }
                    portsCard(r)
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle(hostname ?? ip)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if scanner.result == nil { scanner.scan(ip: ip, hostname: hostname) }
        }
        .onDisappear { scanner.cancel() }
    }

    private var headerCard: some View {
        Panel(accent: Theme.accent) {
            VStack(alignment: .leading, spacing: 6) {
                Text(ip).font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.accent).textSelection(.enabled)
                if let hostname { DataRow(key: "hostname", value: hostname) }
                if let v = vendorGuess { DataRow(key: "vendor", value: v, valueColor: Theme.info) }
            }
        }
    }

    private var progressCard: some View {
        Panel {
            VStack(spacing: 10) {
                ProgressView(value: scanner.progress).tint(Theme.accent)
                Text(scanner.phase).font(Theme.monoSm).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var scanControl: some View {
        VStack(spacing: 8) {
            ActionButton(title: scanner.result == nil ? "Full Scan · every common port" : "Full Scan again",
                         systemImage: "magnifyingglass") {
                scanner.scan(ip: ip, hostname: hostname)
            }
            ActionButton(title: "Fast Scan · 20 most common ports", systemImage: "bolt", color: Theme.amber) {
                scanner.scan(ip: ip, hostname: hostname, quick: true)
            }
            Text("Ports are the doors a device leaves open for services like web or file sharing. Fast checks the 20 most common; Full checks the wider set — slower, but more thorough.")
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private func profileCard(_ r: DeepScanResult) -> some View {
        Panel(title: "Profile", accent: Theme.info) {
            VStack(spacing: 8) {
                DataRow(key: "device type", value: r.deviceType ?? "unknown",
                        valueColor: r.deviceType != nil ? Theme.accent : Theme.textDim)
                DataRow(key: "likely OS", value: r.osGuess ?? "unknown",
                        valueColor: r.osGuess != nil ? Theme.accent : Theme.textDim)
                DataRow(key: "open ports", value: "\(r.openPorts.count)")
                if let rtt = r.rttMs { DataRow(key: "latency", value: String(format: "%.0f ms", rtt)) }
            }
        }
    }

    private func findingsCard(_ r: DeepScanResult) -> some View {
        Panel(title: "Findings · \(r.findings.count)", accent: Theme.amber) {
            VStack(spacing: 0) {
                ForEach(Array(r.findings.enumerated()), id: \.offset) { i, f in
                    AnalyzedFindingRow(finding: f)
                    if i < r.findings.count - 1 { Divider().overlay(Theme.stroke) }
                }
            }
        }
    }

    private func portsCard(_ r: DeepScanResult) -> some View {
        Panel(title: "Open Ports · \(r.openPorts.count)") {
            VStack(spacing: 0) {
                ForEach(r.openPorts) { p in
                    VStack(spacing: 4) {
                        HStack {
                            Text("\(p.port)")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.amber).frame(width: 56, alignment: .leading)
                            Text(p.service).font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        if let banner = p.banner {
                            HStack {
                                Image(systemName: "tag.fill").font(.system(.caption2)).foregroundStyle(Theme.info)
                                Text(banner).font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(Theme.info).lineLimit(1).textSelection(.enabled)
                                Spacer()
                            }.padding(.leading, 56)
                            if let keyword = RiskAdvisor.nvdKeyword(fromBanner: banner) {
                                NavigationLink {
                                    CVELookupView(keyword: keyword)
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "ladybug").font(.system(.caption2))
                                        Text("Check CVEs for \(keyword)")
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                        Image(systemName: "chevron.right").font(.system(.caption2))
                                    }
                                    .foregroundStyle(Theme.danger)
                                    .padding(.leading, 56)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    if p.id != r.openPorts.last?.id { Divider().overlay(Theme.stroke) }
                }
                if r.openPorts.isEmpty {
                    Text("No open ports found.").font(Theme.monoSm)
                        .foregroundStyle(Theme.textDim).padding(.vertical, 12)
                }
            }
        }
    }
}

// A findings row that takes AnalyzedFinding (vs the SwiftData Finding model).
struct AnalyzedFindingRow: View {
    let finding: AnalyzedFinding
    private var color: Color {
        [Theme.textDim, Theme.info, Theme.amber, Theme.danger][finding.severity.rawValue]
    }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Pill(text: finding.severity.label, color: color).frame(width: 70, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                Text(finding.detail).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(finding.severity.label) severity. \(finding.title). \(finding.detail)")
    }
}
