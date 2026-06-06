import SwiftUI

// Shared finding row used by device profiles, history, and detail screens.
struct FindingRow: View {
    let finding: Finding
    private var color: Color { [Theme.textDim, Theme.info, Theme.amber, Theme.danger][finding.severity.rawValue] }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 7, height: 7).padding(.top, 6)
                .shadow(color: color.opacity(0.6), radius: 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(finding.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                Text(finding.detail).font(.footnote).foregroundStyle(Theme.textDim)
            }
            Spacer()
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(finding.severity.label) severity. \(finding.title). \(finding.detail)")
    }
}
