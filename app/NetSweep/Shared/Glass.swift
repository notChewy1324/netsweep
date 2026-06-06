import SwiftUI

// MARK: - Glass material
// A frosted translucent material look. Uses regularMaterial (more opaque/legible
// than ultraThin) plus a subtle tint and border. All decorative overlays are
// non-interactive so they never intercept taps on the content beneath them.

extension View {
    /// Apply a frosted glass background clipped to a rounded rectangle.
    func glassPanel(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        self
            .background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
            .background(
                // Tint sits BEHIND content (in background, not overlay) and is
                // non-interactive, so it can't block taps.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill((tint ?? Theme.surface).opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke((tint ?? .white).opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false)
            )
    }
}

// A passthrough container (kept so call sites using GlassGroup still compile).
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content }
}
