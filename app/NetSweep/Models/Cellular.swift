import Foundation
import CoreTelephony

// MARK: - Cellular radio info
// The ONLY legitimate cellular introspection on iOS. Signal strength, tower IDs,
// and bands are all private APIs (App Store rejection), so we surface what's
// actually allowed: the radio access technology (LTE / 5G / etc.) and whatever
// carrier metadata the OS still returns (mostly placeholders on iOS 16+).

struct RadioInfo {
    let technology: String      // e.g. "5G", "LTE", "3G"
    let detail: String          // raw CTRadioAccessTechnology constant, humanized
    let carrier: String?        // often "--" / nil on modern iOS
}

enum Cellular {

    static func current() -> RadioInfo? {
        let info = CTTelephonyNetworkInfo()
        guard let techByService = info.serviceCurrentRadioAccessTechnology,
              let raw = techByService.values.first else {
            return nil
        }
        let (generation, label) = classify(raw)

        var carrierName: String? = nil
        if #available(iOS 16.0, *) {
            // CTCarrier is deprecated and returns placeholder data on iOS 16+;
            // we read it but treat "--" / empty as unavailable.
        } else {
            if let carriers = info.serviceSubscriberCellularProviders,
               let c = carriers.values.first, let n = c.carrierName,
               n != "--", !n.isEmpty {
                carrierName = n
            }
        }
        return RadioInfo(technology: generation, detail: label, carrier: carrierName)
    }

    private static func classify(_ raw: String) -> (String, String) {
        switch raw {
        case CTRadioAccessTechnologyNRNSA: return ("5G", "5G (Non-Standalone)")
        case CTRadioAccessTechnologyNR:    return ("5G", "5G (Standalone)")
        case CTRadioAccessTechnologyLTE:   return ("LTE", "LTE / 4G")
        case CTRadioAccessTechnologyWCDMA, CTRadioAccessTechnologyHSDPA,
             CTRadioAccessTechnologyHSUPA: return ("3G", "3G (UMTS/HSPA)")
        case CTRadioAccessTechnologyeHRPD, CTRadioAccessTechnologyCDMA1x,
             CTRadioAccessTechnologyCDMAEVDORev0, CTRadioAccessTechnologyCDMAEVDORevA,
             CTRadioAccessTechnologyCDMAEVDORevB: return ("3G", "3G (CDMA)")
        case CTRadioAccessTechnologyEdge:  return ("2G", "EDGE / 2G")
        case CTRadioAccessTechnologyGPRS:  return ("2G", "GPRS / 2G")
        default:                           return ("?", "Unknown radio")
        }
    }
}
