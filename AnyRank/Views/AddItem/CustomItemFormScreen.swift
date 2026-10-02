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

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            Group {
                Section {
                    TextField("What are you ranking?", text: $name)
                        .font(.body.weight(.medium))
                        .textInputAutocapitalization(.words)
                        .focused($nameFocused)
                        .submitLabel(.continue)
                        .onSubmit { if canSubmit { submit() } }
                        .onAppear { nameFocused = true }
                } header: {
                    header("Name")
                }
                Section {
                    TextField("https://…", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    header("Link")
                } footer: {
                    Text("Optional").foregroundStyle(Theme.textTertiary)
                }
                if !list.customFieldNames.isEmpty {
                    Section {
                        CustomFieldRows(names: list.customFieldNames) { field in
                            Binding(
                                get: { fieldValues[field] ?? "" },
                                set: { fieldValues[field] = $0 }
                            )
                        }
                    } header: {
                        header("Details")
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .themedList()
        .safeAreaInset(edge: .bottom) {
            Button("Continue", action: submit)
                .buttonStyle(.primary)
                .disabled(!canSubmit)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, 8)
                .background(Theme.background)
        }
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Theme.textSecondary)
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
