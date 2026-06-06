import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var page = 0

    var body: some View {
        ZStack {
            ObservatoryCanvas()
            VStack(spacing: 0) {
                TabView(selection: $page) {
                    welcomePage.tag(0)
                    featuresPage.tag(1)
                    permissionPage.tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                pageDots
                bottomButton
            }
            .padding(24)
        }
    }

    private var pageDots: some View {
        HStack(spacing: 8) {
            ForEach(0..<3) { i in
                Circle().fill(i == page ? Theme.accent : Theme.stroke)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, 20)
    }

    @ViewBuilder
    private var bottomButton: some View {
        if page < 2 {
            ActionButton(title: "Continue", systemImage: "arrow.right") {
                withAnimation { page += 1 }
            }
        } else {
            ActionButton(title: "Enable & Start", systemImage: "checkmark.shield") {
                settings.hasPrimedLocalNetwork = true
                settings.hasOnboarded = true
                // The actual iOS Local Network prompt fires on the first scan.
            }
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "scope")
                .font(.system(size: 72)).foregroundStyle(Theme.accent)
            Text(AppInfo.displayName.uppercased())
                .font(.system(.largeTitle, design: .monospaced).weight(.heavy)).tracking(3)
                .foregroundStyle(Theme.textPrimary)
            Text("See every device on your network and whether it's safe — in one tap.")
                .font(Theme.mono).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            Spacer(); Spacer()
        }
    }

    private var featuresPage: some View {
        VStack(alignment: .leading, spacing: 24) {
            Spacer()
            Text("WHAT IT DOES")
                .font(.system(.caption, design: .monospaced).weight(.bold)).tracking(2)
                .foregroundStyle(Theme.textDim)
            feature("dot.radiowaves.left.and.right", "Maps your network",
                    "Finds every device on your Wi-Fi and identifies what it is.")
            feature("checkmark.shield", "Spots problems",
                    "Flags risky open services, weak certificates, and exposed devices.")
            feature("sparkles", "Catches newcomers",
                    "Tells you when a device you've never seen joins your network.")
            feature("wrench.and.screwdriver", "Deep tools",
                    "Port scanning, TLS inspection, DNS lookups, and more — all on tap.")
            Spacer(); Spacer()
        }
    }

    private func feature(_ icon: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundStyle(Theme.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(body).font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
            }
        }
    }

    private var permissionPage: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 64)).foregroundStyle(Theme.info)
            Text("One permission needed")
                .font(.system(.title2, design: .monospaced).weight(.bold))
                .foregroundStyle(Theme.textPrimary)
            Text("To find devices, \(AppInfo.displayName) needs Local Network access. iOS will ask next — tap Allow, or scanning won't find anything.")
                .font(Theme.monoSm).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center)
            Panel {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Everything stays on your device", systemImage: "lock.fill")
                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.accent)
                    Label("No accounts, ads, or tracking", systemImage: "hand.raised.fill")
                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.accent)
                }
            }
            Spacer(); Spacer()
        }
    }
}
