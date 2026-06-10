import SwiftUI
import SwiftData

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]
    @State private var confirmingClear = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if sessions.isEmpty {
                        emptyState
                    } else {
                        ForEach(sessions) { s in
                            NavigationLink {
                                SessionDetailView(session: s)
                                    .zoomDestination("session-\(s.id)")
                            } label: {
                                SessionCard(session: s)
                            }
                            .zoomSource("session-\(s.id)")
                        }
                    }
                }
                .padding(16)
                .readableWidth()
            }
            .background(ObservatoryCanvas())
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        TrendsView()
                            .zoomDestination("trends")
                    } label: {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .tint(Theme.accent)
                    .accessibilityLabel("Trends")
                    .zoomSource("trends")
                }
                if !sessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            Haptics.tap()
                            confirmingClear = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .tint(Theme.danger)
                        .accessibilityLabel("Delete all history")
                    }
                }
            }
            .confirmationDialog("Delete all scan history?",
                                isPresented: $confirmingClear,
                                titleVisibility: .visible) {
                Button("Delete \(sessions.count) Scan\(sessions.count == 1 ? "" : "s")", role: .destructive) {
                    clearAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every saved scan from this device.")
            }
        }
        .zoomNavigationRoot()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").font(.largeTitle).foregroundStyle(Theme.textDim)
            Text("No scans yet.").font(Theme.monoSm).foregroundStyle(Theme.textDim)
            Text("Run a scan from the Home tab to start building history.")
                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private func clearAll() {
        for s in sessions { context.delete(s) }
        try? context.save()
        Haptics.success()
    }
}

struct SessionCard: View {
    let session: ScanSession
    private var color: Color {
        SecurityAnalysis.color(for: session.healthScore)
    }
    var body: some View {
        Panel {
            HStack(spacing: 14) {
                VStack {
                    Text("\(session.healthScore)")
                        .font(.system(.title, design: .monospaced).weight(.heavy))
                        .foregroundStyle(color)
                    Text(SecurityAnalysis.grade(session.healthScore).0)
                        .font(.system(.caption2, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.textDim)
                }
                .frame(width: 70)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                    Text(session.subnet).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                    HStack(spacing: 6) {
                        Pill(text: "\(session.deviceCount) devices", color: Theme.info)
                        if session.newDeviceCount > 0 {
                            Pill(text: "+\(session.newDeviceCount) new", color: Theme.amber)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textDim)
            }
        }
    }
}

struct SessionDetailView: View {
    let session: ScanSession
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                let findings = session.findings.sorted { $0.severity > $1.severity }
                if !findings.isEmpty {
                    Panel(title: "Findings · \(findings.count)") {
                        VStack(spacing: 0) {
                            ForEach(findings) { f in
                                FindingRow(finding: f)
                                if f.id != findings.last?.id { Divider().overlay(Theme.stroke) }
                            }
                        }
                    }
                }
                let devices = session.devices.sorted {
                    (NetInfo.ipToUInt32($0.ip) ?? 0) < (NetInfo.ipToUInt32($1.ip) ?? 0)
                }
                Panel(title: "Devices · \(devices.count)", accent: Theme.info) {
                    VStack(spacing: 0) {
                        ForEach(devices) { d in
                            HStack {
                                if d.isNew { Image(systemName: "sparkles").foregroundStyle(Theme.amber) }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.hostname ?? d.ip)
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .foregroundStyle(Theme.accent)
                                    if let v = d.vendorGuess {
                                        Text(v).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.info)
                                    }
                                }
                                Spacer()
                                Text(d.openPorts.map(String.init).joined(separator: ","))
                                    .font(.system(.caption, design: .monospaced)).foregroundStyle(Theme.textDim)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 8)
                            if d.id != devices.last?.id { Divider().overlay(Theme.stroke) }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle(session.date.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let pdf = ReportPDF.generate(for: session) {
                        ShareLink(item: pdf) { Label("PDF Report", systemImage: "doc.richtext") }
                    }
                    if let json = ScanExport.json(for: session) {
                        ShareLink(item: json) { Label("JSON Data", systemImage: "curlybraces") }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .tint(Theme.accent)
                .accessibilityLabel("Share report")
            }
        }
    }
}
