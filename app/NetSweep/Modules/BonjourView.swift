import SwiftUI

struct BonjourView: View {
    @StateObject private var browser = BonjourBrowser()

    private var grouped: [(String, [BonjourService])] {
        Dictionary(grouping: browser.services, by: { $0.friendly })
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                CellularNote(feature: "Bonjour discovery")
                Panel(title: "Service Discovery", accent: Theme.info) {
                    VStack(spacing: 10) {
                        Text("Passively listens for services advertised on your local network via mDNS/Bonjour.")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(Theme.textDim)
                        HStack {
                            Pill(text: browser.isBrowsing ? "Listening" : "Idle",
                                 color: browser.isBrowsing ? Theme.accent : Theme.textDim)
                            Pill(text: "\(browser.services.count) found", color: Theme.info)
                            Spacer()
                        }
                        if browser.isBrowsing {
                            ActionButton(title: "Stop", systemImage: "stop.fill", color: Theme.danger) {
                                browser.stop()
                            }
                        } else {
                            ActionButton(title: "Start Listening", systemImage: "antenna.radiowaves.left.and.right", color: Theme.info) {
                                browser.start()
                            }
                        }
                    }
                }

                if grouped.isEmpty {
                    Panel(accent: Theme.info) {
                        VStack(spacing: 10) {
                            if browser.isBrowsing {
                                ProgressView().tint(Theme.info)
                                Text("Listening for services…")
                                    .font(.subheadline).foregroundStyle(Theme.textDim)
                                Text("Discoverable devices like printers, speakers, TVs, and file shares will appear here as they announce themselves.")
                                    .font(.footnote).foregroundStyle(Theme.textFaint)
                                    .multilineTextAlignment(.center)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.largeTitle).foregroundStyle(Theme.textFaint)
                                Text("Not listening")
                                    .font(.subheadline).foregroundStyle(Theme.textDim)
                                Text("Tap Start Listening to discover services on your network.")
                                    .font(.footnote).foregroundStyle(Theme.textFaint)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                    }
                }

                ForEach(grouped, id: \.0) { type, services in
                    Panel(title: nil, accent: Theme.info) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: services.first?.icon ?? "questionmark.circle")
                                    .foregroundStyle(Theme.info)
                                Text(type)
                                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Pill(text: "\(services.count)", color: Theme.info)
                            }
                            ForEach(services) { svc in
                                NavigationLink {
                                    BonjourDetailView(service: svc)
                                } label: {
                                    HStack {
                                        Text(svc.name)
                                            .font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                                            .lineLimit(1)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.caption2).foregroundStyle(Theme.textDim)
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Bonjour")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { browser.start() }
        .onDisappear { browser.stop() }
    }
}
