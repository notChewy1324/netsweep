import SwiftUI

// MARK: - Brand kit — sonar sigil + two-tone wordmark + status pulse
// The home-screen identity reads as a command-center instrument rather than
// a marketing logotype. Three small pieces compose it:
//
//   SonarSigil   — three concentric rings ripple out of a center dot,
//                  tinted by the surrounding mood.
//   BrandWordmark — "NETSWEEP" in monospaced heavy, the prefix in primary
//                  text, the suffix in accent. A thin vertical scan-line
//                  drifts across the letters every couple of seconds.
//   StatusPulse  — a tiny dot that breathes while a scan is running.

// MARK: Sigil

struct SonarSigil: View {
    var color: Color = Theme.accent
    var size: CGFloat = 30

    @State private var t0 = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSince(t0)
            Canvas { ctx, sz in
                let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
                let maxR = min(sz.width, sz.height) / 2 - 1
                // Three rings staggered by 1/3 of the cycle so something is
                // always expanding outward; older rings fade as they grow.
                for i in 0..<3 {
                    let phase = (t / 2.0 + Double(i) / 3.0).truncatingRemainder(dividingBy: 1.0)
                    let r = maxR * CGFloat(phase)
                    let alpha = 1 - phase
                    ctx.stroke(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r,
                                                      width: r * 2, height: r * 2)),
                               with: .color(color.opacity(alpha * 0.75)),
                               lineWidth: 1.0)
                }
                // Soft halo + breathing dot.
                let dotPulse = 1.0 + 0.18 * sin(t * 3)
                let haloR = sz.width * 0.32
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - haloR, y: center.y - haloR,
                                                 width: haloR * 2, height: haloR * 2)),
                         with: .color(color.opacity(0.20)))
                let dotR: CGFloat = 3 * CGFloat(dotPulse)
                ctx.fill(Path(ellipseIn: CGRect(x: center.x - dotR, y: center.y - dotR,
                                                 width: dotR * 2, height: dotR * 2)),
                         with: .color(color))
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: Wordmark

struct BrandWordmark: View {
    let text: String
    var accent: Color
    /// Letters before this index render in primary; the rest render in accent.
    var splitIndex: Int
    var fontSize: CGFloat

    @State private var scan: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ text: String,
         accent: Color = Theme.accent,
         splitIndex: Int = 3,
         fontSize: CGFloat = 20) {
        self.text = text
        self.accent = accent
        self.splitIndex = max(0, min(splitIndex, text.count))
        self.fontSize = fontSize
    }

    private var leading: String  { String(text.uppercased().prefix(splitIndex)) }
    private var trailing: String { String(text.uppercased().dropFirst(splitIndex)) }
    private var font: Font { .system(size: fontSize, weight: .heavy, design: .monospaced) }

    var body: some View {
        wordmark
            .shadow(color: accent.opacity(0.45), radius: 8)
            .overlay(scanCursor)
            .onAppear {
                guard !reduceMotion else { return }
                // A single deliberate sweep, then pause, then repeat. Not a
                // constant shimmer — feels intentional rather than busy.
                withAnimation(.easeInOut(duration: 1.6)
                                .delay(0.8)
                                .repeatForever(autoreverses: false)) {
                    scan = 1
                }
            }
    }

    private var wordmark: some View {
        HStack(spacing: 0) {
            Text(leading).foregroundStyle(Theme.textPrimary)
            Text(trailing).foregroundStyle(accent)
        }
        .font(font)
        .tracking(2)
    }

    // A narrow vertical highlight band glides across the wordmark, masked by
    // the letters themselves so it brightens letters as it passes.
    private var scanCursor: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let head = CGFloat(scan) * (w + 40) - 20
            LinearGradient(colors: [.clear, accent.opacity(0.95), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 32, height: geo.size.height + 8)
                .offset(x: head - 16, y: -4)
                .blendMode(.screen)
        }
        .mask(wordmark)
        .allowsHitTesting(false)
    }
}

// MARK: Status pulse

struct StatusPulse: View {
    var color: Color
    var isActive: Bool
    @State private var phase: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .scaleEffect(isActive ? 1.0 + 0.6 * phase : 1.0)
            .opacity(isActive ? 1.0 - 0.35 * phase : 1.0)
            .shadow(color: color.opacity(0.7), radius: isActive ? 3 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    phase = 1
                }
            }
            .accessibilityHidden(true)
    }
}
