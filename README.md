<div align="center">

# 🛰️ NetSweep

### See your network like an observatory.

**An on-device network security scanner for iOS — mapping your devices as a living, spatial command center.**

[![Platform](https://img.shields.io/badge/platform-iOS%2018%2B-0a84ff?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-FA7343?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/swift/)
[![Privacy](https://img.shields.io/badge/privacy-100%25%20on--device-5cd9db?style=for-the-badge&logo=ghostery&logoColor=white)](#-privacy-first)
[![License](https://img.shields.io/badge/license-proprietary-1d212c?style=for-the-badge)](LICENSE)

[🌐 netsweepapp.com](https://netsweepapp.com) · [👤 camgarrison.com](https://camgarrison.com) · [💻 GitHub](https://github.com/notchewy1324)

</div>

---

## ✨ Overview

**NetSweep** reframes the network scanner. Instead of a wall of IP addresses in a table, it renders your network as a living, spatial **observatory** — devices orbit a central beacon, problems glow before you read a word, and the whole interface breathes with the health of what it sees.

Underneath the calm is a real engine: concurrent on-device scanning, TLS inspection, live CVE lookups, and connection diagnostics — all within Apple's sandbox, with nothing leaving your phone.

> 🎯 **Built to be opened, not configured.** No accounts. No agents. No dashboards. No setup. Just scan and see.

---

## 🎨 Design Philosophy

NetSweep is an experiment in making a deeply technical tool feel **calm, spatial, and alive** — borrowing from theme-park and command-center design more than from dashboards.

- **A place, not a list.** The network is a navigable canvas you pan and zoom, not a spreadsheet. Spatial memory does the work that scrolling usually does.
- **The interface has a mood.** A single health signal drives the entire color temperature of the app — cyan when all is well, warming through amber to red as risk rises. You feel the state before you read it.
- **Honest by design.** Every limitation iOS imposes is stated plainly, in the app itself. The product never pretends to do what the platform forbids.
- **Restraint over density.** Motion is purposeful and respects Reduce Motion; type respects Dynamic Type; nothing animates just to animate.

---

## 🚀 What It Does

| | Feature | Description |
|---|---|---|
| 🗺️ | **Spatial device map** | Every device is a node you can pan, zoom, drag, and tap — orbiting a central beacon |
| 🎛️ | **Health-aware UI** | The whole interface shifts temperature — cyan when calm, amber on alert, red when it matters |
| 🔍 | **Full & fast scans** | Scan every common port, or just the 20 most common — explained in plain language |
| 🛡️ | **Deep device profiles** | Service detection, TLS inspection, banner grabs, OS guesses, exportable reports |
| 🐛 | **Vulnerability insights** | Per-device risk breakdown with live **NIST NVD** CVE lookup |
| 📶 | **Connection diagnostics** | Latency, jitter, throughput estimate, public-IP / ISP info, with history |
| 📡 | **Cellular-aware** | Shows everything iOS permits when you're on cellular instead of Wi-Fi |
| 📄 | **Reports you can keep** | Export any scan as a clean **PDF** or **JSON** |
| 🔔 | **Background checks** | Opportunistic nudges when a new device joins your Wi-Fi (within iOS limits) |
| ♿ | **Accessible** | Respects Dynamic Type and Reduce Motion throughout |

---

## 🧩 Engineering Highlights

The parts worth a closer look for fellow engineers:

- **Custom spatial canvas.** A SwiftUI pan/zoom surface backed by **UIKit gesture recognizers** to get true simultaneous pan + pinch — something SwiftUI's native gesture composition couldn't deliver cleanly. Node positions are cached and only rebuilt on data change, so panning stays at frame rate regardless of device count.
- **Concurrent scan engine.** TCP-connect probing built on **async/await** with bounded task groups — fast sweeps that stay inside iOS's sandbox, with no private APIs and no raw sockets.
- **Sandbox-honest networking.** Bonjour/mDNS discovery, path monitoring, and a captive-portal check, each scoped to exactly what the platform allows and declared correctly in the app's entitlements and privacy manifest.
- **On-device data model.** **SwiftData** persists scans, devices, and findings with proper relationships; history and trends are rendered with **Swift Charts**.
- **Zero dependencies.** Entirely first-party frameworks — nothing to audit, nothing to break on update.

---

## 🔒 Privacy-First

> **Your network stays yours.**

- 🏠 **100% on-device scanning** — results never leave your phone
- 🚫 **No accounts, no analytics, no ads, no trackers**
- 📋 Ships with a privacy manifest declaring **zero data collection**
- 🌐 The only outbound requests are **query-only** optional lookups:
  - `ipwho.is` — public IP / ISP info
  - `Cloudflare` — connection speed estimate
  - `NIST NVD` — CVE search
  - `Apple captive-portal` — hijacked-network detection

---

## 🧱 Tech Stack

<div align="center">

| Layer | Technology |
|---|---|
| 🎨 **Interface** | SwiftUI + a custom spatial pan/zoom canvas |
| 👆 **Gestures** | UIKit recognizers (simultaneous pan + pinch) |
| 💾 **Persistence** | SwiftData |
| 📊 **Charts** | Swift Charts |
| 🌐 **Networking** | Network.framework (TCP-connect, Bonjour/mDNS, path monitoring) |
| 🔐 **Crypto** | CryptoKit (TLS certificate inspection) |
| 📦 **Dependencies** | **Zero** third-party packages |

</div>

---

## 📂 Repository Layout

```
.
├── 📱 app/      The iOS app — open app/NetSweep.xcodeproj in Xcode
│   └── NetSweep/
│       ├── App/        Entry, root flow, home canvas, onboarding, settings, history
│       ├── Models/     Scanning engine, networking, persistence, services
│       ├── Modules/    Feature screens (port scanner, TLS, DNS, map, vuln insights…)
│       ├── Shared/     Design system, spatial canvas, gestures, haptics, shared UI
│       └── Assets.xcassets/
└── 🌐 site/     Static marketing + privacy site for netsweepapp.com (HTML/CSS/JS)
```

---

## 📇 Identity

| | |
|---|---|
| **Name** | NetSweep |
| **Bundle ID** | `com.camgarrison.netsweep` |
| **Domain** | [netsweepapp.com](https://netsweepapp.com) |
| **Deployment target** | iOS 18.0+ |
| **Destinations** | iPhone · iPad · (Designed-for-iPad extends to Mac & Apple Vision Pro) |

---

## 🌐 The Website (`site/`)

Static **HTML / CSS / JS** marketing and privacy site for **netsweepapp.com** — extends the app's observatory aesthetic to the web with a light/dark theme toggle, scroll reveals, and the NetSweep sweep mark. No build step, no dependencies.

- 🏠 `index.html` — overview, features, portfolio framing
- 💡 `use-cases.html` — IT, developer & security-curious scenarios + honest platform limits
- 🔒 `privacy.html` — full privacy policy *(App Store Connect URL: `netsweepapp.com/privacy.html`)*
- 🎨 `styles.css` · `app.js` — shared across all pages

> ☁️ **Deploy:** Cloudflare Pages with the build output directory set to `site`.

---

## 🛠️ Development Notes

- 📲 Open `app/NetSweep.xcodeproj` and build to a **physical iPhone** — designed and tested on real hardware
- 🎯 The app icon is a single 1024×1024 universal asset — **Clean Build Folder** after any asset change
- 🔑 Signing, certificates & provisioning profiles are **never** committed (handled in Xcode)
- 🙈 `.gitignore` excludes Xcode user state, build output, DerivedData, and all signing artifacts

---

## 📜 License

This project is released under a **proprietary license** — see [LICENSE](LICENSE).

It is **public for portfolio and reference viewing**: you're welcome to read it, clone it for study, and learn from it. It is **not** open-source — please don't republish it, ship it, or present it as your own. If you'd like to use a part of it, reach out.

---

<div align="center">

## 👤 Author

**Cam Garrison**
*Cybersecurity · Computer Science · Networking/Systems Administration*

[![Portfolio](https://img.shields.io/badge/Portfolio-camgarrison.com-5cd9db?style=for-the-badge&logo=safari&logoColor=white)](https://camgarrison.com)
[![GitHub](https://img.shields.io/badge/GitHub-notchewy1324-181717?style=for-the-badge&logo=github&logoColor=white)](https://github.com/notchewy1324)

© 2026 Cam Garrison · All rights reserved.

**🛰️ Built with care, one sweep at a time.**

</div>
