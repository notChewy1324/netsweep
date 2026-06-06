import SwiftUI
import SwiftData

@main
struct NetSweepApp: App {
    @StateObject private var settings = AppSettings()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundScanManager.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
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
    @State private var launchDone = false

    var body: some View {
        ZStack {
            if launchDone {
                Group {
                    if settings.hasOnboarded {
                        NavigationStack { CanvasHomeView() }
                    } else {
                        OnboardingView()
                    }
                }
                .transition(.opacity)
            } else {
                LaunchAnimationView { launchDone = true }
                    .transition(.opacity)
            }
        }
    }
}
