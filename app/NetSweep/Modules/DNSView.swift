import SwiftUI

struct DNSView: View {
    @State private var query = ""
    @State private var forward: [String] = []
    @State private var reverse: String?
    @State private var running = false
    @State private var mode = 0  // 0 forward, 1 reverse

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Panel(title: "Lookup", accent: Theme.info) {
                    VStack(spacing: 10) {
                        Picker("Mode", selection: $mode) {
                            Text("Forward (A/AAAA)").tag(0)
                            Text("Reverse (PTR)").tag(1)
                        }.pickerStyle(.segmented)

                        TextField(mode == 0 ? "hostname" : "IP address", text: $query)
                            .font(Theme.mono).foregroundStyle(Theme.textPrimary)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(10).background(Theme.surfaceHi)
                            .clipShape(RoundedRectangle(cornerRadius: 12))

                        ActionButton(title: "Resolve", systemImage: "globe",
                                     color: Theme.info, running: running) {
                            resolve()
                        }
                    }
                }

                if !forward.isEmpty {
                    Panel(title: "Records", accent: Theme.info) {
                        ForEach(forward, id: \.self) { ip in
                            DataRow(key: ip.contains(":") ? "AAAA" : "A", value: ip, valueColor: Theme.accent)
                        }
                    }
                }
                if let reverse {
                    Panel(title: "PTR", accent: Theme.info) {
                        DataRow(key: "hostname", value: reverse, valueColor: Theme.accent)
                    }
                }
            }
            .padding(16)
        }
        .background(ObservatoryCanvas())
        .navigationTitle("DNS Tools")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func resolve() {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        running = true; forward = []; reverse = nil
        Task {
            if mode == 0 {
                forward = await DNS.resolve(host: q)
            } else {
                reverse = await DNS.reverse(ip: q) ?? "no PTR record"
            }
            running = false
        }
    }
}
