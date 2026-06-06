import SwiftUI
import SwiftData

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.modelContext) private var context
    @Query private var sessions: [ScanSession]

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
                                    Text("New-device alerts")
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("Notify when an unrecognized device joins.")
                                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                                }
                            }.tint(Theme.accent)

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
                                    Text("Occasionally re-check your Wi-Fi for new devices in the background. iOS controls the timing (often hours apart, never guaranteed) — this isn't continuous monitoring.")
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
                            Text("\(AppInfo.displayName) is an on-device network observatory: it maps the devices on your network, surfaces open ports and risk notes, and helps you keep an eye on what's connected. Everything runs locally — no accounts, ads, or trackers. Three features make outbound requests by necessity: the public-IP lookup (ipwho.is), the speed estimate (Cloudflare), and CVE lookup (NIST NVD), which send only the query, never your scan data.")
                                .font(.footnote).foregroundStyle(Theme.textDim)
                                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                        }
                    }

                    Panel(title: "Developer", accent: Theme.info) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Designed & built by Cam Garrison")
                                .font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                            Link(destination: URL(string: "https://camgarrison.com")!) {
                                HStack(spacing: 8) {
                                    Image(systemName: "globe").foregroundStyle(Theme.accent)
                                    Text("camgarrison.com").foregroundStyle(Theme.accent)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.textDim)
                                }
                            }
                            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                            Link(destination: URL(string: "https://github.com/notchewy1324")!) {
                                HStack(spacing: 8) {
                                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                                        .foregroundStyle(Theme.accent)
                                    Text("github.com/notchewy1324").foregroundStyle(Theme.accent)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.textDim)
                                }
                            }
                            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                        }
                        .font(.subheadline)
                    }

                    Panel(title: "Responsible Use", accent: Theme.amber) {
                        Text("Only scan networks and devices you own or have explicit authorization to test. Unauthorized scanning may violate law and acceptable-use policies.")
                            .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                    }

                    if !sessions.isEmpty {
                        Panel(title: "Data", accent: Theme.danger) {
                            ActionButton(title: "Delete All Scan History",
                                         systemImage: "trash", color: Theme.danger) {
                                for s in sessions { context.delete(s) }
                                try? context.save()
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
        }
    }
}
