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
    let sub: String
    let openPorts: Int
    let icon: String
    let accent: Color
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

    var effectiveZoom: CGFloat { zoom }
    var effectivePan: CGSize { pan }

    // Incremental pan from the gesture surface.
    func applyPan(_ delta: CGSize) {
        pan.width += delta.width
        pan.height += delta.height
    }

    // Incremental zoom, anchored at `anchor` (in the view's coordinate space,
    // origin at center). Keeps the point under the fingers stationary.
    func applyZoom(_ delta: CGFloat, anchor: CGPoint, viewSize: CGSize) {
        let newZoom = min(max(zoom * delta, minZoom), maxZoom)
        let actualDelta = newZoom / zoom
        // Anchor point relative to the view center.
        let ax = anchor.x - viewSize.width / 2
        let ay = anchor.y - viewSize.height / 2
        // Adjust pan so the anchor stays fixed as we scale.
        pan.width = (pan.width - ax) * actualDelta + ax
        pan.height = (pan.height - ay) * actualDelta + ay
        zoom = newZoom
    }

    func reset() {
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

    private var revealDetail: Bool { zoom > 1.4 && !node.sub.isEmpty }

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
                    Text(node.sub).font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    if node.openPorts > 0 {
                        Text("\(node.openPorts) \(node.openPorts == 1 ? "port" : "ports")")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(node.accent)
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
