import Foundation
import Network
import Security
import CryptoKit

// MARK: - TLS certificate inspector
// Opens a TLS connection and captures the server's certificate chain during the
// handshake (via sec_protocol verify block), then parses each cert with the
// Security framework. Great for spotting expired certs, weak chains, self-signed
// endpoints, and unexpected issuers on devices you're auditing.

struct CertInfo: Identifiable {
    let id = UUID()
    let position: Int           // 0 = leaf
    let subjectSummary: String
    let sha256: String
    var notBefore: Date?
    var notAfter: Date?
    var isExpired: Bool { notAfter.map { $0 < Date() } ?? false }
    var daysRemaining: Int? {
        guard let notAfter else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: notAfter).day
    }
}

struct TLSReport {
    var host: String
    var port: UInt16
    var negotiatedProtocol: String?
    var chain: [CertInfo]
    var handshakeMs: Double
    var trustEvaluated: Bool
}

@MainActor
final class TLSInspector: ObservableObject {
    @Published var report: TLSReport?
    @Published var error: String?
    @Published var isRunning = false

    func inspect(host: String, port: UInt16 = 443, timeout: TimeInterval = 6) {
        isRunning = true
        error = nil
        report = nil

        Task.detached {
            let start = DispatchTime.now()
            let collected = Lock<[SecCertificate]>([])
            let proto = Lock<String?>(nil)

            let tls = NWProtocolTLS.Options()
            // Capture the chain without failing on untrusted/self-signed certs —
            // we want to *report* on bad certs, not refuse them.
            sec_protocol_options_set_verify_block(
                tls.securityProtocolOptions,
                { _, trustRef, complete in
                    let trust = sec_trust_copy_ref(trustRef).takeRetainedValue()
                    var chain: [SecCertificate] = []
                    if #available(iOS 15.0, *) {
                        if let certs = SecTrustCopyCertificateChain(trust) as? [SecCertificate] {
                            chain = certs
                        }
                    } else {
                        let cnt = SecTrustGetCertificateCount(trust)
                        for i in 0..<cnt {
                            if let c = SecTrustGetCertificateAtIndex(trust, i) { chain.append(c) }
                        }
                    }
                    collected.swap(chain)
                    complete(true) // accept so handshake completes and we can read state
                },
                .main
            )

            let params = NWParameters(tls: tls)
            guard let nwPort = NWEndpoint.Port(rawValue: port) else {
                await self.fail("Invalid port"); return
            }
            let conn = NWConnection(host: .init(host), port: nwPort, using: params)
            let resumed = Lock(false)

            @Sendable func done(_ block: @escaping () -> Void) {
                if resumed.swap(true) == false { conn.cancel(); block() }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let meta = conn.metadata(definition: NWProtocolTLS.definition)
                        as? NWProtocolTLS.Metadata {
                        let sp = sec_protocol_metadata_get_negotiated_tls_protocol_version(
                            meta.securityProtocolMetadata)
                        proto.swap(Self.protoName(sp))
                    }
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
                    let chain = collected.current
                    done {
                        Task { await self.publish(host: host, port: port,
                                                  proto: proto.current, certs: chain, ms: ms) }
                    }
                case .failed(let e):
                    done { Task { await self.fail(e.localizedDescription) } }
                case .cancelled:
                    done { }
                default: break
                }
            }
            conn.start(queue: .global())
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                done { Task { await self.fail("Handshake timed out") } }
            }
        }
    }

    private func publish(host: String, port: UInt16, proto: String?,
                         certs: [SecCertificate], ms: Double) {
        let chain = certs.enumerated().map { idx, cert -> CertInfo in
            let data = SecCertificateCopyData(cert) as Data
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            let summary = (SecCertificateCopySubjectSummary(cert) as String?) ?? "—"
            var info = CertInfo(position: idx, subjectSummary: summary,
                                sha256: String(digest.prefix(32)) + "…")
            let (nb, na) = Self.validity(cert)
            info.notBefore = nb; info.notAfter = na
            return info
        }
        report = TLSReport(host: host, port: port, negotiatedProtocol: proto,
                           chain: chain, handshakeMs: ms, trustEvaluated: !chain.isEmpty)
        isRunning = false
    }

    private func fail(_ msg: String) { error = msg; isRunning = false }

    // SecCertificateCopyValues + the kSecOIDX509V1Validity* keys are macOS-only.
    // On iOS we parse the validity dates straight out of the DER ourselves.
    //
    // Structure:  Certificate ::= SEQUENCE { tbsCertificate SEQUENCE { ... } ... }
    //   tbsCertificate ::= SEQUENCE {
    //       [0] version (optional), serialNumber INTEGER, signature SEQUENCE,
    //       issuer SEQUENCE, validity SEQUENCE { notBefore Time, notAfter Time }, ... }
    // We walk to the first inner SEQUENCE (tbsCertificate), then find the first
    // Validity SEQUENCE whose two children are UTCTime(0x17)/GeneralizedTime(0x18).
    private nonisolated static func validity(_ cert: SecCertificate) -> (Date?, Date?) {
        let der = [UInt8](SecCertificateCopyData(cert) as Data)
        return DER.findValidity(der)
    }

    private nonisolated static func protoName(_ v: tls_protocol_version_t) -> String {
        switch v {
        case .TLSv13: return "TLS 1.3"
        case .TLSv12: return "TLS 1.2"
        case .TLSv11: return "TLS 1.1"
        case .TLSv10: return "TLS 1.0"
        default: return "unknown"
        }
    }
}
