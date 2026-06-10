import SwiftUI

// MARK: - Spatial node model
// A device positioned in the canvas's coordinate space. Positions are assigned
// once (radial layout) then the user can drag individual nodes freely.

struct SpatialNode: Identifiable {
    let id: String          // device IP (stable key)
    var offset: CGSize      // position relative to canvas center
    let isCenter: Bool
    let isNew: Bool
    let label: String
    let icon: String
    let accent: Color
    // Revealed when the user zooms in. Both are optional — if neither has a
    // value the reveal block stays hidden so we don't show empty rows.
    let fingerprint: String?   // port-signature device guess, e.g. "AirPlay / Apple TV"
    let services: String?      // top services joined, e.g. "ssh · http · mdns"
}

// MARK: - Canvas interaction state (pan + zoom)
// Driven by incremental deltas from the UIKit gesture surface: pan adds a
// translation delta each frame; zoom multiplies by a scale delta, anchored at
// the pinch midpoint so the content under the fingers stays put.

@Observable
final class CanvasState {
    var zoom: CGFloat = 1.0
    var pan: CGSize = .zero

    private let minZoom: CGFloat = 0.4
    private let maxZoom: CGFloat = 3.0
    // Remembered for endZoom() so a rubber-band snap-back can keep the same
    // anchor stable instead of drifting the content during the spring.
    private var lastZoomAnchor: CGPoint = .zero
    private var lastViewSize: CGSize = .zero
    @ObservationIgnored private var inertiaTask: Task<Void, Never>?

    var effectiveZoom: CGFloat { zoom }
    var effectivePan: CGSize { pan }

    // Incremental pan from the gesture surface. A new pan kills any in-flight
    // fling so the canvas immediately obeys the new touch.
    func applyPan(_ delta: CGSize) {
        cancelInertia()
        pan.width += delta.width
        pan.height += delta.height
    }

    // Decelerating glide after a flick. `velocity` is the pan recognizer's
    // velocity in pt/sec; we apply it per-frame with exponential decay.
    func flingPan(velocity: CGPoint) {
        cancelInertia()
        let magnitude = (velocity.x * velocity.x + velocity.y * velocity.y).squareRoot()
        guard magnitude > 120 else { return }   // ignore tiny flicks
        let initialVx = velocity.x
        let initialVy = velocity.y
        let dt: CGFloat = 1.0 / 60.0
        let decay: CGFloat = 0.93
        inertiaTask = Task { @MainActor [weak self] in
            var vx = initialVx
            var vy = initialVy
            while !Task.isCancelled, (vx * vx + vy * vy).squareRoot() > 8 {
                try? await Task.sleep(nanoseconds: 16_000_000)
                if Task.isCancelled { break }
                self?.pan.width += vx * dt
                self?.pan.height += vy * dt
                vx *= decay
                vy *= decay
            }
        }
    }

    func cancelInertia() {
        inertiaTask?.cancel()
        inertiaTask = nil
    }

    // Incremental zoom, anchored at `anchor` (in the view's coordinate space,
    // origin at center). Keeps the point under the fingers stationary. Past
    // the [minZoom, maxZoom] limits we let the zoom drift with diminishing
    // returns ("rubber-band") so the gesture stays alive — endZoom() then
    // springs back into bounds.
    func applyZoom(_ delta: CGFloat, anchor: CGPoint, viewSize: CGSize) {
        cancelInertia()
        lastZoomAnchor = anchor
        lastViewSize = viewSize
        let proposed = zoom * delta
        let constrained: CGFloat
        if proposed < minZoom {
            constrained = minZoom - (minZoom - proposed) * 0.35
        } else if proposed > maxZoom {
            constrained = maxZoom + (proposed - maxZoom) * 0.35
        } else {
            constrained = proposed
        }
        let actualDelta = constrained / zoom
        let ax = anchor.x - viewSize.width / 2
        let ay = anchor.y - viewSize.height / 2
        pan.width = (pan.width - ax) * actualDelta + ax
        pan.height = (pan.height - ay) * actualDelta + ay
        zoom = constrained
    }

    // Called on pinch release. If the user stretched past the limits we
    // spring back to the nearest clamp while preserving the last anchor.
    func endZoom() {
        guard zoom < minZoom || zoom > maxZoom else { return }
        let target = min(max(zoom, minZoom), maxZoom)
        let actualDelta = target / zoom
        let ax = lastZoomAnchor.x - lastViewSize.width / 2
        let ay = lastZoomAnchor.y - lastViewSize.height / 2
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            pan.width = (pan.width - ax) * actualDelta + ax
            pan.height = (pan.height - ay) * actualDelta + ay
            zoom = target
        }
        Haptics.soft()
    }

    // Animated jump to a specific zoom, anchored at `anchor`. Used by the
    // double-tap and two-finger-tap shortcuts.
    func zoomTo(_ target: CGFloat, anchor: CGPoint, viewSize: CGSize) {
        cancelInertia()
        let clamped = min(max(target, minZoom), maxZoom)
        let actualDelta = clamped / zoom
        let ax = anchor.x - viewSize.width / 2
        let ay = anchor.y - viewSize.height / 2
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            pan.width = (pan.width - ax) * actualDelta + ax
            pan.height = (pan.height - ay) * actualDelta + ay
            zoom = clamped
        }
    }

    func reset() {
        cancelInertia()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            zoom = 1; pan = .zero
        }
    }
}

// MARK: - A single device node rendered in space

struct NodeView: View {
    let node: SpatialNode
    let selected: Bool
    var zoom: CGFloat = 1.0     // when zoomed in, reveal more detail
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var revealDetail: Bool {
        zoom > 1.4 && (node.fingerprint != nil || node.services != nil)
    }

    var body: some View {
        // The circle is the centered core (so it aligns with the hit area's
        // center). Labels hang below as an overlay and don't shift the circle.
        ZStack {
            // Glow halo
            Circle()
                .fill(node.accent.opacity(selected ? 0.35 : 0.18))
                .frame(width: node.isCenter ? 78 : 58, height: node.isCenter ? 78 : 58)
                .blur(radius: 6)
                .scaleEffect(pulse ? 1.08 : 0.95)
            // Body
            Circle()
                .fill(Theme.surfaceHi)
                .frame(width: node.isCenter ? 60 : 44, height: node.isCenter ? 60 : 44)
                .overlay(Circle().stroke(node.accent, lineWidth: selected ? 2.5 : 1.5))
            Image(systemName: node.icon)
                .font(.system(size: node.isCenter ? 24 : 17))
                .foregroundStyle(node.accent)
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 2) {
                if node.isNew {
                    Text("NEW").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.amber)
                }
                Text(node.label)
                    .font(.system(size: node.isCenter ? 12 : 10, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1).frame(maxWidth: 100)
                if revealDetail {
                    // Port-signature fingerprint: the impressive bit — the app
                    // tells you what the device *is* from its open-port shape.
                    if let fp = node.fingerprint {
                        Text(fp)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(node.accent)
                            .lineLimit(1)
                    }
                    // Top services as compact mono pills inline.
                    if let svc = node.services {
                        Text(svc)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                            .lineLimit(1)
                    }
                }
            }
            .fixedSize()
            .offset(y: 38)   // hang below the circle without affecting centering
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.25), value: revealDetail)
        .onAppear {
            guard !reduceMotion else { pulse = false; return }
            withAnimation(.easeInOut(duration: 2.0 + Double.random(in: 0...1)).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Expanding grid
// A large grid drawn well beyond the screen so that panning/zooming reveals
// "more space" — the canvas feels like an open field, not a bounded box.

struct ExpandingGrid: View {
    var spacing: CGFloat = 44
    var body: some View {
        Canvas { ctx, size in
            // Draw across a region 3x the view in each direction, centered.
            let extra = max(size.width, size.height) * 1.5
            let minX = -extra, maxX = size.width + extra
            let minY = -extra, maxY = size.height + extra
            var path = Path()
            var x = minX
            while x <= maxX { path.move(to: CGPoint(x: x, y: minY)); path.addLine(to: CGPoint(x: x, y: maxY)); x += spacing }
            var y = minY
            while y <= maxY { path.move(to: CGPoint(x: minX, y: y)); path.addLine(to: CGPoint(x: maxX, y: y)); y += spacing }
            ctx.stroke(path, with: .color(Theme.accent.opacity(0.05)), lineWidth: 0.5)
        }
        .ignoresSafeArea()
    }
}
// MARK: - Instrument mark
// A static sonar-style emblem used in the instrument panel's tool tiles —
// concentric rings + an SF Symbol icon in the center, tinted by the active
// brand mood color. Intentionally non-animated so 8 of them on screen don't
// each pay for a TimelineView refresh.

struct InstrumentMark: View {
    let icon: String
    let color: Color

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.22), lineWidth: 1)
            Circle().stroke(color.opacity(0.38), lineWidth: 1)
                .scaleEffect(0.66)
            Circle().fill(color.opacity(0.18))
                .scaleEffect(0.45)
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(color)
        }
    }
}

// MARK: - Screen-edge scan glow ("Aurora Breath")
// A single mood-colored edge that softly breathes while a scan is running,
// with one slow accent "head" drifting around the perimeter. No multi-color
// wheel, no white sweeps, no plus-lighter blending. The breathing baseline
// signals "active" calmly; the drifting head signals "progressing" without
// the eye-catching strobe of the old radar pattern.
//
// Performance: one cached SwiftUI shape with stacked shadows (GPU-cheap) +
// one Canvas pass per frame for the moving head — versus the previous
// three Canvas passes plus a 15pt blur filter. TimelineView runs at 20 FPS
// because the underlying motion is slow enough that 20 FPS is visually
// identical to 60 FPS, at a third of the work.

struct ScreenEdgeScanGlow: View {
    // 55pt matches the actual display corner radius of modern iPhones
    // (iPhone 14 Pro and later, iPhone Air). Previously 50pt left a
    // slight gap at the rounded corners on these devices.
    // 65 is good start for corner edges
    var cornerRadius: CGFloat = 65
    // 0 = invisible, 1 = fully drawn. Used as opacity for the simple fade
    // intro — no perimeter trim animation any more.
    var introProgress: Double = 1.0
    // The base color of the glow. Defaults to the brand accent; the caller
    // can pass the active health-mood color so the glow recolors with the
    // network state.
    var color: Color = Theme.accent

    @Environment(\.colorScheme) private var colorScheme
    @State private var t0 = Date()

    var body: some View {
        // Light vs. dark calls for very different tuning. In light mode,
        // colored shadows fade against the bright canvas — the line ITSELF
        // has to carry most of the signal, so it needs to be substantially
        // thicker and stay at a higher baseline opacity. In dark mode the
        // bloom shadows pop against the deep canvas, so thinner lines and
        // more breath dynamics feel right.
        let isLight = colorScheme == .light
        let bloomLine: CGFloat   = isLight ? 8   : 6
        let crispLine: CGFloat   = isLight ? 4   : 3
        let headLine:  CGFloat   = isLight ? 8   : 6
        let floor: Double        = isLight ? 0.85 : 0.70
        let range: Double        = isLight ? 0.15 : 0.30
        let bloomA: Double       = isLight ? 0.95 : 0.80
        let bloomB: Double       = isLight ? 0.70 : 0.55
        let bloomC: Double       = isLight ? 0.45 : 0.30

        return TimelineView(.animation(minimumInterval: 1.0 / 20)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(t0)
            let breathPhase = elapsed.truncatingRemainder(dividingBy: 2.4) / 2.4
            let breath = floor + range * (0.5 - 0.5 * cos(breathPhase * 2 * .pi))

            // Drifting accent head — one lap every 4.5s.
            let headPhase = (elapsed / 4.5).truncatingRemainder(dividingBy: 1.0)
            let headAngle = Angle.degrees(headPhase * 360 - 90)

            ZStack {
                // Bloom: .stroke (not .strokeBorder) puts the line center
                // right on the screen edge, so the visible half hugs the
                // bezel rather than sitting inset by lineWidth/2. The
                // outside half clips against the screen edge naturally,
                // so the line APPEARS edge-to-edge without any gap.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(color.opacity(breath * 0.60), lineWidth: bloomLine)
                    .shadow(color: color.opacity(breath * bloomA), radius: 14)
                    .shadow(color: color.opacity(breath * bloomB), radius: 30)
                    .shadow(color: color.opacity(breath * bloomC), radius: 50)

                // Crisp inner edge — the brightest, cleanest line. Same
                // .stroke trick so it hugs the screen edge precisely.
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(color.opacity(breath), lineWidth: crispLine)

                // Drifting head — a Canvas conic stroke at the screen
                // edge. Path matches the screen bounds so the inner
                // half of the stroke renders right at the bezel.
                Canvas { ctx, size in
                    let rect = CGRect(origin: .zero, size: size)
                    let path = Path(
                        roundedRect: rect,
                        cornerSize: CGSize(width: cornerRadius,
                                           height: cornerRadius),
                        style: .continuous)
                    let center = CGPoint(x: size.width / 2,
                                         y: size.height / 2)
                    let stops: [Gradient.Stop] = [
                        .init(color: .clear,             location: 0.00),
                        .init(color: .clear,             location: 0.40),
                        .init(color: color.opacity(1.0), location: 0.50),
                        .init(color: .clear,             location: 0.60),
                        .init(color: .clear,             location: 1.00)
                    ]
                    let shading = GraphicsContext.Shading.conicGradient(
                        Gradient(stops: stops),
                        center: center,
                        angle: headAngle)
                    ctx.stroke(path, with: shading, lineWidth: headLine)
                }
            }
            .opacity(introProgress)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Perimeter sweep
// A glowing point that rotates continuously around a rounded-rect border —
// the scan button's "instrument is active" indicator. TimelineView drives the
// angle directly so the sweep is perfectly continuous (no seam between
// repeatForever cycles), and only runs while the view is on screen.

struct PerimeterSweep: View {
    let color: Color
    var cornerRadius: CGFloat = 18
    var cycleSeconds: Double = 1.4
    var lineWidth: CGFloat = 2.5

    @State private var t0 = Date()

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(t0)
            let progress = elapsed.truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds
            // -90° puts the start of the gradient at "12 o'clock"; we then
            // rotate clockwise around the perimeter.
            let angle = Angle.degrees(progress * 360 - 90)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.00),
                            .init(color: .clear, location: 0.88),
                            .init(color: color, location: 0.95),
                            .init(color: .clear, location: 1.00)
                        ]),
                        center: .center,
                        angle: angle
                    ),
                    lineWidth: lineWidth
                )
        }
    }
}

