import SwiftUI

struct TLSView: View {
    @StateObject private var inspector = TLSInspector()
    @State private var host = ""
    @State private var portText = "443"

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel(title: "Endpoint") {
                    VStack(spacing: 10) {
                        TextField("host (e.g. example.com)", text: $host)
                            .font(Theme.mono).foregroundStyle(Theme.textPrimary)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .keyboardType(.URL)
                            .padding(10).background(Theme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        TextField("port", text: $portText)
                            .font(Theme.mono).foregroundStyle(Theme.textPrimary)
                            .keyboardType(.numberPad)
                            .padding(10).background(Theme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        ActionButton(title: "Inspect", systemImage: "lock.shield",
                                     running: inspector.isRunning) {
                            let h = host.trimmingCharacters(in: .whitespaces)
                            guard !h.isEmpty, let p = UInt16(portText) else { return }
                            inspector.inspect(host: h, port: p)
                        }
                    }
                }

                if let err = inspector.error {
                    Panel(title: "Error", accent: Theme.danger) {
                        Text(err).font(Theme.monoSm).foregroundStyle(Theme.danger)
                    }
                }

                if let report = inspector.report {
                    Panel(title: "Handshake") {
                        DataRow(key: "endpoint", value: "\(report.host):\(report.port)", valueColor: Theme.accent)
                        DataRow(key: "protocol", value: report.negotiatedProtocol ?? "—",
                                valueColor: report.negotiatedProtocol == "TLS 1.3" ? Theme.accent : Theme.amber)
                        DataRow(key: "handshake", value: String(format: "%.0f ms", report.handshakeMs))
                        DataRow(key: "chain depth", value: "\(report.chain.count) cert(s)")
                    }

                    ForEach(report.chain) { cert in
                        Panel(title: cert.position == 0 ? "Leaf Certificate" : "Chain #\(cert.position)",
                              accent: cert.isExpired ? Theme.danger : Theme.accent) {
                            VStack(spacing: 8) {
                                DataRow(key: "subject", value: cert.subjectSummary, valueColor: Theme.textPrimary)
                                if let nb = cert.notBefore {
                                    DataRow(key: "not before", value: nb.formatted(date: .abbreviated, time: .omitted))
                                }
                                if let na = cert.notAfter {
                                    DataRow(key: "not after", value: na.formatted(date: .abbreviated, time: .omitted),
                                            valueColor: cert.isExpired ? Theme.danger : Theme.textPrimary)
                                }
                                if let days = cert.daysRemaining {
                                    HStack {
                                        Text("status").font(Theme.monoSm).foregroundStyle(Theme.textDim)
                                        Spacer()
                                        if cert.isExpired {
                                            Pill(text: "EXPIRED", color: Theme.danger)
                                        } else if days < 30 {
                                            Pill(text: "\(days)d left", color: Theme.amber)
                                        } else {
                                            Pill(text: "\(days)d left", color: Theme.accent)
                                        }
                                    }
                                }
                                DataRow(key: "sha-256", value: cert.sha256, valueColor: Theme.textDim)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle("TLS Inspector")
        .navigationBarTitleDisplayMode(.inline)
    }
}
