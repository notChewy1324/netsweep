import SwiftUI
import SwiftData

struct ConnectionView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var path = PathMonitor()
    @StateObject private var tester = ConnectionTester()
    @StateObject private var lookup = PublicEndpointLookup()
    @State private var radio: RadioInfo?
    @State private var savedThisRun = false
    @Query(sort: \ConnectionTest.date, order: .reverse) private var history: [ConnectionTest]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                interfaceCard
                qualityCard
                if !history.isEmpty { historyCard }
                publicCard
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            path.start()
            radio = Cellular.current()
            if lookup.endpoint == nil { lookup.fetch() }
        }
        .onDisappear { path.stop() }
        .onChange(of: tester.isRunning) { _, running in
            // When a test finishes, persist the result once.
            if running { savedThisRun = false }
            else if !savedThisRun, tester.quality.latencyMs != nil {
                saveResult()
                savedThisRun = true
            }
        }
    }

    private func saveResult() {
        let q = tester.quality
        let test = ConnectionTest(latencyMs: q.latencyMs, jitterMs: q.jitterMs,
                                  throughputMbps: q.throughputMbps,
                                  network: path.interfaceType)
        context.insert(test)
        try? context.save()
    }

    private var historyCard: some View {
        Panel(title: "History", accent: Theme.info) {
            VStack(spacing: 0) {
                ForEach(Array(history.prefix(8))) { t in
                    HStack {
                        Text(t.date.formatted(.dateTime.month().day().hour().minute()))
                            .font(.footnote).foregroundStyle(Theme.textDim)
                        Spacer()
                        Text(t.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—")
                            .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textPrimary)
                        if let tp = t.throughputMbps {
                            Text(String(format: "%.0f Mbps", tp))
                                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.accent)
                                .frame(width: 80, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 7)
                    if t.id != history.prefix(8).last?.id { Divider().overlay(Theme.stroke) }
                }
            }
        }
    }

    // MARK: Interface + radio

    private var interfaceCard: some View {
        Panel(title: "Active Interface", accent: Theme.info) {
            VStack(spacing: 8) {
                HStack {
                    Pill(text: path.status, color: path.status == "ONLINE" ? Theme.accent : Theme.danger)
                    Pill(text: path.interfaceType, color: Theme.info)
                    if path.isExpensive { Pill(text: "Metered", color: Theme.amber) }
                    if path.isConstrained { Pill(text: "Low Data", color: Theme.amber) }
                    Spacer()
                }
                if path.interfaceType == "CELLULAR", let radio {
                    Divider().overlay(Theme.stroke)
                    DataRow(key: "radio", value: radio.detail, valueColor: Theme.accent)
                    if let carrier = radio.carrier {
                        DataRow(key: "carrier", value: carrier)
                    }
                    Text("iOS doesn't expose signal strength, towers, or bands to apps those are restricted APIs.")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if path.interfaceType == "CELLULAR" {
                    DataRow(key: "radio", value: "unavailable", valueColor: Theme.textDim)
                }
                HStack(spacing: 10) {
                    Pill(text: path.supportsIPv4 ? "IPv4 ✓" : "IPv4 ✗",
                         color: path.supportsIPv4 ? Theme.accent : Theme.textDim)
                    Pill(text: path.supportsIPv6 ? "IPv6 ✓" : "IPv6 ✗",
                         color: path.supportsIPv6 ? Theme.accent : Theme.textDim)
                    Spacer()
                }
            }
        }
    }

    // MARK: Connection quality

    private var qualityCard: some View {
        Panel(title: "Connection Quality") {
            VStack(spacing: 12) {
                let q = tester.quality
                let color = [Theme.danger, Theme.amber, Theme.accent][q.gradeColorIndex]
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(q.grade)
                            .font(.system(.title2, design: .monospaced).weight(.heavy))
                            .foregroundStyle(color)
                        Text("on \(path.interfaceType.lowercased())")
                            .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    Sparkline(values: q.samples, color: color)
                        .frame(width: 110, height: 40)
                }
                Divider().overlay(Theme.stroke)
                DataRow(key: "latency (median)", value: q.latencyMs.map { String(format: "%.0f ms", $0) } ?? "—",
                        valueColor: color)
                DataRow(key: "jitter", value: q.jitterMs.map { String(format: "%.1f ms", $0) } ?? "—")
                DataRow(key: "throughput", value: q.throughputMbps.map { String(format: "%.1f Mbps", $0) } ?? "—",
                        valueColor: Theme.accent)
                if tester.isRunning {
                    HStack { ProgressView().controlSize(.small).tint(Theme.accent)
                        Text(tester.phase).font(Theme.monoSm).foregroundStyle(Theme.textDim); Spacer() }
                } else {
                    ActionButton(title: "Run Test", systemImage: "speedometer") { tester.run() }
                }
            }
        }
    }

    // MARK: Public endpoint

    private var publicCard: some View {
        Panel(title: "What The Internet Sees", accent: Theme.amber) {
            VStack(spacing: 8) {
                if lookup.isLoading {
                    HStack { ProgressView().controlSize(.small).tint(Theme.amber)
                        Text("Looking up…").font(Theme.monoSm).foregroundStyle(Theme.textDim); Spacer() }
                } else if let e = lookup.endpoint {
                    DataRow(key: "public IP", value: e.ip ?? "—", valueColor: Theme.accent)
                    DataRow(key: "ISP / carrier", value: e.org ?? "—", valueColor: Theme.textPrimary)
                    if let asn = e.asn { DataRow(key: "ASN", value: asn) }
                    if !e.locationLine.isEmpty { DataRow(key: "location", value: e.locationLine) }
                    Text("This is your network's public identity. On cellular it shows your carrier's network.")
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if let err = lookup.error {
                    Text(err).font(Theme.monoSm).foregroundStyle(Theme.danger)
                }
                ActionButton(title: "Refresh", systemImage: "arrow.clockwise", color: Theme.amber) {
                    lookup.fetch()
                }
            }
        }
    }
}

// MARK: - Sparkline

struct Sparkline: View {
    let values: [Double]
    var color: Color = Theme.accent
    var body: some View {
        GeometryReader { geo in
            if values.count > 1, let mn = values.min(), let mx = values.max(), mx > mn {
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(values.count - 1)
                        let y = geo.size.height * (1 - CGFloat((v - mn) / (mx - mn)))
                        i == 0 ? p.move(to: .init(x: x, y: y)) : p.addLine(to: .init(x: x, y: y))
                    }
                }
                .stroke(color, style: .init(lineWidth: 2, lineCap: .round, lineJoin: .round))
            } else {
                Rectangle().fill(Theme.surfaceHi)
                    .frame(height: 2).frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}
