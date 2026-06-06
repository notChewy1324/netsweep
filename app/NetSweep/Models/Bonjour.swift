import Foundation
import Network

// MARK: - Bonjour / mDNS service discovery
// NWBrowser passively discovers advertised services on the local link. This is
// one of the most revealing things you can do on a LAN from an unprivileged app:
// AirPlay targets, printers, SSH/SFTP servers, smart-home hubs, media servers, etc.

struct BonjourService: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    var friendly: String { ServiceTypes.friendly[type] ?? type }
    var icon: String { ServiceTypes.icon[type] ?? "questionmark.circle" }
}

enum ServiceTypes {
    // Service types we actively browse for.
    static let browseList: [String] = [
        "_http._tcp", "_https._tcp", "_ssh._tcp", "_sftp-ssh._tcp",
        "_smb._tcp", "_afpovertcp._tcp", "_nfs._tcp",
        "_airplay._tcp", "_raop._tcp", "_companion-link._tcp",
        "_ipp._tcp", "_ipps._tcp", "_printer._tcp", "_pdl-datastream._tcp",
        "_homekit._tcp", "_hap._tcp", "_googlecast._tcp",
        "_spotify-connect._tcp", "_daap._tcp", "_dpap._tcp",
        "_rfb._tcp", "_workstation._tcp", "_device-info._tcp",
        "_apple-mobdev2._tcp", "_adisk._tcp", "_time-machine._tcp"
    ]

    static let friendly: [String: String] = [
        "_http._tcp": "Web Server (HTTP)",
        "_https._tcp": "Web Server (HTTPS)",
        "_ssh._tcp": "SSH Server",
        "_sftp-ssh._tcp": "SFTP",
        "_smb._tcp": "File Share (SMB)",
        "_afpovertcp._tcp": "File Share (AFP)",
        "_nfs._tcp": "File Share (NFS)",
        "_airplay._tcp": "AirPlay",
        "_raop._tcp": "AirPlay Audio",
        "_companion-link._tcp": "Apple Companion",
        "_ipp._tcp": "Printer (IPP)",
        "_ipps._tcp": "Printer (IPPS)",
        "_printer._tcp": "Printer (LPD)",
        "_pdl-datastream._tcp": "Printer (raw)",
        "_homekit._tcp": "HomeKit",
        "_hap._tcp": "HomeKit Accessory",
        "_googlecast._tcp": "Chromecast",
        "_spotify-connect._tcp": "Spotify Connect",
        "_daap._tcp": "iTunes Library",
        "_rfb._tcp": "Screen Sharing (VNC)",
        "_workstation._tcp": "Workstation",
        "_device-info._tcp": "Device Info",
        "_apple-mobdev2._tcp": "iOS Device",
        "_adisk._tcp": "Time Capsule",
        "_time-machine._tcp": "Time Machine"
    ]

    static let icon: [String: String] = [
        "_http._tcp": "globe", "_https._tcp": "lock.shield",
        "_ssh._tcp": "terminal", "_sftp-ssh._tcp": "terminal",
        "_smb._tcp": "folder.badge.gearshape", "_afpovertcp._tcp": "folder",
        "_nfs._tcp": "folder", "_airplay._tcp": "airplayvideo",
        "_raop._tcp": "airplayaudio", "_companion-link._tcp": "applelogo",
        "_ipp._tcp": "printer", "_ipps._tcp": "printer", "_printer._tcp": "printer",
        "_pdl-datastream._tcp": "printer", "_homekit._tcp": "house",
        "_hap._tcp": "house", "_googlecast._tcp": "tv",
        "_spotify-connect._tcp": "music.note", "_daap._tcp": "music.note.list",
        "_rfb._tcp": "display", "_workstation._tcp": "desktopcomputer",
        "_device-info._tcp": "info.circle", "_apple-mobdev2._tcp": "iphone",
        "_adisk._tcp": "externaldrive", "_time-machine._tcp": "clock.arrow.circlepath"
    ]
}

@MainActor
final class BonjourBrowser: ObservableObject {
    @Published var services: [BonjourService] = []
    @Published var isBrowsing = false

    private var browsers: [NWBrowser] = []

    func start() {
        stop()
        services = []
        isBrowsing = true
        for type in ServiceTypes.browseList {
            let browser = NWBrowser(for: .bonjour(type: type, domain: "local."),
                                    using: .init())
            browser.browseResultsChangedHandler = { [weak self] results, _ in
                Task { @MainActor in
                    guard let self else { return }
                    for r in results {
                        if case let .service(name, t, _, _) = r.endpoint {
                            let svc = BonjourService(name: name, type: t)
                            if !self.services.contains(where: { $0.name == name && $0.type == t }) {
                                self.services.append(svc)
                                self.services.sort { $0.friendly < $1.friendly }
                            }
                        }
                    }
                }
            }
            browser.start(queue: .main)
            browsers.append(browser)
        }
    }

    func stop() {
        browsers.forEach { $0.cancel() }
        browsers = []
        isBrowsing = false
    }
}
