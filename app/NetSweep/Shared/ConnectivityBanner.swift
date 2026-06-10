import SwiftUI
import Network

// MARK: - Connectivity awareness
// Local-network features (device discovery, Bonjour, the map, per-device port
// scans) require being ON a Wi-Fi/LAN. Over cellular there is no local network
// to scan, so we surface an honest note rather than silently returning nothing.
// Internet features (DNS, TLS of public hosts, speed test, public IP, CVE
// lookup) work fine on cellular.

@MainActor
final class Connectivity: ObservableObject {
    static let shared = Connectivity()
    @Published var onWiFi = false
    @Published var online = false
    @Published var type = "—"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "Connectivity")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.online = path.status == .satisfied
                self.onWiFi = path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet)
                if path.usesInterfaceType(.wifi) { self.type = "Wi-Fi" }
                else if path.usesInterfaceType(.wiredEthernet) { self.type = "Ethernet" }
                else if path.usesInterfaceType(.cellular) { self.type = "Cellular" }
                else { self.type = "Offline" }
            }
        }
        monitor.start(queue: queue)
    }

    // App-lifetime singleton, but if this is ever swapped for an
    // instance-per-screen owner the monitor still releases its queue cleanly.
    deinit { monitor.cancel() }
}

// A reusable note shown on local-network screens when the user is on cellular.
struct CellularNote: View {
    var feature: String = "Local network scanning"
    @ObservedObject private var conn = Connectivity.shared

    var body: some View {
        if conn.online && !conn.onWiFi {
            HStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(feature) needs Wi-Fi")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("You're on \(conn.type). There's no local network to scan over cellular — connect to Wi-Fi to map your devices. Internet tools (DNS, TLS, speed, CVE lookup) still work.")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                }
                Spacer()
            }
            .padding(14)
            .background(Theme.amber.opacity(0.12), in: .rect(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.amber.opacity(0.3), lineWidth: 1))
        }
    }
}

// Compact, dismissible cellular notice for screens where the full note would
// overlap live canvas content. Tap-to-expand: collapsed it's a slim pill,
// expanded it's a card explaining exactly which features work over cellular
// and which need Wi-Fi. Solid (not translucent) so map content underneath
// doesn't bleed through, and the X dismisses for the session.
struct CellularPill: View {
    var feature: String = "needs Wi-Fi"
    var onDismiss: () -> Void
    @ObservedObject private var conn = Connectivity.shared
    @State private var expanded = false

    var body: some View {
        if conn.online && !conn.onWiFi {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                if expanded { expandedBody }
            }
            .background(Theme.surface,
                        in: .rect(cornerRadius: expanded ? 14 : 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: expanded ? 14 : 20, style: .continuous)
                .stroke(Theme.amber.opacity(0.6), lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 8, y: 2)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expanded)
        }
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.caption)
                .foregroundStyle(Theme.amber)
            Text(expanded ? "Cellular limitations" : "\(conn.type) limitations")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                .font(.caption2)
                .foregroundStyle(Theme.textDim)
            Button {
                Haptics.tap()
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Theme.textDim)
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12).padding(.trailing, 4)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                expanded.toggle()
            }
            Haptics.soft()
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.stroke)
            Text("You're on \(conn.type). iOS doesn't expose a LAN to apps over the cellular path, so there's no local network to discover, map, or port scan. Internet side features still work because they hit public endpoints over the carrier.")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                limitRow(label: "Still works", color: Theme.good,
                         items: "DNS · TLS · speed test · public IP · CVE lookup")
                limitRow(label: "Needs Wi-Fi", color: Theme.amber,
                         items: "device map · port scans · Bonjour · gateway scan")
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .padding(.top, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private func limitRow(label: String, color: Color, items: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label)
                .font(.system(.caption2, design: .monospaced).weight(.bold))
                .foregroundStyle(color)
            Text(items)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
