import SwiftUI
import SwiftData

struct NetworkMapView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]
    @StateObject private var path = PathMonitor()
    @StateObject private var auditor = WiFiAuditor()

    private var latest: ScanSession? { sessions.first }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CellularNote(feature: "The network map")
                if let session = latest {
                    mapCard(session)
                    auditCard
                } else {
                    emptyState
                }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Network Map")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            path.start()
            Task { await auditor.run(path: path, lastSession: latest) }
        }
        .onDisappear { path.stop() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.largeTitle).foregroundStyle(Theme.textDim)
            Text("No scan data yet.").font(Theme.monoSm).foregroundStyle(Theme.textDim)
            Text("Run a scan from Home to map your network.")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
        }.frame(maxWidth: .infinity).padding(.vertical, 60)
    }

    private func mapCard(_ session: ScanSession) -> some View {
        let devices = session.devices.sorted {
            (NetInfo.ipToUInt32($0.ip) ?? 0) < (NetInfo.ipToUInt32($1.ip) ?? 0)
        }
        return Panel(title: "Topology · \(devices.count) devices") {
            RadialMap(devices: devices, subnet: session.subnet)
                .frame(height: devices.count > 20 ? 460 : 360)
        }
    }

    private var auditCard: some View {
        Panel(title: "Wi-Fi Security Audit",
              accent: auditScoreColor) {
            VStack(spacing: 10) {
                HStack {
                    Text("\(auditor.score)")
                        .font(.system(size: 34, weight: .heavy, design: .monospaced))
                        .foregroundStyle(auditScoreColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(auditVerdict).font(.system(.subheadline, design: .monospaced).weight(.bold))
                            .foregroundStyle(auditScoreColor)
                        Text("network posture").font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    if auditor.isRunning { ProgressView().controlSize(.small).tint(Theme.accent) }
                }
                Divider().overlay(Theme.stroke)
                ForEach(auditor.checks) { check in
                    HStack(alignment: .top, spacing: 10) {
                        Pill(text: check.status.label, color: statusColor(check.status))
                            .frame(width: 64, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(check.name).font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                            Text(check.detail).font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.textDim)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(check.name): \(check.status.label). \(check.detail)")
                }
            }
        }
    }

    private var auditScoreColor: Color {
        switch auditor.score { case 85...100: return Theme.accent; case 60..<85: return Theme.amber; default: return Theme.danger }
    }
    private var auditVerdict: String {
        switch auditor.score { case 85...100: return "SOLID"; case 60..<85: return "REVIEW"; default: return "WEAK" }
    }
    private func statusColor(_ s: AuditCheck.Status) -> Color {
        switch s { case .pass: return Theme.accent; case .warn: return Theme.amber
                   case .fail: return Theme.danger; case .info: return Theme.info }
    }
}

// MARK: - Radial topology map

struct RadialMap: View {
    let devices: [DeviceRecord]
    let subnet: String
    @State private var pulse = false
    @State private var flow: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = min(geo.size.width, geo.size.height) / 2 - 44
            ZStack {
                // Animated flowing links from gateway to each device.
                // The trim animation is costly, so only animate when sparse.
                let animateFlow = devices.count <= 20
                ForEach(Array(devices.enumerated()), id: \.element.id) { idx, _ in
                    let p = nodePoint(idx, count: devices.count, center: center, radius: radius)
                    Path { path in path.move(to: center); path.addLine(to: p) }
                        .stroke(Theme.stroke, lineWidth: 1)
                    if animateFlow {
                        Path { path in path.move(to: center); path.addLine(to: p) }
                            .trim(from: flow, to: min(flow + 0.18, 1))
                            .stroke(Theme.accent.opacity(0.6), lineWidth: 1.5)
                    }
                }
                // Gateway hub (gently pulsing)
                NodeBadge(label: "GATEWAY", sub: subnet, color: Theme.accent, isHub: true)
                    .scaleEffect(pulse ? 1.05 : 1.0)
                    .position(center)
                // Device nodes (tappable → profile)
                let compact = devices.count > 15
                ForEach(Array(devices.enumerated()), id: \.element.id) { idx, device in
                    let p = nodePoint(idx, count: devices.count, center: center, radius: radius)
                    NavigationLink {
                        DeviceProfileView(ip: device.ip, hostname: device.hostname,
                                          vendorGuess: device.vendorGuess)
                    } label: {
                        NodeBadge(label: shortLabel(device),
                                  sub: "\(device.openPorts.count)p",
                                  color: device.isNew ? Theme.amber : Theme.info,
                                  isHub: false, compact: compact)
                            .scaleEffect(pulse ? 1.02 : 0.99)
                    }
                    .position(p)
                }
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { pulse = true }
                withAnimation(.linear(duration: 2.5).repeatForever(autoreverses: false)) { flow = 1 }
            }
        }
    }

    private func nodePoint(_ idx: Int, count: Int, center: CGPoint, radius: CGFloat) -> CGPoint {
        guard count > 0 else { return center }
        // Distribute across concentric rings (~10 per ring) so dense networks
        // don't crowd a single circle. Inner rings are tighter.
        let perRing = 10
        let ring = idx / perRing
        let totalRings = (count - 1) / perRing + 1
        let idxInRing = idx % perRing
        let countInRing = min(perRing, count - ring * perRing)
        // Ring radius scales from inner to outer within available space.
        let ringRadius = radius * (CGFloat(ring + 1) / CGFloat(totalRings))
        // Offset alternate rings so nodes don't line up radially.
        let angleOffset = (ring % 2 == 0) ? 0.0 : .pi / Double(max(countInRing, 1))
        let angle = (Double(idxInRing) / Double(max(countInRing, 1))) * 2 * .pi - .pi / 2 + angleOffset
        return CGPoint(x: center.x + ringRadius * CGFloat(cos(angle)),
                       y: center.y + ringRadius * CGFloat(sin(angle)))
    }

    private func shortLabel(_ d: DeviceRecord) -> String {
        if let h = d.hostname, let first = h.split(separator: ".").first { return String(first.prefix(10)) }
        return d.ip.split(separator: ".").last.map(String.init) ?? d.ip
    }
}

struct NodeBadge: View {
    let label: String, sub: String, color: Color, isHub: Bool
    var compact: Bool = false
    private var dotSize: CGFloat { isHub ? 56 : (compact ? 26 : 40) }
    private var iconSize: CGFloat { isHub ? 22 : (compact ? 11 : 15) }
    var body: some View {
        VStack(spacing: 2) {
            Circle()
                .fill(color.opacity(0.18))
                .frame(width: dotSize, height: dotSize)
                .overlay(Circle().stroke(color, lineWidth: isHub ? 2 : 1.5))
                .glow(color, radius: isHub ? 10 : (compact ? 3 : 5))
                .overlay(
                    Image(systemName: isHub ? "wifi.router" : "desktopcomputer")
                        .font(.system(size: iconSize)).foregroundStyle(color)
                )
            if !compact || isHub {
                Text(label).font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary).lineLimit(1)
                Text(sub).font(.system(size: 8, design: .monospaced)).foregroundStyle(Theme.textDim)
            }
        }
    }
}
