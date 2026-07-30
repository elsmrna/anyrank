import SwiftUI

/// Custom-category add screen. Free-text name + optional pasted link +
/// the list's user-defined metadata fields.
struct CustomItemFormScreen: View {
    let list: RankList
    let onIdentified: (StagedItem) -> Void

    @State private var name: String = ""
    @State private var link: String = ""
    @State private var fieldValues: [String: String] = [:]
    /// Focus the name field on appear — keyboard up immediately.
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section("Name") {
                TextField("Item name", text: $name)
                    .textInputAutocapitalization(.words)
                    .focused($nameFocused)
                    .onAppear { nameFocused = true }
            }
            Section("Link") {
                TextField("https://…", text: $link)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            if !list.customFieldNames.isEmpty {
                Section("Details") {
                    ForEach(list.customFieldNames, id: \.self) { field in
                        TextField(field, text: Binding(
                            get: { fieldValues[field] ?? "" },
                            set: { fieldValues[field] = $0 }
                        ))
                    }
                }
            }
            Section {
                Button("Continue") {
                    submit()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func submit() {
        var staged = StagedItem(
            name: name.trimmingCharacters(in: .whitespaces),
            category: .custom
        )
        let trimmedLink = link.trimmingCharacters(in: .whitespaces)
        staged.customLink = trimmedLink.isEmpty ? nil : trimmedLink
        staged.customFieldValues = fieldValues.compactMapValues { value in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }
        onIdentified(staged)
    }
}

#Preview {
    let list = RankList(
        name: "Wines",
        category: .custom,
        customFieldNames: ["Region", "Vintage", "Grape"]
    )
    return NavigationStack {
        CustomItemFormScreen(list: list, onIdentified: { _ in })
    }
}
