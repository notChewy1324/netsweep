import Foundation

// MARK: - NVD (National Vulnerability Database) client
// Queries NIST's official CVE API 2.0. We ONLY surface descriptive vulnerability
// information and link back to the authoritative NVD record. We never fetch,
// generate, or display exploit code or step-by-step attack instructions.
//
// API docs: https://nvd.nist.gov/developers/vulnerabilities
// Note: the public API is rate-limited (a few requests per 30s without a key).

struct CVEItem: Identifiable {
    let id: String                 // e.g. "CVE-2021-44228"
    let description: String
    let severity: String           // CRITICAL / HIGH / MEDIUM / LOW / UNKNOWN
    let score: Double?             // CVSS base score
    let published: String?
    // Percent-encode the CVE ID for the path segment so a malformed `id`
    // can't produce nil or an unexpected URL. Falls back to the bare detail
    // landing page in the (never-observed) case that encoding fails.
    var nvdURL: URL {
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return URL(string: "https://nvd.nist.gov/vuln/detail/\(encoded)")
            ?? URL(string: "https://nvd.nist.gov/")!
    }

    var severityRank: Int {
        switch severity.uppercased() {
        case "CRITICAL": return 4
        case "HIGH": return 3
        case "MEDIUM": return 2
        case "LOW": return 1
        default: return 0
        }
    }
}

enum NVDError: Error { case badResponse, rateLimited }

@MainActor
final class NVDClient: ObservableObject {
    @Published var results: [CVEItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastQuery = ""

    /// Search by free-text keyword (e.g. "OpenSSH 8.9"). Caps results to keep it
    /// readable and the request light.
    func search(keyword: String, limit: Int = 15) {
        let trimmed = keyword.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        error = nil
        lastQuery = trimmed
        results = []

        Task { @MainActor in
            defer { self.isLoading = false }
            do {
                let items = try await fetch(keyword: trimmed, limit: limit)
                self.results = items.sorted { $0.severityRank > $1.severityRank }
            } catch NVDError.rateLimited {
                self.error = "NVD rate limit reached. Wait a moment and try again."
            } catch let failure {
                _ = failure
                self.error = "Couldn't reach the NVD database. Check your connection."
            }
        }
    }

    private func fetch(keyword: String, limit: Int) async throws -> [CVEItem] {
        var comps = URLComponents(string: "https://services.nvd.nist.gov/rest/json/cves/2.0")!
        comps.queryItems = [
            URLQueryItem(name: "keywordSearch", value: keyword),
            URLQueryItem(name: "resultsPerPage", value: "\(limit)")
        ]
        guard let url = comps.url else { throw NVDError.badResponse }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        let (data, response) = try await URLSession(configuration: config).data(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 403 || http.statusCode == 429 { throw NVDError.rateLimited }
            guard http.statusCode == 200 else { throw NVDError.badResponse }
        }
        return try parse(data)
    }

    private func parse(_ data: Data) throws -> [CVEItem] {
        let root = try JSONDecoder().decode(NVDResponse.self, from: data)
        return root.vulnerabilities.compactMap { wrapper in
            let cve = wrapper.cve
            let desc = cve.descriptions.first(where: { $0.lang == "en" })?.value
                ?? cve.descriptions.first?.value ?? "No description available."
            let (sev, score) = cve.bestSeverity()
            return CVEItem(id: cve.id, description: desc, severity: sev,
                           score: score, published: cve.published)
        }
    }
}

// MARK: - Minimal NVD 2.0 JSON shapes (only what we use)

private struct NVDResponse: Decodable {
    let vulnerabilities: [Wrapper]
    struct Wrapper: Decodable { let cve: CVE }
}

private struct CVE: Decodable {
    let id: String
    let published: String?
    let descriptions: [Desc]
    let metrics: Metrics?

    struct Desc: Decodable { let lang: String; let value: String }

    struct Metrics: Decodable {
        let cvssMetricV31: [MetricV3]?
        let cvssMetricV30: [MetricV3]?
        let cvssMetricV2: [MetricV2]?
    }
    struct MetricV3: Decodable {
        let cvssData: CVSSV3
        struct CVSSV3: Decodable { let baseScore: Double; let baseSeverity: String }
    }
    struct MetricV2: Decodable {
        let cvssData: CVSSV2
        let baseSeverity: String?
        struct CVSSV2: Decodable { let baseScore: Double }
    }

    func bestSeverity() -> (String, Double?) {
        if let m = metrics?.cvssMetricV31?.first { return (m.cvssData.baseSeverity, m.cvssData.baseScore) }
        if let m = metrics?.cvssMetricV30?.first { return (m.cvssData.baseSeverity, m.cvssData.baseScore) }
        if let m = metrics?.cvssMetricV2?.first { return (m.baseSeverity ?? "UNKNOWN", m.cvssData.baseScore) }
        return ("UNKNOWN", nil)
    }
}
