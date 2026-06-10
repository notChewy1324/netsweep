import SwiftUI
import SwiftData
import Charts

// MARK: - Network Overview
// An at-a-glance summary of YOUR OWN home network: current health, week-over-
// week new devices, hosts on the latest scan worth a closer look, and a feed
// of recent notable findings. Everything is informational — meant to help the
// owner understand their own gear, not to enable any kind of external probing.

struct ThreatDashboardView: View {
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]
    @Query private var tags: [DeviceTag]

    private var latest: ScanSession? { sessions.first }
    private var previous: ScanSession? { sessions.dropFirst().first }

    // Last 10 sessions (chronological) for the sparkline on the health card.
    private var sparkSessions: [ScanSession] {
        Array(sessions.prefix(10).reversed())
    }

    // Devices first seen in the last 7 days — dedup by IP, newest first.
    fileprivate struct NewDevice: Identifiable {
        var id: String { ip }
        let ip: String
        let hostname: String?
        let firstSeen: Date
        let ports: [Int]
        let trust: TrustLevel
    }
    private var newDevicesThisWeek: [NewDevice] {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        var seen = Set<String>()
        var out: [NewDevice] = []
        let tagByIP = Dictionary(uniqueKeysWithValues: tags.map { ($0.ip, $0) })
        for s in sessions where s.date >= cutoff {
            for d in s.devices where d.isNew && !seen.contains(d.ip) {
                seen.insert(d.ip)
                out.append(NewDevice(
                    ip: d.ip,
                    hostname: d.hostname,
                    firstSeen: d.firstSeen,
                    ports: d.openPorts,
                    trust: tagByIP[d.ip]?.trust ?? .unknown))
            }
        }
        return out.sorted { $0.firstSeen > $1.firstSeen }
    }

    // Per-host risk score derived from finding severities on the latest scan.
    fileprivate struct RiskyHost: Identifiable {
        var id: String { ip }
        let ip: String
        let hostname: String?
        let score: Int
        let findings: [Finding]
        let maxSeverity: Severity
    }
    private var riskyHostsInLatest: [RiskyHost] {
        guard let s = latest else { return [] }
        let byIP = Dictionary(grouping: s.findings.compactMap { f -> (String, Finding)? in
            guard let ip = f.deviceIP else { return nil }
            return (ip, f)
        }, by: { $0.0 }).mapValues { $0.map { $0.1 } }
        return byIP.map { ip, findings in
            let weight = findings.reduce(0) { acc, f in
                acc + [0, 1, 4, 10][f.severity.rawValue]
            }
            let host = s.devices.first { $0.ip == ip }
            let maxSev = findings.map(\.severity).max() ?? .info
            return RiskyHost(
                ip: ip,
                hostname: host?.hostname,
                score: weight,
                findings: findings.sorted { $0.severity > $1.severity },
                maxSeverity: maxSev)
        }.sorted { $0.score > $1.score }
        .prefix(5)
        .map { $0 }
    }

    // Recent high+medium findings across the last 5 sessions, newest first.
    private struct RecentFinding: Identifiable {
        let id = UUID()
        let date: Date
        let finding: Finding
        let sessionID: UUID
    }
    private var recentSeriousFindings: [RecentFinding] {
        var out: [RecentFinding] = []
        for s in sessions.prefix(5) {
            for f in s.findings where f.severity >= .medium {
                out.append(RecentFinding(date: s.date, finding: f, sessionID: s.id))
            }
        }
        return Array(out.sorted { $0.date > $1.date }.prefix(8))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if sessions.isEmpty {
                    emptyState
                } else if let s = latest {
                    healthCard(for: s)
                    quickStatsRow
                    if !newDevicesThisWeek.isEmpty { newDevicesCard }
                    if !riskyHostsInLatest.isEmpty { riskyHostsCard }
                    if !recentSeriousFindings.isEmpty { recentFindingsCard }
                    if newDevicesThisWeek.isEmpty
                        && riskyHostsInLatest.isEmpty
                        && recentSeriousFindings.isEmpty {
                        allClearCard
                    }
                    trendsLink
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.textDim)
            Text("No scans yet")
                .font(Theme.monoSm).foregroundStyle(Theme.textDim)
            Text("Run a scan from Home to populate your dashboard.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textFaint)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }

    // MARK: Health card

    private func healthCard(for s: ScanSession) -> some View {
        let (gradeLabel, _) = SecurityAnalysis.grade(s.healthScore)
        let color = SecurityAnalysis.color(for: s.healthScore)
        let delta: Int? = previous.map { s.healthScore - $0.healthScore }
        return Panel(title: "Network Health", accent: color) {
            VStack(spacing: 14) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text("\(s.healthScore)")
                        .font(.system(size: 64, weight: .heavy, design: .monospaced))
                        .foregroundStyle(color)
                        .glow(color, radius: 6)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(gradeLabel)
                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .tracking(2)
                            .foregroundStyle(color)
                        if let delta {
                            HStack(spacing: 4) {
                                Image(systemName: deltaIcon(delta))
                                    .font(.caption2.weight(.bold))
                                Text(delta == 0 ? "no change" : "\(abs(delta)) vs prior")
                            }
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(deltaColor(delta))
                        }
                        Text(s.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer(minLength: 4)
                    if sparkSessions.count >= 2 {
                        sparkline(color: color).frame(width: 72, height: 38)
                    }
                }
                Text(SecurityAnalysis.summary(score: s.healthScore,
                                              deviceCount: s.deviceCount,
                                              newCount: s.newDeviceCount))
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func deltaIcon(_ delta: Int) -> String {
        if delta == 0 { return "minus" }
        return delta > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    private func deltaColor(_ delta: Int) -> Color {
        if delta == 0 { return Theme.textDim }
        return delta > 0 ? Theme.good : Theme.danger
    }

    private func sparkline(color: Color) -> some View {
        Chart(sparkSessions) { s in
            LineMark(
                x: .value("Date", s.date),
                y: .value("Score", s.healthScore))
                .foregroundStyle(color)
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            AreaMark(
                x: .value("Date", s.date),
                y: .value("Score", s.healthScore))
                .foregroundStyle(.linearGradient(
                    colors: [color.opacity(0.35), .clear],
                    startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...100)
        .accessibilityHidden(true)
    }

    // MARK: Quick stats row

    private var quickStatsRow: some View {
        HStack(spacing: 10) {
            StatTile(
                value: "\(newDevicesThisWeek.count)",
                label: "NEW · 7d",
                color: newDevicesThisWeek.isEmpty ? Theme.textDim : Theme.amber,
                icon: "sparkles")
            StatTile(
                value: "\(riskyHostsInLatest.count)",
                label: "TO REVIEW",
                color: riskyHostsInLatest.isEmpty ? Theme.textDim : Theme.danger,
                icon: "exclamationmark.shield")
            StatTile(
                value: "\(sessions.count)",
                label: "SCANS",
                color: Theme.info,
                icon: "clock.arrow.circlepath")
        }
    }

    // MARK: New devices card

    private var newDevicesCard: some View {
        Panel(title: "New Devices · 7 Days", accent: Theme.amber) {
            VStack(spacing: 0) {
                ForEach(newDevicesThisWeek.prefix(5)) { d in
                    NewDeviceRow(device: d)
                    if d.id != newDevicesThisWeek.prefix(5).last?.id {
                        Divider().overlay(Theme.stroke)
                    }
                }
                if newDevicesThisWeek.count > 5 {
                    Text("+\(newDevicesThisWeek.count - 5) more")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .padding(.top, 10)
                }
            }
        }
    }

    // MARK: Risky hosts card

    private var riskyHostsCard: some View {
        Panel(title: "Devices Worth A Look · Latest Scan", accent: Theme.danger) {
            VStack(spacing: 0) {
                ForEach(riskyHostsInLatest) { host in
                    RiskyHostRow(host: host)
                    if host.id != riskyHostsInLatest.last?.id {
                        Divider().overlay(Theme.stroke)
                    }
                }
            }
        }
    }

    // MARK: Recent findings card

    private var recentFindingsCard: some View {
        Panel(title: "Recent Activity", accent: Theme.info) {
            VStack(spacing: 0) {
                ForEach(recentSeriousFindings) { rf in
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(severityColor(rf.finding.severity))
                            .frame(width: 7, height: 7)
                            .padding(.top, 6)
                            .shadow(color: severityColor(rf.finding.severity).opacity(0.6), radius: 4)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(rf.finding.title)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            Text(rf.date.formatted(.relative(presentation: .named)))
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.textFaint)
                        }
                        Spacer(minLength: 8)
                        Pill(text: rf.finding.severity.label,
                             color: severityColor(rf.finding.severity))
                    }
                    .padding(.vertical, 9)
                    if rf.id != recentSeriousFindings.last?.id {
                        Divider().overlay(Theme.stroke)
                    }
                }
            }
        }
    }

    private func severityColor(_ s: Severity) -> Color {
        [Theme.textDim, Theme.info, Theme.amber, Theme.danger][s.rawValue]
    }

    // MARK: All-clear

    private var allClearCard: some View {
        Panel(title: "All Clear", accent: Theme.good) {
            HStack(spacing: 14) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.title)
                    .foregroundStyle(Theme.good)
                    .glow(Theme.good, radius: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nothing notable, no new devices this week.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your home network looks calm.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Trends link

    private var trendsLink: some View {
        NavigationLink {
            TrendsView()
                .zoomDestination("dashboard-trends")
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Explore Trends")
                        .font(.body.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Interactive charts · score breakdown")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textFaint)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(
                                LinearGradient(colors: [Theme.stroke, .clear],
                                               startPoint: .top, endPoint: .bottom),
                                lineWidth: 1)
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .zoomSource("dashboard-trends")
        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
    }
}

// MARK: - Stat tile (used in quick-stats row)

private struct StatTile: View {
    let value: String
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.caption.weight(.semibold))
                Text(label).font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1.2)
            }
            .foregroundStyle(color)
            Text(value)
                .font(.system(size: 26, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(color.opacity(0.22), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
    }
}

// MARK: - New device row

private struct NewDeviceRow: View {
    let device: ThreatDashboardView.NewDevice

    private var trustColor: Color {
        switch device.trust {
        case .trusted: return Theme.good
        case .blocked: return Theme.danger
        case .unknown: return Theme.amber
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.subheadline)
                .foregroundStyle(Theme.amber)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.hostname ?? device.ip)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(device.ip)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    if !device.ports.isEmpty {
                        Text("·").foregroundStyle(Theme.textFaint)
                        Text("\(device.ports.count) port\(device.ports.count == 1 ? "" : "s")")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(device.firstSeen.formatted(.relative(presentation: .named)))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                Pill(text: device.trust.label.uppercased(), color: trustColor)
            }
        }
        .padding(.vertical, 9)
    }
}

// MARK: - Risky host row

private struct RiskyHostRow: View {
    let host: ThreatDashboardView.RiskyHost

    private var severityColor: Color {
        [Theme.textDim, Theme.info, Theme.amber, Theme.danger][host.maxSeverity.rawValue]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(severityColor)
                    .frame(width: 9, height: 9)
                    .shadow(color: severityColor.opacity(0.7), radius: 4)
                Text(host.hostname ?? host.ip)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Pill(text: "\(host.findings.count) issue\(host.findings.count == 1 ? "" : "s")",
                     color: severityColor)
            }
            if host.hostname != nil {
                Text(host.ip)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .padding(.leading, 19)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(host.findings.prefix(2)) { f in
                    Text("• \(f.title)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
                if host.findings.count > 2 {
                    Text("+\(host.findings.count - 2) more")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.leading, 19)
        }
        .padding(.vertical, 10)
    }
}
