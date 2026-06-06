import SwiftUI
import SwiftData

struct VulnInsightsView: View {
    @StateObject private var nvd = NVDClient()
    @State private var query = ""

    // Pull open ports from the last scan to show risk guidance automatically.
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]
    private var latest: ScanSession? { sessions.first }
    private var exposedPorts: [UInt16] {
        guard let latest else { return [] }
        let all = latest.devices.flatMap { $0.openPorts.map { UInt16($0) } }
        return Array(Set(all)).sorted()
    }
    private var guidance: [RiskGuidance] {
        exposedPorts.compactMap { RiskAdvisor.guidance(for: $0) }
            .sorted { $0.severity > $1.severity }
    }
    // Devices that have at least one risky port, with their guidance.
    private var riskyDevices: [(DeviceRecord, [RiskGuidance])] {
        guard let latest else { return [] }
        return latest.devices.compactMap { d in
            let g = d.openPorts.compactMap { RiskAdvisor.guidance(for: UInt16($0)) }
                .sorted { $0.severity > $1.severity }
            return g.isEmpty ? nil : (d, g)
        }
        .sorted { ($0.1.first?.severity ?? .info) > ($1.1.first?.severity ?? .info) }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                disclaimer
                if latest == nil {
                    emptyState
                } else {
                    networkSummary
                    if !riskyDevices.isEmpty { deviceBreakdownCard }
                    if !guidance.isEmpty { guidanceCard }
                }
                lookupCard
                if nvd.isLoading { loadingCard }
                if let err = nvd.error { errorCard(err) }
                if !nvd.results.isEmpty { resultsCard }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Vulnerability Insights")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var emptyState: some View {
        Panel {
            Text("Run a network scan first. Vulnerability Insights then analyzes the open ports found on your devices and flags what's worth checking.")
                .font(.subheadline).foregroundStyle(Theme.textDim)
        }
    }

    private var networkSummary: some View {
        let risky = riskyDevices.count
        let total = latest?.deviceCount ?? 0
        return Panel(title: "Your Network", accent: risky > 0 ? Theme.amber : Theme.good) {
            VStack(alignment: .leading, spacing: 8) {
                DataRow(key: "devices scanned", value: "\(total)", valueColor: Theme.textPrimary)
                DataRow(key: "exposed services", value: "\(exposedPorts.count)", valueColor: Theme.info)
                DataRow(key: "devices with risk notes", value: "\(risky)",
                        valueColor: risky > 0 ? Theme.amber : Theme.good)
            }
        }
    }

    private var deviceBreakdownCard: some View {
        Panel(title: "By Device", accent: Theme.danger) {
            VStack(spacing: 0) {
                ForEach(Array(riskyDevices.enumerated()), id: \.offset) { i, pair in
                    let (device, gs) = pair
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.hostname ?? device.ip)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text(device.ip).font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textDim)
                        ForEach(Array(gs.enumerated()), id: \.offset) { _, g in
                            HStack(spacing: 8) {
                                Pill(text: g.severity.label, color: sevColor(g.severity))
                                Text("\(g.service) · port \(g.port)")
                                    .font(.footnote).foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                        }
                    }
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if i < riskyDevices.count - 1 { Divider().overlay(Theme.stroke) }
                }
            }
        }
    }

    private var disclaimer: some View {
        Panel(accent: Theme.amber) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle.fill").foregroundStyle(Theme.amber)
                Text("CVE data comes from NIST's NVD. Matches depend on knowing a device's exact software version, which isn't always detectable — treat results as leads to verify, not a complete audit. No exploit instructions are provided.")
                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var lookupCard: some View {
        Panel(title: "CVE Lookup", accent: Theme.danger) {
            VStack(spacing: 10) {
                Text("Search NVD by product and version (e.g. \"OpenSSH 8.9\", \"nginx 1.18\").")
                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TextField("product version", text: $query)
                    .font(Theme.mono).foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .padding(10).background(Theme.surfaceHi).clipShape(RoundedRectangle(cornerRadius: 12))
                ActionButton(title: "Search NVD", systemImage: "magnifyingglass",
                             color: Theme.danger, running: nvd.isLoading) {
                    nvd.search(keyword: query)
                }
            }
        }
    }

    private var loadingCard: some View {
        Panel {
            HStack { ProgressView().controlSize(.small).tint(Theme.danger)
                Text("Querying NVD…").font(Theme.monoSm).foregroundStyle(Theme.textDim); Spacer() }
        }
    }

    private func errorCard(_ msg: String) -> some View {
        Panel(accent: Theme.danger) {
            Text(msg).font(Theme.monoSm).foregroundStyle(Theme.danger)
        }
    }

    private var resultsCard: some View {
        Panel(title: "CVEs for \"\(nvd.lastQuery)\" · \(nvd.results.count)", accent: Theme.danger) {
            VStack(spacing: 0) {
                ForEach(nvd.results) { cve in
                    CVERow(cve: cve)
                    if cve.id != nvd.results.last?.id { Divider().overlay(Theme.stroke) }
                }
            }
        }
    }

    private var guidanceCard: some View {
        Panel(title: "Exposed Service Guidance", accent: Theme.amber) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Based on open ports from your last scan. These are risk notes, not confirmed CVEs.")
                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                ForEach(Array(guidance.enumerated()), id: \.offset) { i, g in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Pill(text: g.severity.label, color: sevColor(g.severity))
                            Text("\(g.service) · port \(g.port)")
                                .font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        Text(g.concern).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                        Text("→ \(g.recommendation)").font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.vertical, 6)
                    if i < guidance.count - 1 { Divider().overlay(Theme.stroke) }
                }
            }
        }
    }

    private func sevColor(_ s: Severity) -> Color {
        [Theme.textDim, Theme.info, Theme.amber, Theme.danger][s.rawValue]
    }
}

struct CVERow: View {
    let cve: CVEItem
    @Environment(\.openURL) private var openURL

    private var color: Color {
        switch cve.severityRank {
        case 4: return Theme.danger
        case 3: return Theme.danger
        case 2: return Theme.amber
        case 1: return Theme.info
        default: return Theme.textDim
        }
    }

    var body: some View {
        Button { openURL(cve.nvdURL) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(cve.id).font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(color)
                    Spacer()
                    if let s = cve.score {
                        Text(String(format: "%.1f", s)).font(Theme.monoSm).foregroundStyle(color)
                    }
                    Pill(text: cve.severity, color: color)
                }
                Text(cve.description)
                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                    .lineLimit(3).multilineTextAlignment(.leading)
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.square").font(.system(.caption))
                    Text("View on NVD").font(.system(.caption, design: .monospaced))
                }.foregroundStyle(Theme.info)
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(cve.id), \(cve.severity) severity. \(cve.description). Opens NVD detail page.")
    }
}

// MARK: - CVE lookup (auto-runs a search for a given keyword)
// Used when jumping in from a device profile's banner.

struct CVELookupView: View {
    let keyword: String
    @StateObject private var nvd = NVDClient()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel(accent: Theme.amber) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Theme.amber)
                        Text("Results from NIST NVD for the detected banner. Verify the exact version on the device before acting. No exploit details are shown.")
                            .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                    }
                }
                if nvd.isLoading {
                    Panel { HStack { ProgressView().controlSize(.small).tint(Theme.danger)
                        Text("Querying NVD…").font(Theme.monoSm).foregroundStyle(Theme.textDim); Spacer() } }
                } else if let err = nvd.error {
                    Panel(accent: Theme.danger) { Text(err).font(Theme.monoSm).foregroundStyle(Theme.danger) }
                } else if nvd.results.isEmpty {
                    Panel { Text("No CVEs returned for \"\(keyword)\". This isn't a guarantee none exist — try a more specific version.")
                        .font(Theme.monoSm).foregroundStyle(Theme.textDim) }
                } else {
                    Panel(title: "CVEs · \(nvd.results.count)", accent: Theme.danger) {
                        VStack(spacing: 0) {
                            ForEach(nvd.results) { cve in
                                CVERow(cve: cve)
                                if cve.id != nvd.results.last?.id { Divider().overlay(Theme.stroke) }
                            }
                        }
                    }
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle("CVE: \(keyword)")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if nvd.results.isEmpty { nvd.search(keyword: keyword) } }
    }
}
