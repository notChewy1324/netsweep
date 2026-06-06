import SwiftUI
import SwiftData

// MARK: - Canvas Home — the single immersive surface (replaces tabs)
// A pan/zoom spatial map of your network. Your device is centered; discovered
// devices float around it. Tap a node for a detail sheet; tap the orb for the
// radial tool menu; scan to watch devices materialize into the space.

struct CanvasHomeView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.modelContext) private var context
    @StateObject private var service = NetworkScanService()
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]

    @State private var canvas = CanvasState()
    @State private var nodeOffsets: [String: CGSize] = [:]   // user-dragged positions
    @State private var selectedIP: String?
    @State private var showTools = false
    @State private var showGateway = false

    private var latest: ScanSession? { service.lastSession ?? sessions.first }

    // Living health: the scene's accent shifts with the network's health score.
    private var healthMood: Color {
        guard let s = latest else { return Theme.accent }
        switch s.healthScore {
        case 85...100: return Theme.accent      // calm cyan — all well
        case 60..<85:  return Theme.amber       // warm — worth a look
        default:        return Theme.danger      // alert
        }
    }

    var body: some View {
        ZStack {
            ObservatoryCanvas()

            // Living health: a faint mood wash that shifts with network health.
            RadialGradient(colors: [healthMood.opacity(0.10), .clear],
                           center: .center, startRadius: 0, endRadius: 360)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 1.2), value: healthMood)
                .allowsHitTesting(false)

            // Expanding grid: a large tiled grid that moves with the pan/zoom so
            // the space visibly extends as you drag nodes or pan around.
            ExpandingGrid()
                .scaleEffect(canvas.effectiveZoom)
                .offset(canvas.effectivePan)
                .allowsHitTesting(false)

            // Layer 1: UIKit-backed pan/zoom surface BEHIND the nodes. Real
            // UIPan + UIPinch recognizers run simultaneously and handle multitouch
            // properly. Sits behind nodes, so node taps/drags still work.
            GeometryReader { geo in
                CanvasGestureSurface(
                    onPanChanged: { delta in canvas.applyPan(delta) },
                    onPanEnded: { },
                    onZoomChanged: { delta, anchor in
                        canvas.applyZoom(delta, anchor: anchor, viewSize: geo.size)
                    },
                    onZoomEnded: { }
                )
            }

            // Layer 2: the transformed spatial content (lines + nodes). Nodes carry
            // their own high-priority drag so they win over the background pan.
            spatialLayer
                .scaleEffect(canvas.effectiveZoom)
                .offset(canvas.effectivePan)

            topBar
            emptyHint
            VStack {
                Spacer().frame(height: 100)
                CellularNote(feature: "Network mapping").padding(.horizontal, 20)
                Spacer()
            }
            bottomControls

            if showTools { radialToolMenu }
        }
        .sheet(item: Binding(get: { selectedIP.map { IPWrap(ip: $0) } },
                             set: { selectedIP = $0?.ip })) { wrap in
            deviceSheet(wrap.ip)
        }
        .sheet(isPresented: $showGateway) {
            NavigationStack { GatewayInfoView() }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: service.isScanning) { wasScanning, nowScanning in
            // Satisfying "settle" when a scan finishes and devices lock in.
            if wasScanning && !nowScanning {
                Haptics.success()
                rebuildNodes()
            }
        }
        .onChange(of: latest?.id) { _, _ in rebuildNodes() }
        .onAppear { rebuildNodes() }
    }

    // MARK: Spatial layer (center + device nodes)

    private var spatialLayer: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            ZStack {
                linksLayer(center: center).allowsHitTesting(false)
                NodeView(node: centerNode, selected: showGateway)
                    .frame(width: 110, height: 110)
                    .contentShape(Rectangle())
                    .position(center)
                    .onTapGesture { Haptics.tap(); showGateway = true }
                nodesLayer(center: center)
            }
        }
    }

    private func linksLayer(center: CGPoint) -> some View {
        ForEach(deviceNodes) { node in
            let end = CGPoint(x: center.x + node.offset.width, y: center.y + node.offset.height)
            Path { p in
                p.move(to: center)
                p.addLine(to: end)
            }
            .stroke(Theme.accent.opacity(0.12), lineWidth: 1)
        }
    }

    private func nodesLayer(center: CGPoint) -> some View {
        ForEach(deviceNodes) { node in
            DraggableNode(
                node: node,
                center: center,
                zoom: canvas.effectiveZoom,
                selected: selectedIP == node.id,
                onMoved: { newOffset in
                    nodeOffsets[node.id] = newOffset
                    // Update just this node in the cache (cheap), not a full rebuild.
                    if let i = cachedNodes.firstIndex(where: { $0.id == node.id }) {
                        cachedNodes[i].offset = newOffset
                    }
                },
                onTap: { Haptics.tap(); selectedIP = node.id }
            )
            .transition(.scale(scale: 0.1).combined(with: .opacity))
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: latest?.deviceCount)
    }

    // MARK: Nodes

    private var centerNode: SpatialNode {
        SpatialNode(id: "__self__", offset: .zero, isCenter: true, isNew: false,
                    label: AppInfo.displayName, sub: "", openPorts: 0,
                    icon: "scope", accent: healthMood)
    }

    // Cached node list — rebuilt only when scan data or dragged positions
    // change, NOT on every pan/zoom frame (pan/zoom are pure transforms).
    @State private var cachedNodes: [SpatialNode] = []
    private var deviceNodes: [SpatialNode] { cachedNodes }

    private func rebuildNodes() {
        guard let s = latest else { cachedNodes = []; return }
        let devices = s.devices.sorted { (NetInfo.ipToUInt32($0.ip) ?? 0) < (NetInfo.ipToUInt32($1.ip) ?? 0) }
        cachedNodes = devices.enumerated().map { idx, d in
            SpatialNode(
                id: d.ip,
                offset: nodeOffsets[d.ip] ?? radialOffset(idx, total: devices.count),
                isCenter: false, isNew: d.isNew,
                label: d.hostname ?? d.ip,
                sub: d.ip, openPorts: d.openPorts.count,
                icon: icon(for: d), accent: d.isNew ? Theme.amber : Theme.info)
        }
    }

    private func radialOffset(_ i: Int, total: Int) -> CGSize {
        guard total > 0 else { return .zero }
        let golden = 2.399963
        let angle = Double(i) * golden
        let ring = 110.0 + Double((i * 37) % 100)
        return CGSize(width: CGFloat(ring * cos(angle)), height: CGFloat(ring * sin(angle)))
    }

    private func icon(for d: DeviceRecord) -> String {
        let v = (d.vendorGuess ?? "").lowercased()
        if v.contains("apple") { return "applelogo" }
        if v.contains("pi") { return "cpu" }
        if v.contains("router") || v.contains("netgear") || v.contains("tp-link") { return "wifi.router" }
        if v.contains("printer") { return "printer" }
        if d.openPorts.contains(22) { return "terminal" }
        return "desktopcomputer"
    }

    // MARK: Overlays

    private var topBar: some View {
        VStack {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    AnimatedLogoText(text: AppInfo.displayName)
                    if let s = latest {
                        Text("\(s.deviceCount) devices · health \(s.healthScore)")
                            .font(.caption).foregroundStyle(Theme.textDim)
                    } else {
                        Text("Not scanned yet").font(.caption).foregroundStyle(Theme.textDim)
                    }
                }
                Spacer()
                Button { canvas.reset(); Haptics.tap() } label: {
                    Image(systemName: "scope").font(.title3).foregroundStyle(Theme.accent)
                        .padding(10).background(Theme.surface, in: Circle())
                }
            }
            .padding(.horizontal, 20).padding(.top, 8)
            Spacer()
        }
    }

    // A gentle prompt over the empty canvas inviting the first scan.
    @ViewBuilder
    private var emptyHint: some View {
        if latest == nil && !service.isScanning {
            VStack(spacing: 6) {
                Text("Your network, visualized")
                    .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text("Tap Scan to map what's connected")
                    .font(.caption).foregroundStyle(Theme.textDim)
            }
            .offset(y: 70)
            .transition(.opacity)
        } else if latest != nil && !service.isScanning {
            // Subtle one-time-feeling gesture hint at the very top.
            VStack {
                Spacer().frame(height: 4)
                Text("Drag to move · pinch to zoom · tap a node")
                    .font(.caption2).foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.7), in: Capsule())
                    .padding(.top, 64)
                Spacer()
            }
        }
    }

    private var bottomControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                // Tools orb — icon rotates smoothly between states.
                Button { withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { showTools.toggle() }; Haptics.tap() } label: {
                    Image(systemName: showTools ? "xmark" : "square.grid.2x2")
                        .font(.title2).foregroundStyle(Theme.textPrimary)
                        .rotationEffect(.degrees(showTools ? 90 : 0))
                        .frame(width: 56, height: 56)
                        .background(Theme.surface, in: Circle())
                        .overlay(Circle().stroke(Theme.accent.opacity(0.3), lineWidth: 1))
                }
                .pressable()
                // Scan
                Button {
                    Haptics.medium()
                    Task { await service.runFullScan(context: context,
                                                     intensity: settings.scanIntensity,
                                                     notify: settings.notifyNewDevices) }
                } label: {
                    HStack(spacing: 8) {
                        if service.isScanning {
                            ProgressView().controlSize(.small).tint(Theme.canvasTop)
                            Text("Scanning").font(.body.weight(.semibold))
                        } else {
                            Image(systemName: "dot.radiowaves.left.and.right")
                            Text("Scan").font(.body.weight(.semibold))
                        }
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 17)
                    .background(Theme.accent, in: .rect(cornerRadius: 18, style: .continuous))
                    .foregroundStyle(Theme.canvasTop)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 14, y: 4)
                }
                .disabled(service.isScanning)
                .pressable()
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    // MARK: Radial tool menu

    private var radialToolMenu: some View {
        let tools: [(String, String, AnyView)] = [
            ("Network Map", "point.3.connected.trianglepath.dotted", AnyView(NetworkMapView())),
            ("Port Scanner", "target", AnyView(PortScannerView())),
            ("Bonjour", "antenna.radiowaves.left.and.right", AnyView(BonjourView())),
            ("Vuln Insights", "ladybug", AnyView(VulnInsightsView())),
            ("Connection", "speedometer", AnyView(ConnectionView())),
            ("History", "clock.arrow.circlepath", AnyView(HistoryView())),
            ("Net Utils", "function", AnyView(NetUtilsView())),
            ("Settings", "gearshape", AnyView(SettingsView()))
        ]
        return ZStack {
            Rectangle().fill(.ultraThinMaterial).opacity(0.6).ignoresSafeArea()
                .onTapGesture { withAnimation { showTools = false }; Haptics.tap() }
            VStack {
                Spacer()
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { _, tool in
                        NavigationLink {
                            tool.2.navigationTitle(tool.0)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: tool.1).font(.title3).foregroundStyle(Theme.accent)
                                    .frame(width: 36, height: 36)
                                    .background(Theme.accent.opacity(0.14), in: .rect(cornerRadius: 10))
                                Text(tool.0).font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                            .padding(12)
                            .background(Theme.surface, in: .rect(cornerRadius: 14, style: .continuous))
                        }
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                    }
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 28, style: .continuous))
                .padding(.horizontal, 16).padding(.bottom, 80)
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private func deviceSheet(_ ip: String) -> some View {
        if let d = latest?.devices.first(where: { $0.ip == ip }) {
            NavigationStack {
                DeviceProfileView(ip: d.ip, hostname: d.hostname, vendorGuess: d.vendorGuess)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }
}

private struct IPWrap: Identifiable { let ip: String; var id: String { ip } }

// MARK: - Draggable device node
// Extracted as its own view so the type-checker handles the gesture + position
// math in isolation rather than inside the main canvas body.

private struct DraggableNode: View {
    let node: SpatialNode
    let center: CGPoint
    let zoom: CGFloat
    let selected: Bool
    let onMoved: (CGSize) -> Void
    let onTap: () -> Void

    @State private var dragStart: CGSize? = nil

    var body: some View {
        let x: CGFloat = center.x + node.offset.width
        let y: CGFloat = center.y + node.offset.height
        // The hit area is the whole node frame as a rectangle, so you can grab it
        // anywhere on the icon OR the label — not just a circle that's offset from
        // what you see. A generous frame makes small nodes easy to grab.
        return NodeView(node: node, selected: selected, zoom: zoom)
            .frame(width: 110, height: 110)
            .contentShape(Rectangle())
            .position(x: x, y: y)
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let start = dragStart ?? node.offset
                        if dragStart == nil {
                            dragStart = start
                            Haptics.soft()   // picked up
                        }
                        let moved = CGSize(width: start.width + value.translation.width / zoom,
                                           height: start.height + value.translation.height / zoom)
                        onMoved(moved)
                    }
                    .onEnded { _ in
                        if dragStart != nil { Haptics.tap() }   // dropped
                        dragStart = nil
                    }
            )
            .onTapGesture { onTap() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(node.isNew ? "\(node.label), new device" : node.label)
            .accessibilityHint(node.openPorts > 0 ? "\(node.openPorts) open ports. Double-tap for details." : "Double-tap for details.")
            .accessibilityAddTraits(.isButton)
    }
}
