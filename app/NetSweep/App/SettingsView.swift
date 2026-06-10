import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Query private var sessions: [ScanSession]
    @State private var browserLink: PresentedURL?
    @State private var confirmingDeleteAll = false

    // Static URLs for the Developer links. Holding them as constants — rather
    // than constructing inline with force-unwrap — means a malformed string
    // would be a build-time concern, not a tap-time crash.
    private static let developerSiteURL = URL(string: "https://camgarrison.com")
    private static let appSiteURL = URL(string: "https://netsweepapp.com")

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    Panel(title: "Appearance", accent: Theme.accent) {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Appearance", selection: Binding(
                                get: { settings.appearance },
                                set: { settings.appearance = $0; Haptics.selection() }
                            )) {
                                ForEach(Appearance.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text("Choose Light, Dark, or follow your system setting.")
                                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                        }
                    }

                    Panel(title: "Scan Settings", accent: Theme.info) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Intensity")
                                .font(.system(.footnote, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.textDim)
                            Picker("Intensity", selection: Binding(
                                get: { settings.scanIntensity },
                                set: { settings.scanIntensity = $0; Haptics.selection() }
                            )) {
                                ForEach(ScanIntensity.allCases) { Text($0.label).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            Text(settings.scanIntensity.detail)
                                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)

                            Divider().overlay(Theme.stroke)

                            Toggle(isOn: $settings.notifyNewDevices) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("New device alerts")
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Notify when an unrecognized device joins.")
                                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                                }
                            }
                            .tint(Theme.accent)
                            .sensoryFeedback(.selection, trigger: settings.notifyNewDevices)

                            Divider().overlay(Theme.stroke)

                            Toggle(isOn: Binding(
                                get: { settings.backgroundMonitoring },
                                set: { settings.backgroundMonitoring = $0
                                       Haptics.selection()
                                       if $0 { BackgroundScanManager.schedule() }
                                       else { BackgroundScanManager.cancel() } }
                            )) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Background checks")
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Occasionally re-check your Wi-Fi for new devices in the background. iOS controls the timing (often hours apart, never guaranteed) this isn't continuous monitoring.")
                                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                                }
                            }.tint(Theme.accent)
                        }
                    }

                    Panel(title: "About") {
                        VStack(alignment: .leading, spacing: 8) {
                            DataRow(key: "app", value: AppInfo.displayName)
                            DataRow(key: "version", value: "1.0")
                            DataRow(key: "scans stored", value: "\(sessions.count)")
                            Text("\(AppInfo.displayName) is a personal diagnostic tool for the Wi-Fi network you are connected to. It lists the devices on your own network, identifies the services they advertise, and offers informational notes to help you understand and troubleshoot your own gear. It only works on the network you're currently connected to and cannot target devices on any other network. Everything runs on-device — no accounts, ads, or trackers. Three features make outbound requests by necessity: the public-IP lookup (ipwho.is), the speed estimate (Cloudflare), and CVE lookup (NIST NVD), which send only your query, never your scan data.")
                                .font(.footnote).foregroundStyle(Theme.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                        }
                    }

                    Panel(title: "Developer", accent: Theme.info) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Designed & built by Cam Garrison")
                                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            if let url = Self.developerSiteURL {
                                Button {
                                    Haptics.tap()
                                    browserLink = PresentedURL(url: url)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "globe").foregroundStyle(Theme.accent)
                                        Text("camgarrison.com").foregroundStyle(Theme.accent)
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.textDim)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                            if let url = Self.appSiteURL {
                                Button {
                                    Haptics.tap()
                                    browserLink = PresentedURL(url: url)
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "app.badge").foregroundStyle(Theme.accent)
                                        Text("netsweepapp.com").foregroundStyle(Theme.accent)
                                        Spacer()
                                        Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.textDim)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .font(.subheadline)
                    }

                    Panel(title: "Responsible Use", accent: Theme.amber) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("\(AppInfo.displayName) is built for the person who owns or administers a network — it only operates on the Wi-Fi you're currently connected to. Diagnostic tools refuse any target that isn't on that network.")
                                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                            Text("Using \(AppInfo.displayName) on a network you do not own or are not authorized to administer may violate local law and the network's acceptable-use policy.")
                                .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                        }
                    }

                    if !sessions.isEmpty {
                        Panel(title: "Data", accent: Theme.danger) {
                            ActionButton(title: "Delete All Scan History",
                                         systemImage: "trash", color: Theme.danger) {
                                Haptics.tap()
                                confirmingDeleteAll = true
                            }
                        }
                    }
                }
                .padding(16)
                .readableWidth()
            }
            .background(ObservatoryCanvas())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $browserLink) { link in
                SafariSheet(url: link.url).ignoresSafeArea()
            }
            .confirmationDialog("Delete all scan history?",
                                isPresented: $confirmingDeleteAll,
                                titleVisibility: .visible) {
                Button("Delete \(sessions.count) Scan\(sessions.count == 1 ? "" : "s")", role: .destructive) {
                    deleteAllSessions()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes every saved scan from this device.")
            }
        }
        .zoomNavigationRoot()
    }

    private func deleteAllSessions() {
        for s in sessions { context.delete(s) }
        try? context.save()
        Haptics.success()
    }
}
