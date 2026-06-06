import SwiftUI
import SwiftData

struct NetUtilsView: View {
    @State private var tab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Picker("", selection: $tab) {
                    Text("Subnet").tag(0)
                    Text("MAC Vendor").tag(1)
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
    @State private var pickedIP: String?
    @FocusState private var macFieldFocused: Bool
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]

    private var vendor: String? { MACVendor.lookup(mac) }
    private var normalized: String? { MACVendor.normalize(mac) }
    private var devices: [DeviceRecord] {
        guard let s = sessions.first else { return [] }
        return s.devices.sorted { (NetInfo.ipToUInt32($0.ip) ?? 0) < (NetInfo.ipToUInt32($1.ip) ?? 0) }
    }

    var body: some View {
        VStack(spacing: 14) {
            if !devices.isEmpty {
                Panel(title: "From Your Network", accent: Theme.info) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Pick a discovered device, then paste its MAC from your router's client list to identify the maker.")
                            .font(.footnote).foregroundStyle(Theme.textDim)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(devices) { d in
                                    Button {
                                        pickedIP = d.ip; Haptics.tap(); macFieldFocused = true
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text(d.hostname ?? d.ip.split(separator: ".").last.map(String.init) ?? d.ip)
                                                .font(.system(.caption, design: .monospaced).weight(.bold))
                                                .foregroundStyle(pickedIP == d.ip ? Theme.canvasTop : Theme.textPrimary)
                                            Text(d.ip).font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(pickedIP == d.ip ? Theme.canvasTop.opacity(0.7) : Theme.textDim)
                                        }
                                        .frame(width: 92).padding(.vertical, 8)
                                        .background(pickedIP == d.ip ? Theme.info : Theme.surfaceHi,
                                                    in: .rect(cornerRadius: 8))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        if let ip = pickedIP {
                            DataRow(key: "selected", value: ip, valueColor: Theme.info)
                        }
                    }
                }
            }

            Panel(title: "MAC Address", accent: Theme.amber) {
                VStack(spacing: 10) {
                    TextField(pickedIP != nil ? "Paste MAC for \(pickedIP!)" : "e.g. B8:27:EB:12:34:56", text: $mac)
                        .font(Theme.mono).foregroundStyle(Theme.textPrimary)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .focused($macFieldFocused)
                        .padding(10).background(Theme.surfaceHi).clipShape(RoundedRectangle(cornerRadius: 12))
                    Text("iOS hides other devices' real MAC addresses from apps, so paste one from your router's client list (match it to the IP above) to identify its maker.")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !mac.isEmpty {
                Panel(title: "Lookup") {
                    VStack(spacing: 8) {
                        if let n = normalized { DataRow(key: "normalized", value: n) }
                        DataRow(key: "vendor", value: vendor ?? "unknown / not in table",
                                valueColor: vendor != nil ? Theme.accent : Theme.textDim)
                    }
                }
            }
        }
    }
}
