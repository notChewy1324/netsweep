import SwiftUI

// MARK: - Launch — the observatory powers on (starfield warp-in + pulse ripple)
// Stars streak inward from the edges and settle, establishing depth; then the
// core ignites and sends concentric pulse ripples outward through them. The
// ripple gently nudges stars as it passes, tying the two effects together.
// Full-bleed, cinematic, then the name resolves and we hand off.

struct LaunchAnimationView: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var t0 = Date()
    @State private var stars: [Star] = []
    @State private var warp: Double = 0        // 0→1 stars streak in & settle
    @State private var coreGlow: Double = 0
    @State private var ripple: Double = 0       // 0→1 expanding pulse rings
    @State private var nameOpacity: Double = 0
    @State private var nameBlur: CGFloat = 10
    @State private var finalBloom: Double = 0

    struct Star {
        let angle: Double       // direction from center
        let startDist: CGFloat  // how far out it begins
        let settleDist: CGFloat // where it comes to rest
        let size: CGFloat
        let twinklePhase: Double
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                ObservatoryCanvas()

                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSince(t0)
                    Canvas { ctx, sz in
                        draw(&ctx, size: sz, t: t)
                    }
                }
                .ignoresSafeArea()

                RadialGradient(colors: [Theme.accent.opacity(0.35 * finalBloom), .clear],
                               center: .center, startRadius: 0, endRadius: max(size.width, size.height) * 0.6)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                VStack(spacing: 8) {
                    Spacer()
                    Text(AppInfo.displayName)
                        .font(.system(size: 40, weight: .bold))
                        .tracking(4)
                        .foregroundStyle(Theme.textPrimary)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 20)
                        .opacity(nameOpacity)
                        .blur(radius: nameBlur)
                    Text(AppInfo.tagline)
                        .font(.subheadline).tracking(3)
                        .foregroundStyle(Theme.textDim)
                        .opacity(nameOpacity * 0.85)
                    Spacer().frame(height: geo.size.height * 0.16)
                }
            }
            .onAppear { if stars.isEmpty { stars = makeStars(for: size) } }
        }
        .ignoresSafeArea()
        .onAppear(perform: play)
    }

    // MARK: Drawing

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, t: TimeInterval) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxR = max(size.width, size.height)

        // 1. Starfield warp-in: each star streaks from far out to its settle point.
        let w = easeOut(warp)
        for star in stars {
            let dist = star.startDist + (star.settleDist - star.startDist) * CGFloat(w)
            // Ripple nudge: when a pulse front passes a star, push it slightly out.
            let rippleFront = CGFloat(ripple) * maxR * 0.6
            let nudge: CGFloat = abs(dist - rippleFront) < 30 ? 6 : 0
            let d = dist + nudge
            let p = CGPoint(x: center.x + d * CGFloat(cos(star.angle)),
                            y: center.y + d * CGFloat(sin(star.angle)))
            // Streak tail while warping in (fades as it settles).
            let streak = (1 - w) * 0.9
            if streak > 0.02 {
                let tail = CGPoint(x: center.x + (d + 40) * CGFloat(cos(star.angle)),
                                   y: center.y + (d + 40) * CGFloat(sin(star.angle)))
                var line = Path(); line.move(to: p); line.addLine(to: tail)
                ctx.stroke(line, with: .color(Theme.accent.opacity(0.4 * streak)), lineWidth: star.size * 0.6)
            }
            let twinkle = 0.6 + 0.4 * sin(t * 2 + star.twinklePhase)
            // Pulse: stars breathe in size as well as brightness.
            let pulse = 1.0 + 0.45 * sin(t * 2.4 + star.twinklePhase * 1.7)
            let sr = star.size * CGFloat(pulse)
            // Soft halo around each star.
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sr*2.2, y: p.y - sr*2.2,
                                            width: sr*4.4, height: sr*4.4)),
                     with: .color(Theme.accent.opacity(0.10 * twinkle * Double(min(w * 1.5, 1)))))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - sr, y: p.y - sr,
                                            width: sr * 2, height: sr * 2)),
                     with: .color(Theme.accent.opacity((0.4 + 0.5 * twinkle) * Double(min(w * 1.5, 1)))))
        }

        // 2. Pulse ripples: concentric rings expanding from the core.
        if ripple > 0 {
            for i in 0..<3 {
                let phase = ripple - Double(i) * 0.22
                if phase <= 0 || phase > 1 { continue }
                let r = CGFloat(easeOut(phase)) * maxR * 0.6
                let fade = (1 - phase) * 0.6
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r*2, height: r*2)),
                           with: .color(Theme.accent.opacity(fade)), lineWidth: 2)
            }
        }

        // 3. Core ignites as a radiant beacon — a bright center with light rays
        //    bursting outward (not plain circles).
        if coreGlow > 0.01 {
            let rayCount = 12
            let rayLen = 46.0 * coreGlow
            let spin = t * 0.3
            for i in 0..<rayCount {
                let a = Double(i) / Double(rayCount) * 2 * .pi + spin
                let inner = 10.0
                let p1 = CGPoint(x: center.x + CGFloat(inner * cos(a)),
                                 y: center.y + CGFloat(inner * sin(a)))
                // Alternate long/short rays for a sparkle-burst look.
                let len = i % 2 == 0 ? 1.0 : 0.55
                let p2b = CGPoint(x: center.x + CGFloat((inner + rayLen * len) * cos(a)),
                                  y: center.y + CGFloat((inner + rayLen * len) * sin(a)))
                var ray2 = Path(); ray2.move(to: p1); ray2.addLine(to: p2b)
                ctx.stroke(ray2, with: .color(Theme.accent.opacity(0.5 * coreGlow)), lineWidth: 1.5)
            }
            // Soft halo + bright core dot.
            let glowR = 26.0 * coreGlow
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - glowR, y: center.y - glowR,
                                            width: glowR*2, height: glowR*2)),
                     with: .color(Theme.accent.opacity(0.12 * coreGlow)))
            let cr = 7.0 * coreGlow * (1 + 0.12 * sin(t * 3))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - cr, y: center.y - cr, width: cr*2, height: cr*2)),
                     with: .color(Theme.accent))
            // White-hot center.
            let hot = cr * 0.45
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - hot, y: center.y - hot, width: hot*2, height: hot*2)),
                     with: .color(.white.opacity(0.9 * coreGlow)))
        }
    }

    private func makeStars(for size: CGSize) -> [Star] {
        let maxR = max(size.width, size.height)
        return (0..<160).map { _ in
            let angle = Double.random(in: 0..<(2 * .pi))
            let settle = CGFloat.random(in: maxR * 0.08 ... maxR * 0.6)
            return Star(angle: angle,
                        startDist: maxR * CGFloat.random(in: 0.7...1.2),
                        settleDist: settle,
                        size: CGFloat.random(in: 0.8...2.6),
                        twinklePhase: Double.random(in: 0..<(2 * .pi)))
        }
    }

    private func easeOut(_ v: Double) -> Double { 1 - pow(1 - min(max(v, 0), 1), 3) }

    // MARK: Sequence

    private func play() {
        t0 = Date()
        // Reduced motion: skip the elaborate sequence, just settle and hand off.
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.4)) {
                warp = 1; coreGlow = 1; nameOpacity = 1; nameBlur = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                Haptics.success()
                withAnimation(.easeIn(duration: 0.3)) { onFinished() }
            }
            return
        }
        // Stars streak in & settle.
        withAnimation(.easeOut(duration: 1.3)) { warp = 1 }
        // Core ignites as stars settle.
        withAnimation(.easeOut(duration: 0.6).delay(0.9)) { coreGlow = 1 }
        // Pulse ripple sweeps outward through the stars.
        withAnimation(.easeOut(duration: 1.4).delay(1.1)) { ripple = 1 }
        // Name resolves.
        withAnimation(.easeOut(duration: 0.8).delay(1.5)) { nameOpacity = 1; nameBlur = 0 }
        withAnimation(.easeInOut(duration: 0.5).delay(1.8)) { finalBloom = 1 }
        withAnimation(.easeInOut(duration: 0.8).delay(2.3)) { finalBloom = 0.4 }
        // Hand off.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            Haptics.success()
            withAnimation(.easeIn(duration: 0.5)) { onFinished() }
        }
    }
}
