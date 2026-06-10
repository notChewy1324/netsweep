import SwiftUI
import SwiftData

struct PortScannerView: View {
    @StateObject private var scanner = PortScanner()
    @State private var target = ""

    // Devices from the most recent scan, to pick a target quickly.
    @Query(sort: \ScanSession.date, order: .reverse) private var sessions: [ScanSession]
    private var discovered: [DeviceRecord] {
        guard let latest = sessions.first else { return [] }
        return latest.devices.sorted {
            (NetInfo.ipToUInt32($0.ip) ?? 0) < (NetInfo.ipToUInt32($1.ip) ?? 0)
        }
    }

    private var ports: [UInt16] { PortSets.common }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left").font(.headline)
                            .foregroundStyle(Theme.accent)
                            .padding(8).background(Theme.surface, in: Circle())
                    }
                    Text("Service Diagnostics").font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                }
                scopeNotice
                if !discovered.isEmpty { devicePicker }
                Panel(title: "Device On Your Network") {
                    VStack(spacing: 10) {
                        TextField("local IP (e.g. 192.168.1.x)", text: $target)
                            .font(Theme.mono)
                            .foregroundStyle(Theme.textPrimary)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(10)
                            .background(Theme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        DataRow(key: "services checked", value: "\(ports.count) common ports", valueColor: Theme.textDim)

                        if scanner.isScanning {
                            ProgressView(value: scanner.progress).tint(Theme.amber)
                            ActionButton(title: "Stop", systemImage: "stop.fill", color: Theme.danger) {
                                scanner.cancel()
                            }
                        } else {
                            ActionButton(title: "Check Services", systemImage: "stethoscope", color: Theme.amber) {
                                let t = target.trimmingCharacters(in: .whitespaces)
                                guard !t.isEmpty else { return }
                                scanner.scan(host: t, ports: ports)
                            }
                        }

                        if let msg = scanner.scopeError {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.danger)
                                Text(msg)
                                    .font(.system(.footnote, design: .monospaced))
                                    .foregroundStyle(Theme.danger)
                                Spacer(minLength: 0)
                            }
                            .padding(10)
                            .background(Theme.danger.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }

                if !scanner.open.isEmpty {
                    Panel(title: "Reachable Services · \(scanner.open.count)", accent: Theme.amber) {
                        VStack(spacing: 0) {
                            ForEach(scanner.open) { r in
                                VStack(spacing: 4) {
                                    HStack {
                                        Text("\(r.port)")
                                            .font(.system(.subheadline, design: .monospaced).weight(.bold))
                                            .foregroundStyle(Theme.amber)
                                            .frame(width: 56, alignment: .leading)
                                        Text(r.service).font(Theme.monoSm).foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Text(String(format: "%.0f ms", r.rttMs))
                                            .font(Theme.monoSm).foregroundStyle(Theme.textDim)
                                    }
                                    if let banner = r.banner {
                                        HStack {
                                            Image(systemName: "tag.fill")
                                                .font(.system(.caption2)).foregroundStyle(Theme.info)
                                            Text(banner)
                                                .font(.system(.footnote, design: .monospaced))
                                                .foregroundStyle(Theme.info)
                                                .lineLimit(1).textSelection(.enabled)
                                            Spacer()
                                        }
                                        .padding(.leading, 56)
                                    }
                                }
                                .padding(.vertical, 8)
                                if r.id != scanner.open.last?.id { Divider().overlay(Theme.stroke) }
                            }
                        }
                    }
                } else if !scanner.isScanning && scanner.progress > 0 {
                    Text("No reachable services found on that device.")
                        .font(Theme.monoSm).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity).padding(.vertical, 30)
                }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .toolbar(.hidden, for: .navigationBar)
        // Edge-swipe-back: attach the gesture to a narrow 16-pt strip at the
        // leading edge instead of the whole view. Previously the gesture lived
        // on the outer ScrollView and stole horizontal pans from the inner
        // "Discovered Devices" picker — moving it to an edge-only overlay
        // means inner ScrollViews never compete for the touch.
        .overlay(alignment: .leading) {
            Color.clear
                .frame(width: 16)
                .contentShape(Rectangle())
                .highPriorityGesture(
                    DragGesture(minimumDistance: 20)
                        .onEnded { value in
                            if value.translation.width > 80
                                && abs(value.translation.height) < 60 {
                                Haptics.tap()
                                dismiss()
                            }
                        }
                )
                .accessibilityHidden(true)
        }
    }

    private var scopeNotice: some View {
        Panel(accent: Theme.info) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "house.fill").foregroundStyle(Theme.info)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your network only")
                        .font(.system(.subheadline, design: .monospaced).weight(.bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("This tool only inspects devices on the Wi-Fi network you're connected to, so you can see what services are reachable on your own gear (printers, NAS, smart-home hubs, your laptop). Public hosts on the internet can't be targeted.")
                        .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                }
            }
        }
    }

    private var devicePicker: some View {
        Panel(title: "Devices On Your Network", accent: Theme.info) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick one of your devices from the last scan to check.")
                    .font(.system(.footnote, design: .monospaced)).foregroundStyle(Theme.textDim)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(discovered) { d in
                            Button {
                                target = d.ip
                                Haptics.tap()
                            } label: {
                                VStack(spacing: 3) {
                                    Image(systemName: deviceIcon(d))
                                        .font(.system(.callout))
                                        .foregroundStyle(target == d.ip ? Theme.bg : Theme.info)
                                    Text(d.hostname.map { String($0.prefix(10)) } ?? lastOctet(d.ip))
                                        .font(.system(.caption, design: .monospaced).weight(.bold))
                                        .foregroundStyle(target == d.ip ? Theme.bg : Theme.textPrimary)
                                    Text(d.ip).font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(target == d.ip ? Theme.bg.opacity(0.7) : Theme.textDim)
                                }
                                .frame(width: 78)
                                .padding(.vertical, 10)
                                .background(target == d.ip ? Theme.info : Theme.surfaceHi)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(Theme.info.opacity(target == d.ip ? 0 : 0.3), lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func deviceIcon(_ d: DeviceRecord) -> String {
        let v = (d.vendorGuess ?? "").lowercased()
        if v.contains("apple") || v.contains("airplay") { return "applelogo" }
        if v.contains("printer") { return "printer" }
        if v.contains("router") || v.contains("gateway") { return "wifi.router" }
        if v.contains("ssh") || v.contains("server") || v.contains("pi") { return "terminal" }
        return "desktopcomputer"
    }

    private func lastOctet(_ ip: String) -> String {
        ip.split(separator: ".").last.map(String.init) ?? ip
    }
}
