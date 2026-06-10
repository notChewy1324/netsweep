import SwiftUI

// MARK: - App-wide settings (persisted)

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("hasOnboarded") var hasOnboarded = false
    @AppStorage("hasPrimedLocalNetwork") var hasPrimedLocalNetwork = false
    // Explicit affirmation that the user is the owner / authorized
    // administrator of the network they're about to scan. Captured during
    // onboarding so the rest of the app can rely on it as ground truth.
    @AppStorage("hasAcceptedResponsibleUse") var hasAcceptedResponsibleUse = false

    // Scan tuning
    @AppStorage("scanIntensity") var scanIntensityRaw = ScanIntensity.balanced.rawValue
    @AppStorage("notifyNewDevices") var notifyNewDevices = true
    @AppStorage("backgroundMonitoring") var backgroundMonitoring = false

    // Appearance
    @AppStorage("appearance") var appearanceRaw = Appearance.system.rawValue
    var appearance: Appearance {
        get { Appearance(rawValue: appearanceRaw) ?? .system }
        set { appearanceRaw = newValue.rawValue }
    }

    var scanIntensity: ScanIntensity {
        get { ScanIntensity(rawValue: scanIntensityRaw) ?? .balanced }
        set { scanIntensityRaw = newValue.rawValue }
    }

    // MARK: - Customizable tool layout
    // Stored as a comma-separated list of tool IDs (see ToolCatalog). When
    // empty, falls back to the catalog's default order with every tool
    // enabled. Unknown IDs are filtered out so renaming/removing a tool
    // never strands the user with a blank panel.
    @AppStorage("toolLayoutV1") var toolLayoutCSV: String = ""

    var toolLayout: [String] {
        get {
            let stored = toolLayoutCSV
                .split(separator: ",")
                .map(String.init)
                .filter { !$0.isEmpty }
            if stored.isEmpty { return ToolCatalog.defaultOrder }
            let known = Set(ToolCatalog.all.map(\.id))
            let valid = stored.filter { known.contains($0) }
            return valid.isEmpty ? ToolCatalog.defaultOrder : valid
        }
        set { toolLayoutCSV = newValue.joined(separator: ",") }
    }

    func resetToolLayout() {
        toolLayoutCSV = ""
    }
}

// Controls the speed/thoroughness tradeoff of a network sweep.
enum ScanIntensity: String, CaseIterable, Identifiable {
    case fast, balanced, thorough
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var timeout: TimeInterval { self == .fast ? 0.4 : self == .balanced ? 0.6 : 1.0 }
    var concurrency: Int { self == .fast ? 32 : self == .balanced ? 24 : 16 }
    var detail: String {
        switch self {
        case .fast:     return "Quick sweep, may miss slow devices"
        case .balanced: return "Recommended for most networks"
        case .thorough: return "Slower, catches more devices"
        }
    }
}

enum AppMode: String { case home, pro }

// User-selectable appearance. `nil` colorScheme = follow the system.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
}
