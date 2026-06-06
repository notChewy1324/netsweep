import SwiftUI

// MARK: - App-wide settings (persisted)

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage("hasOnboarded") var hasOnboarded = false
    @AppStorage("hasPrimedLocalNetwork") var hasPrimedLocalNetwork = false

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
