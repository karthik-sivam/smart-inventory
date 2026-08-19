import SwiftUI

/// S34 — first-run language selection before onboarding content or after sign-in.
struct OnboardingLanguageStepView: View {
    @EnvironmentObject private var localizationManager: LocalizationManager
    @Binding var isPresented: Bool

    var onCompleted: (() -> Void)?

    @AppStorage(LocalizationManager.hasChosenLanguageKey) private var hasChosenLanguage = false
    @State private var selectedCode: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(L("onboarding.language.title", "Choose your language"))
                        .font(.title2)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                    Text(L("onboarding.language.subtitle", "Stoqly works best in the language you use every day."))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                }
                .padding(.top, 24)
                .padding(.bottom, 12)

                List {
                    ForEach(localizationManager.languageOptions) { option in
                        languageRow(option)
                    }
                }
                .accessibilityIdentifier("onboardingLanguagePicker")

                Button(action: continueTapped) {
                    Text(L("Continue", "Continue"))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.stoqlyPrimary)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .accessibilityIdentifier("onboardingLanguageContinue")
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            if selectedCode == nil {
                selectedCode = defaultDeviceLanguageCode()
            }
        }
    }

    @ViewBuilder
    private func languageRow(_ option: LanguageOption) -> some View {
        Button {
            selectedCode = option.code
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
                if selectedCode == option.code {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.stoqlyPrimary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboardingLanguage_\(option.code ?? "system")")
    }

    private func defaultDeviceLanguageCode() -> String? {
        guard let deviceCode = Locale.current.language.languageCode?.identifier else { return "en" }
        if localizationManager.languageOptions.contains(where: { $0.code == deviceCode }) {
            return deviceCode
        }
        return localizationManager.languageOptions.first?.code
    }

    private func continueTapped() {
        if let code = selectedCode {
            localizationManager.setLanguage(code)
            AnalyticsManager.shared.track(.languageChosenAtOnboarding(language: code))
        }
        hasChosenLanguage = true
        onCompleted?()
        isPresented = false
    }
}
