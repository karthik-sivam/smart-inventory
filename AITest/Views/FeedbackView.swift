import SwiftUI
import UIKit

struct FeedbackView: View {
    enum FeedbackType: String, CaseIterable, Identifiable {
        case bug
        case idea
        case question
        case other

        var id: String { rawValue }

        var localizedTitle: String {
            switch self {
            case .bug:
                L("feedback.type.bug", "Bug")
            case .idea:
                L("feedback.type.idea", "Idea")
            case .question:
                L("feedback.type.question", "Question")
            case .other:
                L("feedback.type.other", "Other")
            }
        }

        var analyticsValue: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authManager: AuthManager

    @State private var feedbackType: FeedbackType = .bug
    @State private var message = ""
    @State private var email = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showSuccess = false
    @State private var sheetTracker = SheetAnalyticsTracker(sheet: "feedback")

    private var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedMessage.isEmpty && !isSubmitting
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(L("feedback.type.label", "Type"), selection: $feedbackType) {
                        ForEach(FeedbackType.allCases) { type in
                            Text(type.localizedTitle).tag(type)
                        }
                    }
                }

                Section {
                    TextEditor(text: $message)
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("feedbackMessageEditor")
                } header: {
                    Text(L("feedback.message.label", "Message"))
                } footer: {
                    Text(L("feedback.message.footer", "Tell us what happened or what you'd like to see."))
                }

                Section {
                    TextField(L("feedback.email.placeholder", "you@example.com"), text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(L("feedback.email.label", "Email (optional)"))
                }

                Section {
                    metadataRow(L("feedback.meta.version", "App version"), value: appVersionString)
                    metadataRow(L("feedback.meta.ios", "iOS"), value: UIDevice.current.systemVersion)
                    metadataRow(L("feedback.meta.device", "Device"), value: deviceModelString)
                    metadataRow(L("feedback.meta.locale", "Locale"), value: localeString)
                } header: {
                    Text(L("feedback.meta.header", "Diagnostics"))
                }
            }
            .navigationTitle(L("feedback.title", "Send Feedback"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        sheetTracker.trackCancelled()
                        dismiss()
                    }
                        .disabled(isSubmitting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button(L("feedback.submit", "Submit")) { Task { await submit() } }
                            .disabled(!canSubmit)
                            .accessibilityIdentifier("feedbackSubmitButton")
                    }
                }
            }
            .alert(L("feedback.success.title", "Thank you"), isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text(L("feedback.success.message", "Your feedback was sent. We appreciate you taking the time to help improve Stoqly."))
            }
            .alert(L("feedback.error.title", "Couldn't send feedback"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                sheetTracker.trackOpened()
                if email.isEmpty, let signedInEmail = authManager.currentUser?.email {
                    email = signedInEmail
                }
            }
            .onDisappear {
                sheetTracker.trackDismissedIfNeeded()
            }
        }
    }

    private func metadataRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var appVersionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private var localeString: String {
        LocalizationManager.shared.currentCode ?? Locale.current.identifier
    }

    private var deviceModelString: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafePointer(to: &systemInfo.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { cPtr in
                String(validatingUTF8: cPtr) ?? UIDevice.current.model
            }
        }
    }

    @MainActor
    private func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try await FirestoreManager.shared.submitFeedback(
                uid: authManager.currentUser?.uid,
                email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                type: feedbackType.analyticsValue,
                message: trimmedMessage,
                appVersion: appVersionString,
                iosVersion: UIDevice.current.systemVersion,
                device: deviceModelString,
                locale: localeString
            )
            AnalyticsManager.shared.track(.feedbackSubmitted(type: feedbackType.analyticsValue))
            sheetTracker.trackSaved()
            showSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
