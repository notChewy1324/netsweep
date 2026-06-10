import SwiftUI
import SwiftData

// MARK: - Scan Diff
// Pick two scan sessions and see what changed: added/removed devices, hosts
// whose open-port set drifted, score delta, and added/resolved findings.
// Defaults to (B = latest, A = the prior scan) so the most common question —
// "what's different now?" — is one tap away.

struct ScanDiffView: View {
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]

    @State private var aID: UUID?      // older scan (baseline)
    @State private var bID: UUID?      // newer scan (current)

    private var sessionA: ScanSession? { sessions.first { $0.id == aID } }
    private var sessionB: ScanSession? { sessions.first { $0.id == bID } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if sessions.count < 2 {
                    emptyState
                } else {
                    pickerCard
                    if let a = sessionA, let b = sessionB, a.id != b.id {
                        let diff = Diff.compute(a: a, b: b)
                        summaryCard(a: a, b: b, diff: diff)
                        devicesCard(diff: diff)
                        findingsCard(diff: diff)
                    } else if sessionA?.id == sessionB?.id {
                        sameScanHint
                    }
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if aID == nil || bID == nil {
                bID = sessions.first?.id
                aID = sessions.dropFirst().first?.id
            }
        }
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle")
                .font(.largeTitle).foregroundStyle(Theme.textDim)
            Text("Need two scans to compare.")
                .font(Theme.monoSm).foregroundStyle(Theme.textDim)
            Text("Run at least two scans, then come back to see what's different.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private var sameScanHint: some View {
        HStack(spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Theme.amber)
            Text("Pick two different scans to see a diff.")
                .font(.footnote).foregroundStyle(Theme.textDim)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.amber.opacity(0.2), lineWidth: 1))
        )
    }

    // MARK: Picker

    private var pickerCard: some View {
        Panel(title: "Choose Scans", accent: Theme.purple) {
            HStack(alignment: .top, spacing: 12) {
                ScanPickerColumn(
                    label: "BASELINE",
                    accent: Theme.textDim,
                    sessions: sessions,
                    selectedID: $aID)
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.purple)
                    .padding(.top, 30)
                ScanPickerColumn(
                    label: "COMPARED",
                    accent: Theme.purple,
                    sessions: sessions,
                    selectedID: $bID)
            }
        }
    }

    // MARK: Summary

    private func summaryCard(a: ScanSession, b: ScanSession, diff: Diff) -> some View {
        let scoreDelta = b.healthScore - a.healthScore
        let deltaColor: Color = scoreDelta == 0 ? Theme.textDim
            : (scoreDelta > 0 ? Theme.good : Theme.danger)
        let deltaIcon: String = scoreDelta == 0 ? "minus"
            : (scoreDelta > 0 ? "arrow.up.right" : "arrow.down.right")
        return Panel(title: "Summary", accent: deltaColor) {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    DiffScoreColumn(score: a.healthScore, label: "BEFORE")
                    Image(systemName: deltaIcon)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(deltaColor)
                        .glow(deltaColor, radius: 4)
                    DiffScoreColumn(score: b.healthScore, label: "AFTER", color: Theme.accent)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(scoreDelta == 0 ? "no change" : (scoreDelta > 0 ? "+\(scoreDelta)" : "\(scoreDelta)"))
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundStyle(deltaColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("SCORE Δ")
                            .font(.system(.caption2, design: .monospaced).weight(.bold))
                            .tracking(1.2)
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                Divider().overlay(Theme.stroke)
                HStack(spacing: 10) {
                    CountTile(value: diff.added.count, label: "ADDED",
                              color: diff.added.isEmpty ? Theme.textDim : Theme.good,
                              icon: "plus.circle")
                    CountTile(value: diff.removed.count, label: "REMOVED",
                              color: diff.removed.isEmpty ? Theme.textDim : Theme.danger,
                              icon: "minus.circle")
                    CountTile(value: diff.changed.count, label: "CHANGED",
                              color: diff.changed.isEmpty ? Theme.textDim : Theme.amber,
                              icon: "arrow.left.and.right.circle")
                }
                Text(diff.headline(a: a, b: b))
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Device diffs

    @ViewBuilder
    private func devicesCard(diff: Diff) -> some View {
        if !diff.added.isEmpty {
            Panel(title: "Added · \(diff.added.count)", accent: Theme.good) {
                VStack(spacing: 0) {
                    ForEach(diff.added) { d in
                        DeviceDiffRow(symbol: "plus", color: Theme.good,
                                      title: d.label, subtitle: d.ip,
                                      detail: portList(d.ports))
                        if d.id != diff.added.last?.id { Divider().overlay(Theme.stroke) }
                    }
                }
            }
        }
        if !diff.removed.isEmpty {
            Panel(title: "Removed · \(diff.removed.count)", accent: Theme.danger) {
                VStack(spacing: 0) {
                    ForEach(diff.removed) { d in
                        DeviceDiffRow(symbol: "minus", color: Theme.danger,
                                      title: d.label, subtitle: d.ip,
                                      detail: portList(d.ports))
                        if d.id != diff.removed.last?.id { Divider().overlay(Theme.stroke) }
                    }
                }
            }
        }
        if !diff.changed.isEmpty {
            Panel(title: "Changed Ports · \(diff.changed.count)", accent: Theme.amber) {
                VStack(spacing: 0) {
                    ForEach(diff.changed) { c in
                        ChangedDeviceRow(change: c)
                        if c.id != diff.changed.last?.id { Divider().overlay(Theme.stroke) }
                    }
                }
            }
        }
        if diff.added.isEmpty && diff.removed.isEmpty && diff.changed.isEmpty {
            Panel(title: "No Device Changes", accent: Theme.good) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.good)
                    Text("Same devices, same open ports.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
            }
        }
    }

    // MARK: Findings diff

    @ViewBuilder
    private func findingsCard(diff: Diff) -> some View {
        if !diff.newFindings.isEmpty || !diff.resolvedFindings.isEmpty {
            Panel(title: "Findings Δ", accent: Theme.info) {
                VStack(spacing: 10) {
                    if !diff.newFindings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("NEW · \(diff.newFindings.count)")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(Theme.danger)
                            ForEach(diff.newFindings) { f in
                                FindingDeltaRow(finding: f, isNew: true)
                            }
                        }
                    }
                    if !diff.newFindings.isEmpty && !diff.resolvedFindings.isEmpty {
                        Divider().overlay(Theme.stroke)
                    }
                    if !diff.resolvedFindings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("RESOLVED · \(diff.resolvedFindings.count)")
                                .font(.system(.caption2, design: .monospaced).weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(Theme.good)
                            ForEach(diff.resolvedFindings) { f in
                                FindingDeltaRow(finding: f, isNew: false)
                            }
                        }
                    }
                }
            }
        }
    }

    private func portList(_ ports: [Int]) -> String? {
        guard !ports.isEmpty else { return nil }
        let trimmed = ports.prefix(6).map(String.init).joined(separator: ", ")
        return ports.count > 6 ? "\(trimmed) +\(ports.count - 6)" : trimmed
    }
}

// MARK: - Diff computation

private struct Diff {
    var added: [DeviceSnapshot]
    var removed: [DeviceSnapshot]
    var changed: [DeviceChange]
    var newFindings: [FindingSnapshot]
    var resolvedFindings: [FindingSnapshot]

    static func compute(a: ScanSession, b: ScanSession) -> Diff {
        let aMap = Dictionary(uniqueKeysWithValues: a.devices.map { ($0.ip, $0) })
        let bMap = Dictionary(uniqueKeysWithValues: b.devices.map { ($0.ip, $0) })
        let aIPs = Set(aMap.keys)
        let bIPs = Set(bMap.keys)

        let addedIPs = bIPs.subtracting(aIPs).sorted { ipSort($0, $1) }
        let removedIPs = aIPs.subtracting(bIPs).sorted { ipSort($0, $1) }
        let sharedIPs = aIPs.intersection(bIPs).sorted { ipSort($0, $1) }

        let added = addedIPs.compactMap { bMap[$0] }.map(DeviceSnapshot.init)
        let removed = removedIPs.compactMap { aMap[$0] }.map(DeviceSnapshot.init)

        var changed: [DeviceChange] = []
        for ip in sharedIPs {
            guard let da = aMap[ip], let db = bMap[ip] else { continue }
            let aPorts = Set(da.openPorts)
            let bPorts = Set(db.openPorts)
            let opened = bPorts.subtracting(aPorts).sorted()
            let closed = aPorts.subtracting(bPorts).sorted()
            if !opened.isEmpty || !closed.isEmpty {
                changed.append(DeviceChange(
                    ip: ip,
                    label: db.hostname ?? da.hostname ?? ip,
                    opened: opened, closed: closed))
            }
        }

        // Findings: keyed by (title, deviceIP) so the "same finding" matches
        // even though Finding model IDs are per-session.
        let aFindingKeys = Dictionary(grouping: a.findings, by: FindingSnapshot.key)
        let bFindingKeys = Dictionary(grouping: b.findings, by: FindingSnapshot.key)
        let newFindings = b.findings.filter { aFindingKeys[FindingSnapshot.key($0)] == nil }
            .map(FindingSnapshot.init)
            .sorted { $0.severityRaw > $1.severityRaw }
        let resolved = a.findings.filter { bFindingKeys[FindingSnapshot.key($0)] == nil }
            .map(FindingSnapshot.init)
            .sorted { $0.severityRaw > $1.severityRaw }

        return Diff(added: added, removed: removed, changed: changed,
                    newFindings: newFindings, resolvedFindings: resolved)
    }

    func headline(a: ScanSession, b: ScanSession) -> String {
        var bits: [String] = []
        if added.isEmpty && removed.isEmpty && changed.isEmpty {
            bits.append("Network is unchanged between these scans.")
        } else {
            if !added.isEmpty { bits.append("\(added.count) new device\(added.count == 1 ? "" : "s")") }
            if !removed.isEmpty { bits.append("\(removed.count) gone") }
            if !changed.isEmpty { bits.append("\(changed.count) shifted ports") }
        }
        if !newFindings.isEmpty { bits.append("\(newFindings.count) new finding\(newFindings.count == 1 ? "" : "s")") }
        if !resolvedFindings.isEmpty { bits.append("\(resolvedFindings.count) resolved") }
        return bits.joined(separator: " · ").capitalizedFirst
    }

    private static func ipSort(_ x: String, _ y: String) -> Bool {
        (NetInfo.ipToUInt32(x) ?? 0) < (NetInfo.ipToUInt32(y) ?? 0)
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return first.uppercased() + dropFirst()
    }
}

// MARK: - Snapshots (detached from SwiftData models for safe rendering)

private struct DeviceSnapshot: Identifiable {
    var id: String { ip }
    let ip: String
    let label: String
    let ports: [Int]

    init(_ d: DeviceRecord) {
        self.ip = d.ip
        self.label = d.hostname ?? d.ip
        self.ports = d.openPorts.sorted()
    }
}

private struct DeviceChange: Identifiable {
    var id: String { ip }
    let ip: String
    let label: String
    let opened: [Int]
    let closed: [Int]
}

private struct FindingSnapshot: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let deviceIP: String?
    let severityRaw: Int

    init(_ f: Finding) {
        self.title = f.title
        self.detail = f.detail
        self.deviceIP = f.deviceIP
        self.severityRaw = f.severityRaw
    }

    var severity: Severity { Severity(rawValue: severityRaw) ?? .info }

    static func key(_ f: Finding) -> String {
        "\(f.title)::\(f.deviceIP ?? "-")"
    }
}

// MARK: - Subviews

private struct ScanPickerColumn: View {
    let label: String
    let accent: Color
    let sessions: [ScanSession]
    @Binding var selectedID: UUID?

    private var selected: ScanSession? { sessions.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(accent)
            Menu {
                ForEach(sessions) { s in
                    Button {
                        selectedID = s.id
                        Haptics.tap()
                    } label: {
                        Label(
                            "\(s.date.formatted(date: .abbreviated, time: .shortened)) · \(s.healthScore)",
                            systemImage: selectedID == s.id ? "checkmark" : "")
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selected?.date.formatted(date: .abbreviated, time: .shortened) ?? "—")
                        .font(.system(.footnote, design: .monospaced).weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        if let s = selected {
                            Pill(text: "\(s.healthScore)", color: accent)
                            Text("\(s.deviceCount) dev")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.surfaceHi.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(accent.opacity(0.25), lineWidth: 1))
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DiffScoreColumn: View {
    let score: Int
    let label: String
    var color: Color = Theme.textDim

    var body: some View {
        VStack(spacing: 2) {
            Text("\(score)")
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textFaint)
        }
    }
}

private struct CountTile: View {
    let value: Int
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.caption.weight(.semibold))
                Text(label).font(.system(.caption2, design: .monospaced).weight(.bold)).tracking(1.2)
            }
            .foregroundStyle(color)
            Text("\(value)")
                .font(.system(.title3, design: .monospaced).weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceHi.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(color.opacity(0.22), lineWidth: 1))
        )
    }
}

private struct DeviceDiffRow: View {
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let detail: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.16), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 8)
            if let detail {
                Text(detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
                    .frame(maxWidth: 130, alignment: .trailing)
            }
        }
        .padding(.vertical, 9)
    }
}

private struct ChangedDeviceRow: View {
    let change: DeviceChange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.left.and.right.circle")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.amber)
                    .frame(width: 22, height: 22)
                    .background(Theme.amber.opacity(0.16), in: Circle())
                Text(change.label)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                Text(change.ip)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
            }
            if !change.opened.isEmpty {
                portChip(prefix: "+", ports: change.opened, color: Theme.good)
            }
            if !change.closed.isEmpty {
                portChip(prefix: "−", ports: change.closed, color: Theme.danger)
            }
        }
        .padding(.vertical, 10)
    }

    private func portChip(prefix: String, ports: [Int], color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(prefix)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
                .frame(width: 12, alignment: .leading)
            Text(ports.map(String.init).joined(separator: ", "))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(color)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.leading, 32)
    }
}

private struct FindingDeltaRow: View {
    let finding: FindingSnapshot
    let isNew: Bool

    private var color: Color {
        if !isNew { return Theme.good }
        return [Theme.textDim, Theme.info, Theme.amber, Theme.danger][finding.severityRaw]
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: isNew ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let ip = finding.deviceIP {
                    Text(ip)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
            }
            Spacer(minLength: 6)
            Pill(text: finding.severity.label, color: color)
        }
        .padding(.vertical, 6)
    }
}
