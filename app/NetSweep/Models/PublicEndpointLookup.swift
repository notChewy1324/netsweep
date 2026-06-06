import Foundation

// MARK: - Public endpoint info ("what the internet sees")
// Looks up the public IP your traffic exits from, plus the ASN/ISP and rough
// geo. Works on cellular and WiFi alike — and on cellular it reveals your
// carrier's network identity, which is the closest thing to "cellular info"
// that's actually attainable.

struct PublicEndpoint {
    var ip: String?
    var city: String?
    var region: String?
    var country: String?
    var org: String?        // ISP / carrier ("AS7018 AT&T")
    var asn: String?
    var locationLine: String {
        [city, region, country].compactMap { $0 }.joined(separator: ", ")
    }
}

@MainActor
final class PublicEndpointLookup: ObservableObject {
    @Published var endpoint: PublicEndpoint?
    @Published var isLoading = false
    @Published var error: String?

    // ipwho.is returns IP + geo + connection (ISP/org/ASN) in one call, no key
    // needed and generous rate limits.
    private let url = URL(string: "https://ipwho.is/")!

    func fetch() {
        isLoading = true
        error = nil
        Task {
            defer { isLoading = false }
            do {
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 10
                let session = URLSession(configuration: config)
                let (data, _) = try await session.data(from: url)
                let decoded = try JSONDecoder().decode(IPWhoResponse.self, from: data)
                let asnString = decoded.connection?.asn.map { "AS\($0)" }
                endpoint = PublicEndpoint(
                    ip: decoded.ip, city: decoded.city, region: decoded.region,
                    country: decoded.country,
                    org: decoded.connection?.isp ?? decoded.connection?.org,
                    asn: asnString
                )
            } catch {
                self.error = "Couldn't reach lookup service. Check your connection."
            }
        }
    }
}

private struct IPWhoResponse: Decodable {
    let ip: String?
    let city: String?
    let region: String?
    let country: String?
    let connection: Connection?

    struct Connection: Decodable {
        let asn: Int?
        let org: String?
        let isp: String?
    }
}
