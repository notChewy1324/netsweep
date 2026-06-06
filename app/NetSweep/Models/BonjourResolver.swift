import Foundation
import Network

// MARK: - Bonjour service resolver
// Resolves a discovered service to its concrete endpoint: hostname, port,
// IP addresses, and TXT-record metadata (which often reveals model, version,
// and capabilities for printers, AirPlay devices, etc.).

struct ResolvedService {
    var name: String
    var type: String
    var host: String?
    var port: UInt16?
    var addresses: [String] = []
    var txtRecords: [(String, String)] = []
}

@MainActor
final class BonjourResolver: ObservableObject {
    @Published var resolved: ResolvedService?
    @Published var isResolving = false

    private var connection: NWConnection?

    func resolve(name: String, type: String) {
        isResolving = true
        resolved = ResolvedService(name: name, type: type)

        let endpoint = NWEndpoint.service(name: name, type: type, domain: "local.", interface: nil)
        let params = NWParameters.tcp
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let inner = conn.currentPath?.remoteEndpoint {
                    Task { @MainActor in self?.capture(inner) }
                }
                Task { @MainActor in self?.finish() }
            case .failed, .cancelled:
                Task { @MainActor in self?.finish() }
            default: break
            }
        }
        conn.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 4) { [weak self] in
            Task { @MainActor in self?.finish() }
        }
    }

    private func capture(_ endpoint: NWEndpoint) {
        if case let .hostPort(host, port) = endpoint {
            resolved?.port = port.rawValue
            switch host {
            case .name(let h, _): resolved?.host = h
            case .ipv4(let addr): resolved?.addresses.append("\(addr)")
            case .ipv6(let addr): resolved?.addresses.append("\(addr)")
            @unknown default: break
            }
        }
    }

    private func finish() {
        guard isResolving else { return }
        isResolving = false
        connection?.cancel()
        connection = nil
    }

    func cancel() { connection?.cancel(); connection = nil; isResolving = false }
}
