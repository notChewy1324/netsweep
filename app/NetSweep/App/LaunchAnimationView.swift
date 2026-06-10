import SwiftUI

// MARK: - Launch — packet routing & mesh formation
// A single packet ignites in the corner and runs across a dark grid to the
// core. On arrival the core explodes into a radial burst of packets that
// race outward to perimeter nodes; the perimeter nodes chain-link into a
// glowing ring, then an inner cross-mesh fills it in. Finally the whole
// topology rushes back to the core in a brilliant flash from which the
// NetSweep wordmark resolves.

struct LaunchAnimationView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t0 = Date()

    // Phase scrubbers — each animates 0 → 1 over its phase.
    @State private var gridFade: Double = 0
    @State private var seedRun: Double = 0      // corner packet → center
    @State private var burst: Double = 0        // center → 8 perimeter nodes
    @State private var perimeter: Double = 0    // ring edges form
    @State private var innerMesh: Double = 0    // cross-mesh through center
    @State private var collapse: Double = 0     // everything contracts to core
    @State private var flash: Double = 0        // white hot pulse
    @State private var logoReveal: Double = 0
    @State private var taglineReveal: Double = 0

    // Scheduled work for the animation timeline. We keep references so the
    // sequence can be cancelled cleanly if the view disappears or the user
    // skips by tapping, preventing late callbacks from firing haptics or
    // calling onFinished a second time.
    @State private var pendingWork: [DispatchWorkItem] = []
    @State private var hasFinished = false

    private let nodeCount = 8

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36

            ZStack {
                ObservatoryCanvas()

                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(t0)
                    Canvas { ctx, sz in
                        draw(&ctx, size: sz, center: center, radius: radius, t: t)
                    }
                }
                .ignoresSafeArea()

                // Radial bloom that pulses out of the core on collapse.
                RadialGradient(colors: [Theme.accent.opacity(flash * 0.7),
                                        Theme.accent.opacity(flash * 0.15),
                                        .clear],
                               center: .center,
                               startRadius: 0,
                               endRadius: max(size.width, size.height) * 0.75)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                // White hot pulse layered on top during the flash.
                Color.white
                    .opacity(flash * 0.35)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 10) {
                    Spacer()
                    Text(AppInfo.displayName)
                        .font(.system(size: 44, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(Theme.textPrimary)
                        .shadow(color: Theme.accent.opacity(0.6 * logoReveal), radius: 22)
                        .opacity(logoReveal)
                        .blur(radius: 10 * (1 - logoReveal))
                        .scaleEffect(0.94 + 0.06 * logoReveal)
                    Text(AppInfo.tagline)
                        .font(.subheadline).tracking(3)
                        .foregroundStyle(Theme.textDim)
                        .opacity(taglineReveal)
                    Spacer().frame(height: size.height * 0.18)
                }
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { skip() }
        .onAppear(perform: play)
        .onDisappear { cancelPending() }
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize,
                      center: CGPoint, radius: CGFloat, t: TimeInterval) {
        let nodes = (0..<nodeCount).map { i -> CGPoint in
            let angle = Double(i) / Double(nodeCount) * 2 * .pi - .pi / 2
            return CGPoint(x: center.x + radius * CGFloat(cos(angle)),
                           y: center.y + radius * CGFloat(sin(angle)))
        }

        // Faint blueprint grid + crosshair: establishes the "system coming online" feel.
        if gridFade > 0.01 {
            let g = easeOut(gridFade)
            let spacing: CGFloat = 36
            var grid = Path()
            var x: CGFloat = 0
            while x < size.width {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }
            var y: CGFloat = 0
            while y < size.height {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }
            ctx.stroke(grid, with: .color(Theme.accent.opacity(0.06 * g)), lineWidth: 0.5)

            var cross = Path()
            cross.move(to: CGPoint(x: 0, y: center.y))
            cross.addLine(to: CGPoint(x: size.width, y: center.y))
            cross.move(to: CGPoint(x: center.x, y: 0))
            cross.addLine(to: CGPoint(x: center.x, y: size.height))
            ctx.stroke(cross, with: .color(Theme.accent.opacity(0.10 * g)), lineWidth: 0.7)
        }

        // Collapse: everything outside the core slides back toward center.
        let c = easeIn(collapse)
        func collapsed(_ p: CGPoint) -> CGPoint {
            CGPoint(x: p.x + (center.x - p.x) * CGFloat(c),
                    y: p.y + (center.y - p.y) * CGFloat(c))
        }

        // Phase: inner cross mesh (every-other perimeter node → through center).
        if innerMesh > 0 {
            let m = easeOut(innerMesh)
            let pairs = nodeCount / 2
            for i in 0..<pairs {
                let a = collapsed(nodes[i])
                let b = collapsed(nodes[i + pairs])
                let lit = min(m * Double(pairs) - Double(i), 1.0)
                if lit <= 0 { continue }
                let mid = CGPoint(x: a.x + (b.x - a.x) * CGFloat(lit),
                                  y: a.y + (b.y - a.y) * CGFloat(lit))
                var edge = Path()
                edge.move(to: a)
                edge.addLine(to: mid)
                ctx.stroke(edge,
                           with: .color(Theme.info.opacity(0.55 * (1 - c))),
                           lineWidth: 1.2)
            }
        }

        // Phase: perimeter ring (chain edges between adjacent perimeter nodes).
        if perimeter > 0 {
            let p = easeOut(perimeter)
            for i in 0..<nodeCount {
                let a = collapsed(nodes[i])
                let b = collapsed(nodes[(i + 1) % nodeCount])
                let lit = min(p * Double(nodeCount) - Double(i), 1.0)
                if lit <= 0 { continue }
                let mid = CGPoint(x: a.x + (b.x - a.x) * CGFloat(lit),
                                  y: a.y + (b.y - a.y) * CGFloat(lit))
                var edge = Path()
                edge.move(to: a)
                edge.addLine(to: mid)
                ctx.stroke(edge,
                           with: .color(Theme.accent.opacity(0.65 * (1 - c))),
                           lineWidth: 1.5)
                if lit < 1 {
                    drawGlow(&ctx, at: mid, r: 5, color: Theme.accent, alpha: 0.9 * (1 - c))
                }
            }
        }

        // Phase: burst packets (center → each perimeter node, staggered).
        if burst > 0 {
            let b = easeOut(burst)
            for (i, node) in nodes.enumerated() {
                let lit = min(b * 1.25 - Double(i) * 0.04, 1.0)
                if lit <= 0 { continue }
                let head = CGPoint(x: center.x + (node.x - center.x) * CGFloat(lit),
                                   y: center.y + (node.y - center.y) * CGFloat(lit))
                let h = collapsed(head)
                drawTrail(&ctx, from: collapsed(center), to: h, color: Theme.accent, fade: 1 - c)
                drawGlow(&ctx, at: h, r: 6, color: Theme.accent, alpha: 1 - c)
                // Light up the destination node as the packet arrives.
                let nodeAlpha = pow(lit, 4) * (1 - c)
                drawNode(&ctx, at: collapsed(node), color: Theme.accent,
                         pulse: 1.0, alpha: nodeAlpha)
            }
        }

        // Phase: seed packet — single corner streak racing to the core.
        if seedRun > 0 && seedRun < 1.0 {
            let s = easeInOut(seedRun)
            let start = CGPoint(x: size.width * 0.08, y: size.height * 0.18)
            let head = CGPoint(x: start.x + (center.x - start.x) * CGFloat(s),
                               y: start.y + (center.y - start.y) * CGFloat(s))
            drawTrail(&ctx, from: start, to: head, color: Theme.accent, fade: 1)
            drawGlow(&ctx, at: head, r: 8, color: Theme.accent, alpha: 1)
        }

        // Core node — appears the moment the seed arrives, then pulses.
        if seedRun > 0.1 {
            let intensity = min(1.0, seedRun * 1.5) * (1 - 0.5 * c)
            let pulseScale = 1.0 + 0.3 * sin(t * 4)
            drawNode(&ctx, at: center, color: Theme.accent,
                     pulse: pulseScale, alpha: intensity)
        }
    }

    // Glowing motion-trail behind a packet head. Tail fades with a quadratic
    // ramp so the brightest part hugs the head.
    private func drawTrail(_ ctx: inout GraphicsContext,
                           from: CGPoint, to: CGPoint, color: Color, fade: Double) {
        let segments = 12
        for i in 0..<segments {
            let f1 = Double(i) / Double(segments)
            let f2 = Double(i + 1) / Double(segments)
            let p1 = CGPoint(x: from.x + (to.x - from.x) * CGFloat(f1),
                             y: from.y + (to.y - from.y) * CGFloat(f1))
            let p2 = CGPoint(x: from.x + (to.x - from.x) * CGFloat(f2),
                             y: from.y + (to.y - from.y) * CGFloat(f2))
            var seg = Path()
            seg.move(to: p1)
            seg.addLine(to: p2)
            let alpha = pow(f2, 2.0) * fade * 0.8
            ctx.stroke(seg, with: .color(color.opacity(alpha)),
                       lineWidth: 1.5 + 0.5 * f2)
        }
    }

    private func drawGlow(_ ctx: inout GraphicsContext, at p: CGPoint, r: CGFloat,
                          color: Color, alpha: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.5, y: p.y - r * 2.5,
                                        width: r * 5, height: r * 5)),
                 with: .color(color.opacity(alpha * 0.12)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                        width: r * 2, height: r * 2)),
                 with: .color(color.opacity(alpha)))
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.4, y: p.y - r * 0.4,
                                        width: r * 0.8, height: r * 0.8)),
                 with: .color(.white.opacity(alpha * 0.9)))
    }

    private func drawNode(_ ctx: inout GraphicsContext, at p: CGPoint, color: Color,
                          pulse: Double, alpha: Double) {
        let r: CGFloat = 4.5 * CGFloat(pulse)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.5, y: p.y - r * 2.5,
                                        width: r * 5, height: r * 5)),
                 with: .color(color.opacity(alpha * 0.18)))
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r,
                                          width: r * 2, height: r * 2)),
                   with: .color(color.opacity(alpha)), lineWidth: 1.5)
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.5,
                                        width: r, height: r)),
                 with: .color(color.opacity(alpha)))
    }

    // MARK: Easing

    private func easeOut(_ v: Double) -> Double { 1 - pow(1 - clamp(v), 3) }
    private func easeIn(_ v: Double) -> Double { pow(clamp(v), 3) }
    private func easeInOut(_ v: Double) -> Double {
        let c = clamp(v)
        return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
    }
    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }

    // MARK: Sequence

    private func play() {
        t0 = Date()
        if reduceMotion {
            // Honor reduce-motion: skip the multi-phase choreography, settle
            // into the final pose in a single short fade, and hand off to the
            // app quickly rather than holding for a full second.
            withAnimation(.easeOut(duration: 0.3)) {
                gridFade = 1; seedRun = 1; burst = 1; perimeter = 1
                innerMesh = 1; logoReveal = 1; taglineReveal = 1
            }
            schedule(after: 0.35) {
                withAnimation(.easeIn(duration: 0.25)) { finish() }
            }
            return
        }

        // Compressed ~2 second sequence — phases overlap more aggressively so
        // each beat feels like it's already underway as the previous resolves,
        // and easeInOut throughout gives a smoother, less staccato flow.
        //
        // 0.00 → 0.25  blueprint grid materializes
        withAnimation(.easeInOut(duration: 0.25)) { gridFade = 1 }
        // 0.10 → 0.50  seed packet streaks corner-to-core
        withAnimation(.easeInOut(duration: 0.40).delay(0.10)) { seedRun = 1 }
        // 0.50         soft tick as the packet hits the core
        schedule(after: 0.50) { Haptics.soft() }
        // 0.50 → 0.95  core erupts; 8 packets race outward
        withAnimation(.easeOut(duration: 0.45).delay(0.50)) { burst = 1 }
        // 0.75 → 1.15  perimeter ring chains together
        withAnimation(.easeOut(duration: 0.40).delay(0.75)) { perimeter = 1 }
        // 0.90 → 1.25  inner cross-mesh fills the ring
        withAnimation(.easeOut(duration: 0.35).delay(0.90)) { innerMesh = 1 }
        // 1.25 → 1.55  collapse to core
        withAnimation(.easeIn(duration: 0.30).delay(1.25)) { collapse = 1 }
        // 1.50 → 1.90  white-hot flash, then fade
        withAnimation(.easeIn(duration: 0.12).delay(1.50)) { flash = 1 }
        withAnimation(.easeOut(duration: 0.35).delay(1.62)) { flash = 0 }
        schedule(after: 1.50) { Haptics.tap() }
        // 1.55 → 1.95  logo resolves from the flash
        withAnimation(.spring(response: 0.45, dampingFraction: 0.78).delay(1.55)) { logoReveal = 1 }
        // 1.70 → 2.00  tagline fades in
        withAnimation(.easeOut(duration: 0.30).delay(1.70)) { taglineReveal = 1 }
        // 2.10         hand off to the app
        schedule(after: 2.10) {
            withAnimation(.easeInOut(duration: 0.35)) { finish() }
        }
    }

    // Tap-to-skip: collapse the choreography into a fast resolve so the user
    // is never trapped behind the full 2 second intro. Cancels every pending
    // beat first to avoid late haptics and double finishes.
    private func skip() {
        guard !hasFinished else { return }
        cancelPending()
        withAnimation(.easeOut(duration: 0.2)) {
            gridFade = 1; seedRun = 1; burst = 1; perimeter = 1
            innerMesh = 1; flash = 0; logoReveal = 1; taglineReveal = 1
        }
        schedule(after: 0.22) {
            withAnimation(.easeInOut(duration: 0.25)) { finish() }
        }
    }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        Haptics.success()
        onFinished()
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping () -> Void) {
        let item = DispatchWorkItem(block: block)
        pendingWork.append(item)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func cancelPending() {
        for item in pendingWork { item.cancel() }
        pendingWork.removeAll()
    }
}
