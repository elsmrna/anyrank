import SwiftUI

/// Editable rows for a Custom list's fields: the field name stays on the
/// left while you type, and the value starts just to its right. Names share
/// one column, sized to the longest, so values line up and it's always
/// clear which field is which. Used by the add-item form and item detail.
struct CustomFieldRows: View {
    let names: [String]
    let value: (String) -> Binding<String>

    /// Widest field name measured so far, capped so a long name doesn't
    /// squeeze out the value.
    @State private var labelWidth: CGFloat = 0
    private let maxLabelWidth: CGFloat = 150

    var body: some View {
        ForEach(names, id: \.self) { name in
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(name)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .frame(width: min(labelWidth, maxLabelWidth), alignment: .leading)
                    .background(alignment: .leading) {
                        Text(name)
                            .fixedSize()
                            .hidden()
                            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width in
                                labelWidth = max(labelWidth, width)
                            }
                    }
                TextField("", text: value(name))
                    .accessibilityLabel(name)
            }
        }
    }
}

#Preview {
    @Previewable @State var values: [String: String] = ["Vintage": "2016"]
    Form {
        CustomFieldRows(names: ["Region", "Vintage", "Grape varietal"]) { name in
            Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
        }
    }
}
