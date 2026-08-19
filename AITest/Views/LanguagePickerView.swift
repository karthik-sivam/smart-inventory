import SwiftUI

struct LanguagePickerView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Environment(\.dismiss) private var dismiss
    @State private var showRestartAlert = false

    var body: some View {
        NavigationStack {
            List {
                languageRow(localizationManager.systemDefaultOption)

                ForEach(localizationManager.languageOptions) { option in
                    languageRow(option)
                }
            }
            .accessibilityIdentifier("languagePicker")
            .navigationTitle(L("Language", "Language"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Cancel")) {
                        dismiss()
                    }
                }
            }
            .alert(
                L("language.restart.title", "Restart to apply"),
                isPresented: $showRestartAlert
            ) {
                Button(L("OK", "OK")) {
                    dismiss()
                }
            } message: {
                Text(L("language.restart.message", "Please reopen Stoqly to finish switching the language."))
            }
        }
    }

    @ViewBuilder
    private func languageRow(_ option: LanguageOption) -> some View {
        Button {
            guard !localizationManager.isSelected(option) else { return }
            let wasRTL = localizationManager.layoutDirection == .rightToLeft
            localizationManager.setLanguage(option.code)
            let nowRTL = localizationManager.layoutDirection == .rightToLeft
            if wasRTL != nowRTL {
                showRestartAlert = true
            } else {
                AppWindowCoordinator.reRootWindow(animated: true)
                dismiss()
            }
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
