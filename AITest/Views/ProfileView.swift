import SwiftUI
import SwiftData
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var authManager = AuthManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var firestoreManager = FirestoreManager.shared
    @Environment(\.modelContext) private var modelContext

    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showEditProfile = false
    @State private var showEmailVerificationSent = false
    @State private var showEmailVerification = false
    @State private var showPrivacyPolicy = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {

                // MARK: - User Info
                Section {
                    HStack(spacing: 16) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: subscriptionManager.isPro ? [.yellow, .orange] : [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 60, height: 60)

                            Text(String(authManager.currentUser?.email?.prefix(1).uppercased() ?? "U"))
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            // Pro crown badge
                            if subscriptionManager.isPro {
                                VStack {
                                    HStack {
                                        Spacer()
                                        Image(systemName: "crown.fill")
                                            .font(.system(size: 12))
                                            .foregroundColor(.yellow)
                                            .background(
                                                Circle()
                                                    .fill(Color(.systemBackground))
                                                    .frame(width: 18, height: 18)
                                            )
                                    }
                                    Spacer()
                                }
                                .frame(width: 60, height: 60)
                            }
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(authManager.currentUser?.displayName ?? "User")
                                    .font(.headline)
                                    .fontWeight(.semibold)

                                if subscriptionManager.isPro {
                                    Text("PRO")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(
                                            LinearGradient(colors: [.yellow, .orange], startPoint: .leading, endPoint: .trailing)
                                        )
                                        .cornerRadius(6)
                                }
                            }

                            Text(authManager.currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                let verified = authManager.currentUser?.isEmailVerified ?? false
                                Image(systemName: verified ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(verified ? .green : .orange)
                                    .font(.caption)
                                Text(verified ? "Email verified" : "Email not verified")
                                    .font(.caption)
                                    .foregroundColor(verified ? .green : .orange)
                            }
                        }

                        Spacer()

                        VStack(spacing: 8) {
                            Button { showEditProfile = true } label: {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            Button {
                                Task { await authManager.reloadUser() }
                            } label: {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // MARK: - Subscription / Upgrade
                Section {
                    if subscriptionManager.isPro {
                        // Cloud sync status
                        HStack(spacing: 12) {
                            Image(systemName: firestoreManager.syncState.icon)
                                .foregroundColor(firestoreManager.syncState.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Cloud Sync")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                if let last = firestoreManager.lastSyncDate {
                                    Text("Last synced \(last, style: .relative) ago")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(firestoreManager.syncState.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if case .syncing = firestoreManager.syncState {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                        .padding(.vertical, 2)

                        // Manual sync trigger
                        Button {
                            Task { await firestoreManager.pullFromCloud(modelContext: modelContext) }
                        } label: {
                            HStack {
                                Label("Sync Now", systemImage: "arrow.triangle.2.circlepath.icloud")
                                    .foregroundColor(.blue)
                                Spacer()
                                if case .syncing = firestoreManager.syncState {
                                    ProgressView().scaleEffect(0.8)
                                } else if let last = firestoreManager.lastSyncDate {
                                    Text(last, style: .relative)
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                        .disabled({ if case .syncing = firestoreManager.syncState { return true }; return false }())

                        Button("Manage Subscription") {
                            if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                                UIApplication.shared.open(url)
                            }
                        }
                        .foregroundColor(.blue)
                    } else {
                        // Upgrade CTA
                        Button { showPaywall = true } label: {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.white)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Upgrade to Pro")
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    Text("Unlimited storages · Advanced analytics · No ads")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text(subscriptionManager.isPro ? "Pro Features" : "Go Pro")
                }

                // MARK: - Email Verification (only if unverified)
                if let verified = authManager.currentUser?.isEmailVerified, !verified {
                    Section("Email Verification") {
                        Button { showEmailVerification = true } label: {
                            Label("Verify Email Address", systemImage: "envelope.circle.fill")
                        }

                        Button {
                            Task {
                                await authManager.sendEmailVerification()
                                if authManager.errorMessage == nil { showEmailVerificationSent = true }
                            }
                        } label: {
                            Label("Resend Verification Email", systemImage: "paperplane.circle.fill")
                        }
                    }
                }

                // MARK: - Support
                Section("Support") {
                    Button(action: openHelpAndSupport) {
                        HStack {
                            Label("Help & Support", systemImage: "questionmark.circle")
                            Spacer()
                            Image(systemName: "envelope")
                                .foregroundColor(.blue)
                        }
                    }
                    .foregroundColor(.primary)
                }

                // MARK: - Account Management
                Section("Account") {
                    Button { showSignOutAlert = true } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.orange)
                    }

                    Button { showDeleteAccountAlert = true } label: {
                        Label("Delete Account", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                }

                // MARK: - App Info
                Section("App Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    Button { showPrivacyPolicy = true } label: {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Add scrollable bottom breathing room above the custom tab bar overlay.
                Color.clear
                    .frame(height: 140)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
        // Alerts
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) { authManager.signOut() }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { Task { await authManager.deleteAccount() } }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
        .alert("Email Verification Sent", isPresented: $showEmailVerificationSent) {
            Button("OK") {}
        } message: {
            Text("Please check your email and click the verification link.")
        }
        // Sheets
        .sheet(isPresented: $showEditProfile) { EditProfileView().sheetStyle() }
        .sheet(isPresented: $showEmailVerification) { EmailVerificationView().sheetStyle() }
        .sheet(isPresented: $showPrivacyPolicy) { PrivacyPolicyView().sheetStyle() }
        .sheet(isPresented: $showPaywall) { PaywallView(source: "pro_feature").sheetStyle() }
        .task {
            await subscriptionManager.loadProducts()
        }
    }

    // MARK: - Help Support

    @MainActor private func openHelpAndSupport() {
        let subject = "Stoqly Support Request"
        let body = """
        Hello Stoqly Support Team,

        Device: \(UIDevice.current.model)
        iOS Version: \(UIDevice.current.systemVersion)
        App Version: 1.0.0
        Plan: \(subscriptionManager.isPro ? "Pro" : "Free")

        Please describe your issue:

        """
        let mailtoString = "mailto:\(HelpAndSupport.supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if let url = URL(string: mailtoString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            UIPasteboard.general.string = HelpAndSupport.supportEmail
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared
    @State private var displayName = ""
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile Information") {
                    TextField("Display Name", text: $displayName)
                        .textContentType(.name)
                }
                Section {
                    Button("Save Changes") {
                        Task {
                            isLoading = true
                            await authManager.updateProfile(displayName: displayName.isEmpty ? nil : displayName)
                            isLoading = false
                            if authManager.errorMessage == nil { dismiss() }
                        }
                    }
                    .disabled(displayName.isEmpty || isLoading)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear { displayName = authManager.currentUser?.displayName ?? "" }
        .alert("Error", isPresented: $authManager.showError) {
            Button("OK") {}
        } message: {
            Text(authManager.errorMessage ?? "An error occurred")
        }
    }
}

#Preview {
    ProfileView()
}
