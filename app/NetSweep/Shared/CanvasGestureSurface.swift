import SwiftUI
import UIKit

// MARK: - Canvas gesture surface (UIKit-backed)
// SwiftUI's gesture composition for simultaneous pan + pinch on a free canvas is
// unreliable — the drag and magnify fight for the touch sequence. UIKit's
// recognizers are purpose-built to run together with proper multitouch
// arbitration, so we host a transparent UIView with real pan + pinch
// recognizers and report deltas back to SwiftUI.
//
// Pan reports incremental translation; pinch reports incremental scale, around
// the pinch midpoint so zoom feels anchored to the fingers.

struct CanvasGestureSurface: UIViewRepresentable {
    // Live deltas during a gesture.
    var onPanChanged: (CGSize) -> Void
    // Pan ended: receives velocity in pt/sec so callers can apply inertia.
    var onPanEnded: (CGPoint) -> Void
    var onZoomChanged: (CGFloat, CGPoint) -> Void
    var onZoomEnded: () -> Void
    // Discrete zoom shortcuts. All carry the tap location (or two-finger
    // centroid) so the caller can anchor the zoom under the fingers.
    var onDoubleTap: (CGPoint) -> Void
    var onTwoFingerTap: (CGPoint) -> Void
    var onTwoFingerDoubleTap: (CGPoint) -> Void

    func makeUIView(context: Context) -> UIView {
        let v = TouchView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 2
        pan.delegate = context.coordinator

        let pinch = UIPinchGestureRecognizer(target: context.coordinator,
                                             action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator

        let doubleTap = UITapGestureRecognizer(target: context.coordinator,
                                               action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        doubleTap.delegate = context.coordinator

        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator,
                                                  action: #selector(Coordinator.handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        twoFingerTap.delegate = context.coordinator

        let twoFingerDoubleTap = UITapGestureRecognizer(target: context.coordinator,
                                                        action: #selector(Coordinator.handleTwoFingerDoubleTap(_:)))
        twoFingerDoubleTap.numberOfTapsRequired = 2
        twoFingerDoubleTap.numberOfTouchesRequired = 2
        twoFingerDoubleTap.delegate = context.coordinator

        // Without this, a two-finger double-tap (reset) would also fire a
        // two-finger single-tap (zoom-out) en route — making reset look like
        // "zoom out, then zoom out, then recenter".
        twoFingerTap.require(toFail: twoFingerDoubleTap)

        v.addGestureRecognizer(pan)
        v.addGestureRecognizer(pinch)
        v.addGestureRecognizer(doubleTap)
        v.addGestureRecognizer(twoFingerTap)
        v.addGestureRecognizer(twoFingerDoubleTap)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasGestureSurface
        private var lastPan: CGPoint = .zero
        private var lastScale: CGFloat = 1.0

        init(_ parent: CanvasGestureSurface) { self.parent = parent }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            let t = g.translation(in: g.view)
            switch g.state {
            case .began:
                lastPan = .zero
            case .changed:
                let dx = t.x - lastPan.x
                let dy = t.y - lastPan.y
                lastPan = t
                parent.onPanChanged(CGSize(width: dx, height: dy))
            case .ended, .cancelled, .failed:
                let v = g.velocity(in: g.view)
                parent.onPanEnded(v)
            default: break
            }
        }

        @objc func handleDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            parent.onDoubleTap(g.location(in: v))
        }

        @objc func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            parent.onTwoFingerTap(g.location(in: v))
        }

        @objc func handleTwoFingerDoubleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let v = g.view else { return }
            parent.onTwoFingerDoubleTap(g.location(in: v))
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            switch g.state {
            case .began:
                lastScale = 1.0
            case .changed:
                let delta = g.scale / lastScale
                lastScale = g.scale
                let anchor = g.location(in: g.view)
                parent.onZoomChanged(delta, anchor)
            case .ended, .cancelled, .failed:
                parent.onZoomEnded()
            default: break
            }
        }

        // Critical: let pan + pinch run at the same time.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }

    // A view that only intercepts multi-touch canvas gestures; single taps on
    // nodes (handled by SwiftUI above this layer) still pass through because
    // this sits BEHIND the nodes in the ZStack.
    final class TouchView: UIView {}
}
