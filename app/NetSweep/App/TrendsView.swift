import SwiftUI
import SwiftData
import Charts

// MARK: - Trends
// Interactive trend charts over the last 30 scans. Scrub a chart to inspect a
// specific session; the selection drives a detail card and a "what changed"
// breakdown. The score-breakdown panel explains *why* the latest score is what
// it is by grouping its findings by severity.

struct TrendsView: View {
    @Query(sort: \ScanSession.date, order: .forward) private var sessions: [ScanSession]

    @State private var selectedDate: Date?
    @State private var selectedChart: ChartKind = .health

    private enum ChartKind { case health, devices }

    private var recent: [ScanSession] { Array(sessions.suffix(30)) }
    private var latest: ScanSession? { sessions.last }

    // The session closest to the user's chart-scrub point.
    private var selectedSession: ScanSession? {
        guard let selectedDate, !recent.isEmpty else { return nil }
        return recent.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    // The scan right before the selection — used for delta comparisons.
    private var priorToSelected: ScanSession? {
        guard let sel = selectedSession,
              let idx = recent.firstIndex(where: { $0.id == sel.id }),
              idx > 0 else { return nil }
        return recent[idx - 1]
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if sessions.count < 2 {
                    emptyState
                } else {
                    healthChart
                    deviceChart
                    if let sel = selectedSession {
                        selectionCard(for: sel)
                    } else {
                        hintCard
                    }
                    if let s = latest { breakdownCard(for: s) }
                    statsCard
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Trends")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Empty

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.largeTitle).foregroundStyle(Theme.textDim)
            Text("Not enough data yet.")
                .font(Theme.monoSm).foregroundStyle(Theme.textDim)
            Text("Run at least two scans to see trends over time.")
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    // MARK: Health chart (scrubbable)

    private var healthChart: some View {
        let scores = recent.map(\.healthScore)
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        return Panel(title: "Health Score · Tap to Inspect") {
            Chart {
                ForEach(recent) { s in
                    LineMark(
                        x: .value("Date", s.date),
                        y: .value("Score", s.healthScore))
                        .foregroundStyle(Theme.accent)
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    AreaMark(
                        x: .value("Date", s.date),
                        y: .value("Score", s.healthScore))
                        .foregroundStyle(.linearGradient(
                            colors: [Theme.accent.opacity(0.3), .clear],
                            startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                }
                RuleMark(y: .value("Average", avg))
                    .foregroundStyle(Theme.textFaint.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .annotation(position: .topTrailing, alignment: .trailing) {
                        Text("avg \(avg)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(Theme.textFaint)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Theme.surface.opacity(0.8), in: Capsule())
                    }

                if let sel = selectedSession, selectedChart == .health {
                    RuleMark(x: .value("Selected", sel.date))
                        .foregroundStyle(Theme.accent.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                    PointMark(
                        x: .value("Date", sel.date),
                        y: .value("Score", sel.healthScore))
                        .foregroundStyle(Theme.accent)
                        .symbolSize(120)
                        .annotation(position: .top, alignment: .center, spacing: 6) {
                            Text("\(sel.healthScore)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.accent)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().stroke(Theme.accent.opacity(0.4), lineWidth: 1))
                        }
                }
            }
            .chartYScale(domain: 0...100)
            .chartXSelection(value: Binding(
                get: { selectedChart == .health ? selectedDate : nil },
                set: { newValue in
                    selectedChart = .health
                    selectedDate = newValue
                    if newValue != nil { Haptics.tap() }
                }))
            .frame(height: 200)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        }
    }

    // MARK: Devices chart (scrubbable)

    private var deviceChart: some View {
        Panel(title: "Devices Discovered", accent: Theme.info) {
            Chart {
                ForEach(recent) { s in
                    BarMark(
                        x: .value("Date", s.date),
                        y: .value("Devices", s.deviceCount))
                        .foregroundStyle(Theme.info)
                        .cornerRadius(3)
                    if s.newDeviceCount > 0 {
                        BarMark(
                            x: .value("Date", s.date),
                            y: .value("New", s.newDeviceCount))
                            .foregroundStyle(Theme.amber)
                            .cornerRadius(3)
                    }
                }
                if let sel = selectedSession, selectedChart == .devices {
                    RuleMark(x: .value("Selected", sel.date))
                        .foregroundStyle(Theme.info.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, alignment: .center, spacing: 6) {
                            Text("\(sel.deviceCount)")
                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.info)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().stroke(Theme.info.opacity(0.4), lineWidth: 1))
                        }
                }
            }
            .frame(height: 180)
            .chartXSelection(value: Binding(
                get: { selectedChart == .devices ? selectedDate : nil },
                set: { newValue in
                    selectedChart = .devices
                    selectedDate = newValue
                    if newValue != nil { Haptics.tap() }
                }))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        }
    }

    // MARK: Hint card (when no selection)

    private var hintCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.tap")
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
            Text("Tap or drag a chart to inspect a specific scan.")
                .font(.footnote)
                .foregroundStyle(Theme.textDim)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.accent.opacity(0.18), lineWidth: 1))
        )
    }

    // MARK: Selection detail card (with "what changed" deltas)

    private func selectionCard(for sel: ScanSession) -> some View {
        let scoreDelta: Int? = priorToSelected.map { sel.healthScore - $0.healthScore }
        let deviceDelta: Int? = priorToSelected.map { sel.deviceCount - $0.deviceCount }
        let (gradeLabel, _) = SecurityAnalysis.grade(sel.healthScore)
        let gradeColor = SecurityAnalysis.color(for: sel.healthScore)
        return Panel(title: "Inspecting Scan", accent: gradeColor) {
            VStack(spacing: 12) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(sel.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        HStack(spacing: 6) {
                            Text(sel.subnet)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                            Pill(text: gradeLabel, color: gradeColor)
                        }
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            selectedDate = nil
                        }
                        Haptics.tap()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textDim)
                            .frame(width: 26, height: 26)
                            .background(Theme.surfaceHi, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Divider().overlay(Theme.stroke)
                HStack(spacing: 10) {
                    DeltaMetric(
                        title: "SCORE",
                        value: "\(sel.healthScore)",
                        delta: scoreDelta,
                        positiveIsGood: true,
                        color: gradeColor)
                    DeltaMetric(
                        title: "DEVICES",
                        value: "\(sel.deviceCount)",
                        delta: deviceDelta,
                        positiveIsGood: false,
                        color: Theme.info)
                    DeltaMetric(
                        title: "NEW",
                        value: "\(sel.newDeviceCount)",
                        delta: nil,
                        positiveIsGood: false,
                        color: sel.newDeviceCount > 0 ? Theme.amber : Theme.textDim)
                }
                if !sel.findings.isEmpty {
                    Divider().overlay(Theme.stroke)
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.shield")
                            .font(.caption2)
                            .foregroundStyle(Theme.textDim)
                        Text("\(sel.findings.count) finding\(sel.findings.count == 1 ? "" : "s") on this scan")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: Score breakdown — "why is my score X?"

    private func breakdownCard(for s: ScanSession) -> some View {
        let bySeverity = Dictionary(grouping: s.findings, by: { $0.severity })
        let high = bySeverity[.high]?.count ?? 0
        let medium = bySeverity[.medium]?.count ?? 0
        let low = bySeverity[.low]?.count ?? 0
        let info = bySeverity[.info]?.count ?? 0
        let highCost = high * 25
        let medCost = medium * 12
        let lowCost = low * 5
        let totalCost = highCost + medCost + lowCost
        return Panel(title: "Score Breakdown · Latest", accent: Theme.amber) {
            VStack(spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(s.healthScore)")
                        .font(.system(size: 38, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .layoutPriority(1)
                    Text("/ 100")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    Spacer()
                    if totalCost > 0 {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("−\(totalCost)")
                                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.danger)
                            Text("FROM FINDINGS")
                                .font(.system(.caption2, design: .monospaced))
                                .tracking(1)
                                .foregroundStyle(Theme.textFaint)
                        }
                    }
                }
                if totalCost == 0 {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.good)
                        Text("No deductions — no risky services detected.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                        Spacer()
                    }
                } else {
                    VStack(spacing: 6) {
                        BreakdownBar(label: "HIGH", count: high, deduction: highCost,
                                     color: Theme.danger, weight: 25)
                        BreakdownBar(label: "MEDIUM", count: medium, deduction: medCost,
                                     color: Theme.amber, weight: 12)
                        BreakdownBar(label: "LOW", count: low, deduction: lowCost,
                                     color: Theme.info, weight: 5)
                        if info > 0 {
                            BreakdownBar(label: "INFO", count: info, deduction: 0,
                                         color: Theme.textDim, weight: 0)
                        }
                    }
                }
            }
        }
    }

    // MARK: Summary stats

    private var statsCard: some View {
        let scores = recent.map(\.healthScore)
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        let best = scores.max() ?? 0
        let worst = scores.min() ?? 0
        let totalNew = recent.reduce(0) { $0 + $1.newDeviceCount }
        return Panel(title: "Summary", accent: Theme.purple) {
            VStack(spacing: 8) {
                DataRow(key: "scans recorded", value: "\(sessions.count)")
                DataRow(key: "average health", value: "\(avg)", valueColor: Theme.accent)
                DataRow(key: "best / worst", value: "\(best) / \(worst)")
                DataRow(key: "new devices (window)", value: "\(totalNew)", valueColor: Theme.amber)
            }
        }
    }
}

// MARK: - Delta metric tile (used in the selection card)

private struct DeltaMetric: View {
    let title: String
    let value: String
    let delta: Int?
    let positiveIsGood: Bool
    let color: Color

    private var deltaColor: Color {
        guard let delta, delta != 0 else { return Theme.textDim }
        let positive = delta > 0
        let good = positive == positiveIsGood
        return good ? Theme.good : Theme.danger
    }

    private var deltaIcon: String {
        guard let delta, delta != 0 else { return "minus" }
        return delta > 0 ? "arrow.up.right" : "arrow.down.right"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.textFaint)
            Text(value)
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let delta {
                HStack(spacing: 3) {
                    Image(systemName: deltaIcon).font(.caption2.weight(.bold))
                    Text("\(abs(delta))")
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                }
                .foregroundStyle(deltaColor)
            } else {
                Text(" ").font(.caption2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surfaceHi.opacity(0.6))
        )
    }
}

// MARK: - Breakdown bar (severity row in the score breakdown)

private struct BreakdownBar: View {
    let label: String
    let count: Int
    let deduction: Int
    let color: Color
    let weight: Int

    private var faded: Bool { count == 0 }

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .tracking(1.2)
                .foregroundStyle(faded ? Theme.textFaint : color)
                .frame(width: 60, alignment: .leading)
            GeometryReader { geo in
                let max: Double = 75 // visual saturation — 3 high-sev findings fills the bar
                let fill = min(1, Double(deduction) / max)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Theme.surfaceHi.opacity(0.5))
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(faded ? 0.18 : 0.85))
                        .frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 8)
            Text("\(count)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(faded ? Theme.textFaint : Theme.textPrimary)
                .frame(width: 22, alignment: .trailing)
            Text(deduction > 0 ? "−\(deduction)" : "—")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(faded ? Theme.textFaint : Theme.danger)
                .frame(width: 38, alignment: .trailing)
        }
        .opacity(faded ? 0.55 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) severity, \(count) findings, deduction \(deduction) points, weight \(weight) per finding")
    }
}
