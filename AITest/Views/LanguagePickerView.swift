import SwiftUI

struct LanguagePickerView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                languageRow(localizationManager.systemDefaultOption)

                ForEach(localizationManager.languageOptions) { option in
                    languageRow(option)
                }
            }
            .accessibilityIdentifier("languagePicker")
            .navigationTitle(String(localized: "Language", defaultValue: "Language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", defaultValue: "Cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func languageRow(_ option: LanguageOption) -> some View {
        Button {
            localizationManager.setLanguage(option.code)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.nativeName)
                        .font(.body)
                        .foregroundColor(.primary)
                    Text(option.englishName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if localizationManager.isSelected(option) {
                    Image(systemName: "checkmark")
                        .foregroundColor(.stoqlyPrimary)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("languageOption_\(option.id)")
    }
}

#Preview {
    LanguagePickerView()
        .environmentObject(LocalizationManager.shared)
}
