import SwiftUI
import SwiftData

@main
struct NetSweepApp: App {
    @StateObject private var settings = AppSettings()
    // Lifted from CanvasHomeView so the scanning state is observable
    // app-wide — the screen-edge glow at RootView reads `isScanning` and
    // renders above every screen (home, pushed views, the tools panel).
    @StateObject private var service = NetworkScanService()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundScanManager.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(service)
                .preferredColorScheme(settings.appearance.colorScheme)
                .tint(Theme.accent)
        }
        .modelContainer(for: [ScanSession.self, DeviceRecord.self, Finding.self, DeviceTag.self, ConnectionTest.self])
        .onChange(of: scenePhase) { _, phase in
            // When backgrounding, schedule the next opportunistic check if the
            // user has enabled background monitoring.
            if phase == .background && settings.backgroundMonitoring {
                BackgroundScanManager.schedule()
            }
        }
    }
}

// Routes between launch animation, onboarding, and the main app.
struct RootView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var service: NetworkScanService
    @State private var launchDone = false
    // Decoupled from `service.isScanning` so the glow's visibility and its
    // trim progress can be updated in the same .onChange block — preventing
    // a one-frame flash where the body renders the glow at introProgress=1
    // before the handler gets a chance to reset it to 0.
    @State private var glowVisible = false
    @State private var glowIntro: Double = 0

    var body: some View {
        ZStack {
            if launchDone {
                Group {
                    if settings.hasOnboarded {
                        NavigationStack { CanvasHomeView() }
                            .zoomNavigationRoot()
                    } else {
                        OnboardingView()
                    }
                }
                .transition(.opacity)
            } else {
                LaunchAnimationView { launchDone = true }
                    .transition(.opacity)
            }

            // Scanning glow lives at the root so it draws above every
            // pushed view, the tools panel, and the canvas. (Sheets render
            // at the window level so they will sit on top — a deliberate
            // limitation of SwiftUI's sheet model.)
            if glowVisible {
                ScreenEdgeScanGlow(introProgress: glowIntro)
                    // .identity on insertion so the intro fade animation
                    // (driven by glowIntro) is the only entry visual,
                    // not a duplicate opacity crossfade on top.
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: glowVisible)
        .onChange(of: service.isScanning) { _, isScanning in
            if isScanning {
                // Mount the glow at 0 opacity in this tick, then defer the
                // fade-in to the next runloop pass so SwiftUI doesn't
                // batch the two writes and skip the animation.
                glowIntro = 0
                glowVisible = true
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.4)) {
                        glowIntro = 1
                    }
                }
            } else {
                glowVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    glowIntro = 0
                }
            }
        }
    }
}
