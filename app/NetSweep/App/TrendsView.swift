import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \ScanSession.date, order: .forward) private var sessions: [ScanSession]

    private var recent: [ScanSession] { Array(sessions.suffix(30)) }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if sessions.count < 2 {
                    emptyState
                } else {
                    healthChart
                    deviceChart
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.line.uptrend.xyaxis").font(.largeTitle).foregroundStyle(Theme.textDim)
            Text("Not enough data yet.").font(Theme.monoSm).foregroundStyle(Theme.textDim)
            Text("Run at least two scans to see trends over time.")
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private var healthChart: some View {
        Panel(title: "Health Score Over Time") {
            Chart(recent) { s in
                LineMark(x: .value("Date", s.date), y: .value("Score", s.healthScore))
                    .foregroundStyle(Theme.accent)
                    .interpolationMethod(.monotone)
                AreaMark(x: .value("Date", s.date), y: .value("Score", s.healthScore))
                    .foregroundStyle(.linearGradient(colors: [Theme.accent.opacity(0.3), .clear],
                                                     startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                PointMark(x: .value("Date", s.date), y: .value("Score", s.healthScore))
                    .foregroundStyle(Theme.accent).symbolSize(28)
            }
            .chartYScale(domain: 0...100)
            .chartForegroundStyleScale(range: [Theme.accent])
            .frame(height: 200)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        }
    }

    private var deviceChart: some View {
        Panel(title: "Devices Discovered", accent: Theme.info) {
            Chart(recent) { s in
                BarMark(x: .value("Date", s.date), y: .value("Devices", s.deviceCount))
                    .foregroundStyle(Theme.info)
                if s.newDeviceCount > 0 {
                    BarMark(x: .value("Date", s.date), y: .value("New", s.newDeviceCount))
                        .foregroundStyle(Theme.amber)
                }
            }
            .frame(height: 180)
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
        }
    }

    private var statsCard: some View {
        let scores = recent.map { $0.healthScore }
        let avg = scores.isEmpty ? 0 : scores.reduce(0, +) / scores.count
        let best = scores.max() ?? 0
        let worst = scores.min() ?? 0
        let totalNew = recent.reduce(0) { $0 + $1.newDeviceCount }
        return Panel(title: "Summary", accent: Theme.amber) {
            VStack(spacing: 8) {
                DataRow(key: "scans recorded", value: "\(sessions.count)")
                DataRow(key: "average health", value: "\(avg)", valueColor: Theme.accent)
                DataRow(key: "best / worst", value: "\(best) / \(worst)")
                DataRow(key: "new devices (window)", value: "\(totalNew)", valueColor: Theme.amber)
            }
        }
    }
}
