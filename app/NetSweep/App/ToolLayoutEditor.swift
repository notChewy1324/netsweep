import SwiftUI

// MARK: - Tool catalog
// One source of truth for every tool that can appear in the instruments panel.
// Each entry is identified by a stable string ID so the user's saved layout
// survives renames, additions, and reordering without losing data.

struct ToolCatalogEntry: Identifiable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let accent: Color
}

enum ToolCatalog {
    // Names stay user-facing; subtitles and icons are now leaning into the
    // observatory theme — gauges, beacons, scopes, telemetry. The semantic
    // meaning of each tool is unchanged.
    static let all: [ToolCatalogEntry] = [
        .init(id: "dashboard",   name: "Overview",            subtitle: "network summary",      icon: "shield.lefthalf.filled",                accent: Theme.good),
        .init(id: "compare",     name: "Compare",             subtitle: "scan delta",           icon: "square.split.2x1",                      accent: Theme.purple),
        .init(id: "network-map", name: "Network Map",         subtitle: "device atlas",         icon: "point.3.connected.trianglepath.dotted", accent: Theme.accent),
        .init(id: "port-scanner",name: "Service Diagnostics", subtitle: "check your devices",   icon: "stethoscope",                           accent: Theme.amber),
        .init(id: "bonjour",     name: "Bonjour",             subtitle: "service beacons",      icon: "dot.radiowaves.left.and.right",         accent: Theme.info),
        .init(id: "vuln",        name: "Security Notes",      subtitle: "informational guide",  icon: "info.circle.fill",                      accent: Theme.danger),
        .init(id: "connection",  name: "Connection",          subtitle: "link telemetry",       icon: "gauge.medium",                          accent: Theme.good),
        .init(id: "history",     name: "History",             subtitle: "session log",          icon: "clock.arrow.circlepath",                accent: Theme.purple),
        .init(id: "net-utils",   name: "Net Utils",           subtitle: "subnet math",          icon: "function",                              accent: Theme.info),
        .init(id: "settings",    name: "Settings",            subtitle: "configuration",        icon: "gearshape.fill",                        accent: Theme.textDim)
    ]

    // Tools that ship hidden by default. Users opt into them from the layout
    // editor — keeping the canvas focused on the core sweep utilities until
    // someone explicitly wants the meta-views.
    static let hiddenByDefault: Set<String> = ["dashboard", "compare"]

    static var defaultOrder: [String] {
        all.map(\.id).filter { !hiddenByDefault.contains($0) }
    }

    static func entry(for id: String) -> ToolCatalogEntry? {
        all.first { $0.id == id }
    }
}

// MARK: - Tool Layout Editor
// A sheet that lets the user reorder visible tools, swipe to hide them, and
// re-enable hidden ones from a Hidden section. Writes the final order to
// AppSettings.toolLayout on every change so the instruments panel updates
// live as the user edits.

struct ToolLayoutEditor: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var enabled: [String] = []

    private var hidden: [ToolCatalogEntry] {
        let enabledSet = Set(enabled)
        return ToolCatalog.all.filter { !enabledSet.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if enabled.isEmpty {
                        Text("No tools enabled. Add one below.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textDim)
                    }
                    ForEach(enabled, id: \.self) { id in
                        if let entry = ToolCatalog.entry(for: id) {
                            ToolRow(entry: entry, isEnabled: true)
                        }
                    }
                    .onMove(perform: move)
                    .onDelete(perform: hide)
                } header: {
                    Text("Visible · \(enabled.count)")
                } footer: {
                    Text("Drag to reorder. Swipe to hide.")
                        .font(.caption2)
                }

                if !hidden.isEmpty {
                    Section("Hidden · \(hidden.count)") {
                        ForEach(hidden) { entry in
                            Button {
                                enable(entry.id)
                            } label: {
                                ToolRow(entry: entry, isEnabled: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        settings.resetToolLayout()
                        enabled = settings.toolLayout
                        Haptics.tap()
                    } label: {
                        Label("Reset to Default", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .navigationTitle("Customize Array")
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Haptics.tap()
                        dismiss()
                    }
                    .tint(Theme.accent)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { enabled = settings.toolLayout }
    }

    private func move(from: IndexSet, to: Int) {
        enabled.move(fromOffsets: from, toOffset: to)
        settings.toolLayout = enabled
        Haptics.soft()
    }

    private func hide(at offsets: IndexSet) {
        enabled.remove(atOffsets: offsets)
        settings.toolLayout = enabled
        Haptics.tap()
    }

    private func enable(_ id: String) {
        guard !enabled.contains(id) else { return }
        enabled.append(id)
        settings.toolLayout = enabled
        Haptics.tap()
    }
}

private struct ToolRow: View {
    let entry: ToolCatalogEntry
    let isEnabled: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: entry.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(entry.accent)
                .frame(width: 36, height: 36)
                .background(entry.accent.opacity(0.16), in: .rect(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(entry.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            if !isEnabled {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
