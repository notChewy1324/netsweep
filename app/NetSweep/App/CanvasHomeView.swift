import SwiftUI
import SwiftData

// MARK: - Canvas Home — the single immersive surface (replaces tabs)
// A pan/zoom spatial map of your network. Your device is centered; discovered
// devices float around it. Tap a node for a detail sheet; tap the orb for the
// radial tool menu; scan to watch devices materialize into the space.

struct CanvasHomeView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var service: NetworkScanService
    @Environment(\.modelContext) private var context
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]

    @State private var canvas = CanvasState()
    @State private var nodeOffsets: [String: CGSize] = [:]   // user dragged positions
    @State private var selectedIP: String?
    @State private var showTools = false
    @State private var showGateway = false
    @State private var cellularDismissed = false
    @State private var scanBreathing = false
    @State private var toolPanelOffset: CGSize = .zero
    @State private var toolsPanning = false
    @State private var showToolEditor = false

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
                    onPanEnded: { velocity in canvas.flingPan(velocity: velocity) },
                    onZoomChanged: { delta, anchor in
                        canvas.applyZoom(delta, anchor: anchor, viewSize: geo.size)
                    },
                    onZoomEnded: { canvas.endZoom() },
                    onDoubleTap: { pt in
                        // Toggle in/out at the tap point.
                        let target: CGFloat = canvas.zoom < 1.8 ? 2.0 : 1.0
                        canvas.zoomTo(target, anchor: pt, viewSize: geo.size)
                        Haptics.tap()
                    },
                    onTwoFingerTap: { pt in
                        let target: CGFloat = max(0.4, canvas.zoom * 0.5)
                        canvas.zoomTo(target, anchor: pt, viewSize: geo.size)
                        Haptics.tap()
                    },
                    onTwoFingerDoubleTap: { _ in
                        canvas.reset()
                        Haptics.success()
                    }
                )
            }

            // Layer 2: the transformed spatial content (lines + nodes). Nodes carry
            // their own high-priority drag so they win over the background pan.
            spatialLayer
                .scaleEffect(canvas.effectiveZoom)
                .offset(canvas.effectivePan)

            topBar
            emptyHint
            // Compact dismissible cellular pill anchored just below the brand
            // header. Solid background so map content underneath doesn't bleed
            // through, and the user can swipe it out of the way.
            if !cellularDismissed {
                VStack {
                    Spacer().frame(height: 86)
                    CellularPill(feature: "  ") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            cellularDismissed = true
                        }
                    }
                    .padding(.horizontal, 40)
                    Spacer()
                }
            }
            bottomControls

            if showTools { radialToolMenu }
            // The screen-edge scan glow now renders at the RootView level so
            // it stays visible across pushed views and the tools panel.
        }
        .sheet(item: Binding(get: { selectedIP.map { IPWrap(ip: $0) } },
                             set: { selectedIP = $0?.ip })) { wrap in
            deviceSheet(wrap.ip)
        }
        .sheet(isPresented: $showGateway) {
            NavigationStack { GatewayInfoView() }
                .zoomNavigationRoot()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showToolEditor) {
            ToolLayoutEditor()
                .environmentObject(settings)
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
                    label: AppInfo.displayName, icon: "scope", accent: healthMood,
                    fingerprint: nil, services: nil)
    }

    // Cached node list — rebuilt only when scan data or dragged positions
    // change, NOT on every pan/zoom frame (pan/zoom are pure transforms).
    @State private var cachedNodes: [SpatialNode] = []
    private var deviceNodes: [SpatialNode] { cachedNodes }

    private func rebuildNodes() {
        guard let s = latest else { cachedNodes = []; return }
        let devices = s.devices.sorted { (NetInfo.ipToUInt32($0.ip) ?? 0) < (NetInfo.ipToUInt32($1.ip) ?? 0) }
        cachedNodes = devices.enumerated().map { idx, d in
            // Port-signature fingerprint — what the device probably is, deduced
            // from the shape of its open-port set. Returns nil for unknown
            // signatures (e.g. zero or only generic open ports).
            let portsU16 = Set(d.openPorts.compactMap { UInt16(exactly: $0) })
            let fingerprint = Fingerprint.guess(openPorts: portsU16)
            // Top services for the second reveal line. Deduped, max 3.
            let serviceNames = d.openPorts.compactMap { UInt16(exactly: $0) }
                .map { Services.name($0) }
                .filter { $0 != "unknown" }
            var seen = Set<String>()
            let uniqueServices = serviceNames.filter { seen.insert($0).inserted }
            let services = uniqueServices.isEmpty ? nil
                : uniqueServices.prefix(3).joined(separator: "")
            return SpatialNode(
                id: d.ip,
                offset: nodeOffsets[d.ip] ?? radialOffset(idx, total: devices.count),
                isCenter: false, isNew: d.isNew,
                label: d.hostname ?? d.ip,
                icon: icon(for: d),
                accent: d.isNew ? Theme.amber : Theme.info,
                fingerprint: fingerprint,
                services: services)
        }
    }

    private func radialOffset(_ i: Int, total: Int) -> CGSize {
        guard total > 0 else { return .zero }
        // Vogel (sunflower) spiral: nodes step around at the golden angle
        // with radius growing like sqrt(i). The big win over a fixed-band
        // scatter is that nearest-neighbor distance stays roughly constant
        // at every density — small networks cluster near the device, big
        // networks naturally spread outward beyond the initial viewport
        // where the user can pan/zoom to reach them.
        let golden = 2.399963
        let angle = Double(i) * golden
        // 60pt base keeps the first device clear of the center "you" node;
        // 55pt per √i shell gives ~80–100pt nearest-neighbor spacing across
        // the full perimeter — about one node frame apart.
        let radius = 60.0 + 55.0 * sqrt(Double(i + 1))
        return CGSize(width: CGFloat(radius * cos(angle)),
                      height: CGFloat(radius * sin(angle)))
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
            HStack(alignment: .center, spacing: 12) {
                SonarSigil(color: healthMood, size: 32)
                VStack(alignment: .leading, spacing: 3) {
                    BrandWordmark(AppInfo.displayName, accent: healthMood, splitIndex: 3)
                    HStack(spacing: 6) {
                        StatusPulse(color: statusColor, isActive: service.isScanning)
                        Text(statusLine)
                            .font(.system(size: 10, design: .monospaced).weight(.medium))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                            .tracking(1.5)
                    }
                }
                Spacer()
                mapControlsCluster
            }
            .padding(.horizontal, 20).padding(.top, 8)
            .animation(.easeInOut(duration: 0.6), value: healthMood)
            Spacer()
        }
    }

    // Two map controls (reset node layout + recenter view) packaged as a
    // native-feeling instrument cluster: solid Theme.surface (matches the
    // tools orb and panels), mood-tinted border + icons + glow shadow + a
    // mood-tinted divider. Reads as part of the same instrument family as
    // the sigil, wordmark, and tools orb — not a system-style glass pill.
    private var mapControlsCluster: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
                    nodeOffsets.removeAll()
                    rebuildNodes()
                }
                Haptics.tap()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(healthMood)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Reset node layout")

            // Mood-tinted divider — matches the border so the whole
            // cluster reads as one color-coordinated instrument.
            Rectangle()
                .fill(healthMood.opacity(0.25))
                .frame(width: 1, height: 20)

            Button {
                canvas.reset()
                Haptics.tap()
            } label: {
                Image(systemName: "scope")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(healthMood)
                    .frame(width: 44, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Recenter view")
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(healthMood.opacity(0.35), lineWidth: 1)
                )
        )
        // Soft mood-tinted glow — the cluster sits on the canvas with
        // the same kind of presence as the scan button at the bottom.
        .shadow(color: healthMood.opacity(0.20), radius: 8, y: 2)
    }

    // Pulse color tracks scan state: amber during a scan, green when there's
    // a fresh session to look at, dim when we haven't scanned yet.
    private var statusColor: Color {
        if service.isScanning { return Theme.amber }
        return latest == nil ? Theme.textDim : Theme.good
    }

    private var statusLine: String {
        if service.isScanning { return "SCANNING…" }
        if let s = latest { return "\(s.deviceCount) DEVICES · HEALTH \(s.healthScore)" }
        return "AWAITING FIRST SCAN"
    }

    // A gentle prompt over the empty canvas inviting the first scan.
    // Anchored to the bottom of the canvas so it sits right above the
    // Scan button (the action it's pointing at) — and never competes with
    // the brand wordmark in the header, no matter the screen size.
    @ViewBuilder
    private var emptyHint: some View {
        if latest == nil && !service.isScanning {
            VStack {
                Spacer()
                VStack(spacing: 6) {
                    Text("Your network, visualized")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 6) {
                        Text("Tap")
                            .foregroundStyle(Theme.textDim)
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundStyle(Theme.accent)
                        Text("to map what's connected")
                            .foregroundStyle(Theme.textDim)
                    }
                    .font(.caption)
                }
                .multilineTextAlignment(.center)
                .padding(.bottom, 110)
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
            .allowsHitTesting(false)
        } else if latest != nil && !service.isScanning {
            // Subtle gesture tip after the first scan completes. Sits below
            // the header (and the cellular pill if it's still visible) so it
            // never collides with the brand wordmark.
            VStack {
                Text("drag to move · pinch to zoom · tap a node")
                    .font(.caption2).foregroundStyle(Theme.textFaint)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.surface.opacity(0.7), in: Capsule())
                    .padding(.top, cellularDismissed ? 80 : 138)
                Spacer()
            }
            .allowsHitTesting(false)
        }
    }

    private var bottomControls: some View {
        VStack {
            Spacer()
            HStack(spacing: 16) {
                toolsOrb
                // Push the scan button to the right edge instead of
                // stretching it across the row. The exposed canvas in
                // between gives the map room to breathe and makes both
                // buttons read as distinct floating instruments — not a
                // single connected control bar.
                Spacer(minLength: 0)
                scanButton
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private var toolsOrb: some View {
        Button {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                showTools.toggle()
                if !showTools { toolPanelOffset = .zero }
            }
            Haptics.tap()
        } label: {
            Image(systemName: showTools ? "xmark" : "square.grid.2x2")
                .font(.title2).foregroundStyle(Theme.textPrimary)
                // iOS 17+ SF Symbol morph — smoother than the old rotation.
                .contentTransition(.symbolEffect(.replace.byLayer))
                .frame(width: 56, height: 56)
                .background(Theme.surface, in: Circle())
                // Border tracks the brand mood color so the orb visually
                // belongs to the same instrument as the header sigil.
                .overlay(Circle().stroke(healthMood.opacity(0.35), lineWidth: 1))
        }
        .pressable()
    }

    private var scanButton: some View {
        Button {
            Haptics.medium()
            launchScan(intensity: settings.scanIntensity)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                    // Pulses outward through the symbol's color layers while
                    // scanning — carries the "active" signal without needing
                    // a separate ProgressView pip.
                    .symbolEffect(.variableColor.iterative.reversing,
                                  isActive: service.isScanning)
                Text(service.isScanning ? "Scanning" : "Scan")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
            }
            // Subheadline-sized label + tight padding shrinks the button
            // by ~35% vs. the previous content-sized capsule. The pinned
            // minWidth keeps the silhouette stable when the label swaps
            // between "Scan" and "Scanning".
            .frame(minWidth: 108)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .background(scanBackground)
            .foregroundStyle(Theme.canvasTop)
            // Mood-tinted glow that intensifies while scanning.
            .shadow(color: healthMood.opacity(service.isScanning ? 0.6 : 0.35),
                    radius: service.isScanning ? 14 : 10, y: 3)
            // Subtle breathing while scanning (1.0 ↔ 1.015).
            .scaleEffect(scanBreathing ? 1.015 : 1.0)
        }
        .fixedSize(horizontal: true, vertical: false)
        .disabled(service.isScanning)
        .pressable()
        // Long-press → quick intensity picker. Selecting an intensity here
        // also writes it back to AppSettings so Settings stays in sync and
        // the next plain tap of Scan uses the same intensity.
        .contextMenu {
            Section("Scan intensity") {
                ForEach(ScanIntensity.allCases) { intensity in
                    Button {
                        settings.scanIntensity = intensity
                        Haptics.medium()
                        launchScan(intensity: intensity)
                    } label: {
                        Label(intensity.label, systemImage: intensityIcon(intensity))
                    }
                }
            }
        }
        .onChange(of: service.isScanning) { _, isScanning in
            if isScanning {
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    scanBreathing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.4)) { scanBreathing = false }
            }
        }
    }

    // Full Capsule (rather than the old 18pt rounded rect) so the silhouette
    // visually rhymes with the round tools orb — they read as two members
    // of the same instrument family, not a banner and a button. The screen-
    // edge glow is the primary "scanning is active" macro signal; the
    // button keeps its breathing pulse, symbol effect, and mood glow.
    private var scanBackground: some View {
        Capsule(style: .continuous).fill(Theme.accent)
    }

    private func launchScan(intensity: ScanIntensity) {
        Task {
            await service.runFullScan(context: context,
                                      intensity: intensity,
                                      notify: settings.notifyNewDevices)
        }
    }

    private func intensityIcon(_ i: ScanIntensity) -> String {
        switch i {
        case .fast:     return "bolt"
        case .balanced: return "dot.radiowaves.left.and.right"
        case .thorough: return "scope"
        }
    }

    // MARK: Instrument panel
    // Replaces the old grid-of-rows with a richer "control panel" of
    // instrument tiles. Each tile shows a small static sonar mark, name, and
    // a one-line description. Mood-tinted throughout so the panel reads as
    // part of the same instrument family as the home brand kit and the new
    // scan button. Drag down or tap outside to dismiss.

    // Tool entries are now driven by the user-customizable layout in
    // AppSettings, looked up through the shared ToolCatalog so the editor
    // sheet and the panel render from the same source of truth.
    private var toolEntries: [ToolCatalogEntry] {
        settings.toolLayout.compactMap { ToolCatalog.entry(for: $0) }
    }

    @ViewBuilder
    private func destination(for id: String) -> some View {
        switch id {
        case "dashboard":    ThreatDashboardView()
        case "compare":      ScanDiffView()
        case "network-map":  NetworkMapView()
        case "port-scanner": PortScannerView()
        case "bonjour":      BonjourView()
        case "vuln":         VulnInsightsView()
        case "connection":   ConnectionView()
        case "history":      HistoryView()
        case "net-utils":    NetUtilsView()
        case "settings":     SettingsView()
        default:             EmptyView()
        }
    }

    private var radialToolMenu: some View {
        ZStack {
            // Simple solid scrim — no blur, no material. Just dims the
            // canvas so the panel reads as the focus. Cheaper to draw
            // than a full-screen UIVisualEffectView and matches the
            // observatory aesthetic better than a glassy haze.
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { dismissTools() }

            VStack {
                Spacer()
                instrumentPanel
                    // Live 2D offset — the panel follows the finger in any
                    // direction, can be paused mid-drag, and can be dragged
                    // back toward rest without dismissing.
                    .offset(toolPanelOffset)
                    // simultaneousGesture (not .gesture) so the drag runs
                    // *alongside* the tile NavigationLink buttons. Without
                    // this the tiles consume the touch and the panel can
                    // only be dragged from the gaps — same model iOS sheets
                    // use, where buttons fire on tap and content drags the
                    // sheet on movement.
                    .simultaneousGesture(panelDragGesture)
                    .padding(.horizontal, 16)
                    // Bottom-flush with the scan button row, so the panel
                    // appears to rise out of the tools orb's position.
                    .padding(.bottom, 12)
            }
            .transition(
                .asymmetric(
                    insertion: .scale(scale: 0.92, anchor: .bottom)
                        .combined(with: .opacity)
                        .combined(with: .move(edge: .bottom)),
                    // Plain fade-out, so a side-swipe dismissal fades the
                    // panel from where the user released — not snapped back
                    // to center and then dropped downward.
                    removal: .opacity
                )
            )
        }
    }

    private var instrumentPanel: some View {
        VStack(spacing: 8) {
            panelHeader
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8),
                                 GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(toolEntries) { tool in
                    NavigationLink {
                        destination(for: tool.id)
                            .navigationTitle(tool.name)
                            .zoomDestination("tool-\(tool.id)")
                    } label: {
                        instrumentTile(tool: tool)
                    }
                    .buttonStyle(.plain)
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                    .zoomSource("tool-\(tool.id)")
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            // Once a pan starts moving the finger meaningfully, every tile
            // becomes disabled — SwiftUI cancels any in-flight button press
            // so a swipe that began on a tile no longer triggers navigation.
            // Stays enabled for pure taps (no movement), so the menu still
            // works normally.
            .disabled(toolsPanning)
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.canvasTop)
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(healthMood.opacity(0.28), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 24, y: 8)
        )
    }

    private var panelHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: "scope")
                .font(.caption).foregroundStyle(healthMood)
            Text("ARRAY")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .tracking(3)
                .foregroundStyle(Theme.textDim)
            Spacer()
            // Grab handle — visual hint that the panel can be dragged.
            Capsule()
                .fill(Theme.textFaint.opacity(0.6))
                .frame(width: 40, height: 4)
            Spacer()
            Button {
                Haptics.tap()
                showToolEditor = true
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(healthMood)
                    .frame(width: 30, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize tools")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .contentShape(Rectangle())
    }

    private func instrumentTile(tool: ToolCatalogEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            InstrumentMark(icon: tool.icon, color: tool.accent)
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(tool.subtitle)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            // Solid surface fill — no .ultraThinMaterial, no gradient wash.
            // Drops a noticeable amount of compositing work compared to the
            // old two-layer ZStack of material + gradient, and the tile
            // reads cleaner against the dimmed scrim behind it.
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tool.accent.opacity(0.32), lineWidth: 1)
        )
    }

    // Fully interactive 2D drag. The panel tracks the finger 1:1 in every
    // direction. The user can pause mid-drag, reverse course, or release.
    // On release: past ~100pt radial distance — or a flick whose predicted
    // landing is past ~240pt — the panel dismisses; otherwise it springs
    // back to rest.
    //
    // minimumDistance: 14 gives quick taps real breathing room. The natural
    // 5–10pt finger jitter that accompanies a fast tap no longer trips the
    // drag detection (which used to flip toolsPanning on and cancel the
    // button press mid-flight). Once the gesture *does* fire, the drag is
    // already committed, so we can flip toolsPanning directly without a
    // secondary magnitude check.
    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if !toolsPanning { toolsPanning = true }
                toolPanelOffset = value.translation
            }
            .onEnded { value in
                let t = value.translation
                let p = value.predictedEndTranslation
                let magnitude = (t.width * t.width + t.height * t.height).squareRoot()
                let predictedMag = (p.width * p.width + p.height * p.height).squareRoot()
                let shouldDismiss = magnitude > 100 || predictedMag > 240
                if shouldDismiss {
                    dismissTools()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        toolPanelOffset = .zero
                    }
                }
                // Re-enable tiles after the gesture ends. If we dismissed,
                // it's also fine — the panel is gone.
                toolsPanning = false
            }
    }

    private func dismissTools() {
        Haptics.soft()
        withAnimation(.easeOut(duration: 0.25)) {
            showTools = false
        }
        // Defer the offset reset until after the fade-out so the panel
        // actually fades from where the user released, not snapped back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            toolPanelOffset = .zero
        }
    }

    @ViewBuilder
    private func deviceSheet(_ ip: String) -> some View {
        if let d = latest?.devices.first(where: { $0.ip == ip }) {
            NavigationStack {
                DeviceProfileView(ip: d.ip, hostname: d.hostname, vendorGuess: d.vendorGuess)
            }
            .zoomNavigationRoot()
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
            // Hit area is the visible disc only (halo-sized), not the full
            // 110×110 frame. Empty space around the node's label and glow
            // no longer steals taps from the background pan/zoom gestures.
            .contentShape(Circle().inset(by: node.isCenter ? 16 : 26))
            .position(x: x, y: y)
            .highPriorityGesture(
                // Critical: use .global. Inside .scaleEffect, the default
                // .local coordinate space reports translation in PRE-scale
                // local pts — i.e. finger pts × (1/zoom) — and then dividing
                // by zoom again over-corrects, especially at low zoom. With
                // .global the translation is raw screen pts and / zoom is the
                // exact mapping to content space.
                DragGesture(minimumDistance: 6, coordinateSpace: .global)
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
            .accessibilityHint(node.fingerprint ?? "Double tap for details.")
            .accessibilityAddTraits(.isButton)
    }
}
