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
