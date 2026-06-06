import SwiftUI

// MARK: - Animated logo text
// The app name with a subtle premium animation: a soft glow that breathes and a
// light shimmer that sweeps across the letters every few seconds. Font size
// stays fixed — only light/color moves.

struct AnimatedLogoText: View {
    let text: String
    var font: Font = .headline.weight(.semibold)

    @State private var shimmer = false
    @State private var glow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(Theme.textPrimary)
            // Breathing glow.
            .shadow(color: Theme.accent.opacity(glow ? 0.55 : 0.15),
                    radius: glow ? 10 : 4)
            // Shimmer sweep: a moving highlight masked to the text, traveling
            // precisely from the first letter (N) to the last (p).
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    let band = w * 0.42
                    // The gradient's BRIGHT POINT sits at the band's center, so we
                    // position by where we want that center to be. Travel the center
                    // from x=0 (the N) to x=w (the p). offset = center - band/2.
                    let center = shimmer ? w : 0
                    LinearGradient(
                        colors: [.clear, Theme.accent.opacity(0.95), .clear],
                        startPoint: .leading, endPoint: .trailing)
                        .frame(width: band)
                        .offset(x: center - band / 2)
                        .blendMode(.screen)
                }
                .mask(Text(text).font(font))
                .allowsHitTesting(false)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                    glow = true
                }
                // A single deliberate sweep N→p, then a pause before repeating —
                // feels intentional rather than constantly shimmering.
                withAnimation(
                    .easeInOut(duration: 1.6)
                    .delay(0.8)
                    .repeatForever(autoreverses: false)
                ) {
                    shimmer = true
                }
            }
    }
}
