import SwiftUI
import UIKit

// MARK: - Design System — "The Observatory"
// A calm, deep, moody command-center aesthetic. One dark canvas, light used as
// the accent (glow = magic), depth via soft shadows rather than hard borders.
// Calm at rest; delight on interaction.

enum Theme {
    // Dynamic color helper: resolves dark vs light per the active interface style.
    private static func dyn(_ dark: (Double, Double, Double), _ light: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { t in
            let c = t.userInterfaceStyle == .light ? light : dark
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    // Canvas: deep observatory at night / soft daylight observatory.
    static let canvasTop    = dyn((0.04, 0.05, 0.07), (0.94, 0.95, 0.97))
    static let canvasBottom = dyn((0.07, 0.07, 0.10), (0.88, 0.90, 0.94))

    // Surfaces float on the canvas.
    static let surface   = dyn((0.10, 0.11, 0.14), (1.00, 1.00, 1.00))
    static let surfaceHi = dyn((0.14, 0.15, 0.19), (0.93, 0.94, 0.96))

    // Primary accent: instrument-backlight cyan-teal (a touch deeper in light).
    static let accent     = dyn((0.36, 0.85, 0.86), (0.10, 0.55, 0.58))
    static let accentSoft = accent.opacity(0.5)

    // Status — only appears when it means something.
    static let good   = dyn((0.40, 0.86, 0.62), (0.13, 0.62, 0.40))
    static let amber  = dyn((0.98, 0.74, 0.36), (0.80, 0.52, 0.10))
    static let danger = dyn((0.98, 0.45, 0.45), (0.83, 0.20, 0.20))
    static let info   = dyn((0.46, 0.68, 0.98), (0.10, 0.45, 0.85))

    // Text.
    static let textPrimary = dyn((0.92, 0.94, 0.96), (0.10, 0.12, 0.16))
    static let textDim     = dyn((0.58, 0.62, 0.70), (0.40, 0.44, 0.52))
    static let textFaint   = dyn((0.40, 0.44, 0.52), (0.62, 0.66, 0.72))

    // Legacy aliases (so existing screens keep compiling).
    static let bg = canvasTop
    static let stroke = dyn((1, 1, 1), (0, 0, 0)).opacity(0.08)
    static let purple = dyn((0.66, 0.58, 0.98), (0.42, 0.32, 0.80))
    static let cyan = accent
    static let pink = dyn((0.96, 0.55, 0.72), (0.82, 0.25, 0.50))
    static let silver = dyn((0.70, 0.74, 0.80), (0.45, 0.50, 0.56))

    // Typography: clean system font; monospace only for technical data.
    static let mono   = Font.system(.body, design: .monospaced)
    static let monoSm = Font.system(.footnote, design: .monospaced)
    static let monoLg = Font.system(.title3, design: .monospaced)
}

// MARK: - The canvas (use as the root background of every screen)

struct ObservatoryCanvas: View {
    var body: some View {
        LinearGradient(colors: [Theme.canvasTop, Theme.canvasBottom],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

// MARK: - Card — depth through light & shadow, not borders

struct Panel<Content: View>: View {
    var title: String? = nil
    var accent: Color = Theme.accent
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                Text(title.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.5)
                    .foregroundStyle(Theme.textDim)
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.surface)
                // Faint light catching the top edge — objects under dim lighting.
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(
                            LinearGradient(colors: [Theme.stroke, .clear],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
    }
}

// MARK: - Key/value row (value monospaced for technical data)

struct DataRow: View {
    let key: String
    let value: String
    var valueColor: Color = Theme.textPrimary
    var body: some View {
        HStack(alignment: .top) {
            Text(key).font(.subheadline).foregroundStyle(Theme.textDim)
            Spacer(minLength: 12)
            Text(value).font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}

// MARK: - Soft status pill

struct Pill: View {
    let text: String
    var color: Color = Theme.accent
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - Primary action — glow blooms on press

struct ActionButton: View {
    let title: String
    var systemImage: String? = nil
    var color: Color = Theme.accent
    var running: Bool = false
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button {
            Haptics.tap(); action()
        } label: {
            HStack(spacing: 8) {
                if running {
                    ProgressView().controlSize(.small).tint(Theme.canvasTop)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title).font(.body.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(running ? color.opacity(0.5) : color)
            )
            .foregroundStyle(Theme.canvasTop)
            .shadow(color: color.opacity(pressed ? 0.7 : 0.4), radius: pressed ? 20 : 12, y: 4)
            .scaleEffect(pressed ? 0.98 : 1)
        }
        .disabled(running)
        .simultaneousGesture(DragGesture(minimumDistance: 0)
            .onChanged { _ in withAnimation(.easeOut(duration: 0.15)) { pressed = true } }
            .onEnded { _ in withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { pressed = false } })
    }
}

// MARK: - Module row (Tools)

struct ModuleCard: View {
    let title: String, subtitle: String, icon: String, accent: Color
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(accent)
                .frame(width: 40, height: 40)
                .background(accent.opacity(0.14), in: .rect(cornerRadius: 11, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Readable width (iPad)

struct ReadableWidth: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: 700).frame(maxWidth: .infinity)
    }
}
extension View {
    func readableWidth() -> some View { modifier(ReadableWidth()) }
}

// MARK: - Glow modifier
// A soft colored glow used by map node badges. (Previously lived in the old
// SciFiFX file; kept here as it's still used by the network map.)
extension View {
    func glow(_ color: Color, radius: CGFloat = 6) -> some View {
        self.shadow(color: color.opacity(0.7), radius: radius)
            .shadow(color: color.opacity(0.4), radius: radius * 1.6)
    }
}

// MARK: - Press style
// A subtle tactile "give" on press — the kind of micro-interaction that makes
// buttons feel physical and considered. Scales down slightly and dims, with a
// spring return. Respects reduce-motion implicitly (the spring is tiny).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.96
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension View {
    /// Apply the tactile press style to any button.
    func pressable(scale: CGFloat = 0.96) -> some View {
        self.buttonStyle(PressableStyle(scale: scale))
    }
}
