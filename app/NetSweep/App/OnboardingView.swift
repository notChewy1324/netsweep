import SwiftUI

// MARK: - Onboarding
// A four-page intro that establishes scope (your own home network only),
// shows the spatial map + analytics + customizable toolkit, prompts for the
// Local Network permission, and finally requires an explicit affirmation
// that the user is the owner/administrator of the network they intend to
// scan. The affirmation gate is the App-Review-required "more than a
// description-only disclaimer" surface.

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var page = 0
    @State private var responsibleUseAccepted = false

    var body: some View {
        ZStack {
            ObservatoryCanvas()
            // A faint accent-tinted wash that subtly shifts between pages —
            // makes the carousel feel like one continuous surface rather
            // than three disconnected slides.
            RadialGradient(colors: [pageAccent.opacity(0.12), .clear],
                           center: .center, startRadius: 0, endRadius: 360)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: page)
                .allowsHitTesting(false)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    permissionPage.tag(2)
                    responsibleUsePage.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                bottomButton
            }
            .padding(24)
        }
    }

    private var pageAccent: Color {
        switch page {
        case 0: return Theme.accent
        case 1: return Theme.purple
        case 2: return Theme.info
        default: return Theme.amber
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<4) { i in
                Capsule()
                    .fill(i == page ? pageAccent : Theme.stroke)
                    .frame(width: i == page ? 22 : 7, height: 7)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: page)
            }
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var bottomButton: some View {
        if page < 3 {
            ActionButton(title: "Continue", systemImage: "arrow.right") {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                    page += 1
                }
            }
        } else {
            ActionButton(title: responsibleUseAccepted ? "I Agree & Start" : "Confirm Above To Continue",
                         systemImage: "checkmark.shield",
                         color: responsibleUseAccepted ? Theme.accent : Theme.textDim) {
                guard responsibleUseAccepted else { return }
                settings.hasPrimedLocalNetwork = true
                settings.hasAcceptedResponsibleUse = true
                settings.hasOnboarded = true
                // The actual iOS Local Network prompt fires on the first scan.
            }
            .disabled(!responsibleUseAccepted)
            .opacity(responsibleUseAccepted ? 1 : 0.6)
        }
    }

    // MARK: - Page 1: Welcome

    private var welcomePage: some View {
        VStack(spacing: 22) {
            Spacer()
            // Reuses the animated brand sigil from the home canvas — gives
            // the welcome screen the same living presence as the app proper.
            SonarSigil(color: Theme.accent, size: 96)
                .frame(height: 110)
            BrandWordmark(AppInfo.displayName, accent: Theme.accent, splitIndex: 3)
                .font(.system(.largeTitle, design: .monospaced).weight(.heavy))
            VStack(spacing: 8) {
                Text("Understand your own home Wi-Fi.")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("A personal diagnostic tool — only for the network you're connected to.")
                    .font(Theme.monoSm)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)
            Spacer(); Spacer()
        }
    }

    // MARK: - Page 2: Features

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 4) {
                Text("WHAT YOU GET")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Theme.textDim)
                Text("Built for the curious.")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            featureCard(
                icon: "point.3.connected.trianglepath.dotted",
                accent: Theme.accent,
                title: "Spatial map",
                detail: "Every device on your own Wi-Fi as a node you can drag, tap, and inspect.")
            featureCard(
                icon: "shield.lefthalf.filled",
                accent: Theme.good,
                title: "Network overview",
                detail: "New devices, items to review, and recent activity on your home network — at a glance.")
            featureCard(
                icon: "chart.line.uptrend.xyaxis",
                accent: Theme.purple,
                title: "Trends & compare",
                detail: "Scrub history charts. Diff two scans of your own network to see exactly what changed.")
            featureCard(
                icon: "slider.horizontal.3",
                accent: Theme.amber,
                title: "Your toolkit",
                detail: "Service diagnostics, TLS inspector, Bonjour, DNS — all scoped to your Wi-Fi.")
            Spacer(minLength: 0)
        }
    }

    private func featureCard(icon: String, accent: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.16), in: .rect(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Page 3: Permission + Privacy

    private var permissionPage: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.info.opacity(0.12))
                    .frame(width: 130, height: 130)
                Circle()
                    .stroke(Theme.info.opacity(0.35), lineWidth: 1)
                    .frame(width: 130, height: 130)
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.info)
            }
            VStack(spacing: 10) {
                Text("One permission needed")
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("To find devices on your own Wi-Fi, \(AppInfo.displayName) needs Local Network access. iOS will ask on your first scan — tap Allow, or scanning won't find anything. This permission only covers the network you're connected to.")
                    .font(Theme.monoSm)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            Panel(title: "Promise", accent: Theme.accent) {
                VStack(alignment: .leading, spacing: 10) {
                    promiseRow(icon: "lock.fill", text: "Everything stays on your device")
                    promiseRow(icon: "hand.raised.fill", text: "No accounts, ads, or tracking")
                    promiseRow(icon: "network.slash", text: "Nothing sent off-device without your tap")
                }
            }
            Spacer()
        }
    }

    private func promiseRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            Text(text)
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Page 4: Responsible Use affirmation
    // Apple's 1.1.6 guideline requires more than a description-only
    // disclaimer for network tools. This page surfaces the rule clearly,
    // requires an explicit toggle, and only then unlocks the Start button.

    private var responsibleUsePage: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.amber.opacity(0.12))
                    .frame(width: 130, height: 130)
                Circle()
                    .stroke(Theme.amber.opacity(0.35), lineWidth: 1)
                    .frame(width: 130, height: 130)
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundStyle(Theme.amber)
            }
            VStack(spacing: 10) {
                Text("For your own network")
                    .font(.system(.title2, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                Text("\(AppInfo.displayName) is designed for the owner or administrator of a network to understand their own gear. It only works on the Wi-Fi you're currently connected to, and the diagnostic tools refuse any target that isn't on that network.")
                    .font(Theme.monoSm)
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
            }
            Panel(title: "Please confirm", accent: Theme.amber) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Using this app on a network you do not own or are not authorized to administer may violate local law and the network's acceptable-use policy.")
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Theme.textDim)
                    Toggle(isOn: $responsibleUseAccepted) {
                        Text("I am the owner or authorized administrator of the network I'll be scanning, and I'll only use \(AppInfo.displayName) on networks I'm allowed to.")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                    .sensoryFeedback(.selection, trigger: responsibleUseAccepted)
                }
            }
            Spacer()
        }
    }
}
