import SwiftUI

struct NetUtilsView: View {
    @State private var tab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("", selection: $tab) {
                    Text("Subnet").tag(0)
                    Text("MAC Lookup").tag(1)
                }.pickerStyle(.segmented)

                if tab == 0 { SubnetTab() } else { MACTab() }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle("Net Utils")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct SubnetTab: View {
    @State private var ip = "192.168.1.10"
    @State private var cidr = 24.0
    private var result: SubnetResult? { SubnetCalc.compute(ip: ip, cidr: Int(cidr)) }

    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "Input", accent: Theme.amber) {
                VStack(spacing: 10) {
                    TextField("IP address", text: $ip)
                        .font(Theme.mono).foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .keyboardType(.numbersAndPunctuation)
                        .padding(10).background(Theme.surfaceHi).clipShape(RoundedRectangle(cornerRadius: 12))
                    HStack {
                        Text("/\(Int(cidr))").font(Theme.mono).foregroundStyle(Theme.accent).frame(width: 50)
                        Slider(value: $cidr, in: 0...32, step: 1).tint(Theme.amber)
                    }
                }
            }
            if let r = result {
                Panel(title: "Result") {
                    VStack(spacing: 8) {
                        DataRow(key: "network", value: r.network, valueColor: Theme.accent)
                        DataRow(key: "broadcast", value: r.broadcast)
                        DataRow(key: "first host", value: r.firstHost)
                        DataRow(key: "last host", value: r.lastHost)
                        DataRow(key: "netmask", value: r.mask)
                        DataRow(key: "wildcard", value: r.wildcard)
                        DataRow(key: "usable hosts", value: "\(r.hostCount)", valueColor: Theme.accent)
                    }
                }
            } else {
                Text("Enter a valid IPv4 address.")
                    .font(Theme.monoSm).foregroundStyle(Theme.textDim).padding(.top, 20)
            }
        }
    }
}

private struct MACTab: View {
    @State private var mac = ""

    private var vendor: String? { MACVendor.lookup(mac) }
    private var normalized: String? { MACVendor.normalize(mac) }

    var body: some View {
        VStack(spacing: 14) {
            Panel(title: "MAC Lookup", accent: Theme.amber) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Paste a MAC address to identify the device maker. The first 24 bits — the OUI — are assigned to manufacturers by IEEE, so looking them up tells you what company made the network interface.")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                    TextField("e.g. B8:27:EB:12:34:56", text: $mac)
                        .font(Theme.mono).foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10).background(Theme.surfaceHi)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("Tip: grab MACs from your router's client list, a Mac's System Settings → Wi-Fi → Details, or another device's network settings. iOS hides other devices' real MACs from apps for privacy, so they have to be entered by hand.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.textFaint)
                }
            }

            if !mac.isEmpty {
                Panel(title: "Lookup") {
                    VStack(spacing: 8) {
                        if let n = normalized {
                            DataRow(key: "normalized", value: n, valueColor: Theme.textPrimary)
                            DataRow(key: "OUI", value: String(n.prefix(8)), valueColor: Theme.info)
                        } else {
                            DataRow(key: "format", value: "invalid", valueColor: Theme.danger)
                        }
                        DataRow(key: "vendor", value: vendor ?? "unknown / not in table",
                                valueColor: vendor != nil ? Theme.accent : Theme.textDim)
                    }
                }
            }
        }
    }
}
