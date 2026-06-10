import SwiftUI

struct BonjourDetailView: View {
    let service: BonjourService
    @StateObject private var resolver = BonjourResolver()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel(accent: Theme.info) {
                    HStack(spacing: 12) {
                        Image(systemName: service.icon)
                            .font(.title).foregroundStyle(Theme.info)
                            .frame(width: 48, height: 48)
                            .background(Theme.info.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(service.name).font(.system(.headline, design: .monospaced).weight(.bold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(service.friendly).font(Theme.monoSm).foregroundStyle(Theme.info)
                        }
                        Spacer()
                    }
                }

                if resolver.isResolving {
                    Panel {
                        HStack { ProgressView().controlSize(.small).tint(Theme.accent)
                            Text("Resolving service…").font(Theme.monoSm).foregroundStyle(Theme.textDim); Spacer() }
                    }
                } else if let r = resolver.resolved {
                    Panel(title: "Endpoint") {
                        VStack(spacing: 8) {
                            DataRow(key: "service type", value: service.type)
                            if let host = r.host { DataRow(key: "host", value: host, valueColor: Theme.accent) }
                            if let port = r.port { DataRow(key: "port", value: "\(port)", valueColor: Theme.amber) }
                            ForEach(Array(r.addresses.enumerated()), id: \.offset) { _, a in
                                DataRow(key: "address", value: a, valueColor: Theme.accent)
                            }
                            if r.host == nil && r.addresses.isEmpty {
                                Text("Could not resolve a concrete address. The service may have gone offline.")
                                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }

                    if !r.txtRecords.isEmpty {
                        Panel(title: "Metadata (TXT)", accent: Theme.amber) {
                            VStack(spacing: 6) {
                                ForEach(Array(r.txtRecords.enumerated()), id: \.offset) { _, kv in
                                    DataRow(key: kv.0, value: kv.1)
                                }
                            }
                        }
                    }

                    // Deep-scan the resolved host if we have an address.
                    if let ip = r.addresses.first ?? r.host {
                        NavigationLink {
                            DeviceProfileView(ip: ip, hostname: r.host, vendorGuess: service.friendly)
                                .zoomDestination("device-\(ip)")
                        } label: {
                            Panel(accent: Theme.accent) {
                                HStack {
                                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.accent)
                                    Text("Deep scan this device")
                                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Theme.textDim)
                                }
                            }
                        }
                        .zoomSource("device-\(ip)")
                    }
                }
            }
            .padding(16)
            .readableWidth()
        }
        .background(ObservatoryCanvas())
        .navigationTitle(service.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { resolver.resolve(name: service.name, type: service.type) }
        .onDisappear { resolver.cancel() }
    }
}
