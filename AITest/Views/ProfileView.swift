import SwiftUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var showSignOutAlert = false
    @State private var showDeleteAccountAlert = false
    @State private var showEditProfile = false
    @State private var showEmailVerificationSent = false
    @State private var showEmailVerification = false
    @State private var showPrivacyPolicy = false
    
    var body: some View {
        NavigationView {
            List {
                // User Info Section
                Section {
                    HStack(spacing: 16) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 60, height: 60)
                            .overlay(
                                Text(String(authManager.currentUser?.email?.prefix(1).uppercased() ?? "U"))
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.currentUser?.displayName ?? "User")
                                .font(.headline)
                                .fontWeight(.semibold)
                            
                            Text(authManager.currentUser?.email ?? "")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            if let emailVerified = authManager.currentUser?.isEmailVerified {
                                HStack(spacing: 4) {
                                    Image(systemName: emailVerified ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundColor(emailVerified ? .green : .orange)
                                    
                                    Text(emailVerified ? "Email Verified" : "Email Not Verified")
                                        .font(.caption)
                                        .foregroundColor(emailVerified ? .green : .orange)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        VStack(spacing: 8) {
                            Button(action: { showEditProfile = true }) {
                                Image(systemName: "pencil.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                            
                            Button(action: {
                                Task {
                                    await authManager.reloadUser()
                                }
                            }) {
                                Image(systemName: "arrow.clockwise.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                
                // Email Verification Section (only show if email not verified)
                if let emailVerified = authManager.currentUser?.isEmailVerified, !emailVerified {
                    Section("Email Verification") {
                        Button(action: { showEmailVerification = true }) {
                            HStack {
                                Image(systemName: "envelope.circle.fill")
                                    .foregroundColor(.blue)
                                Text("Verify Email Address")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Button(action: {
                            Task {
                                await authManager.sendEmailVerification()
                                if authManager.errorMessage == nil {
                                    showEmailVerificationSent = true
                                }
                            }
                        }) {
                            HStack {
                                Image(systemName: "paperplane.circle.fill")
                                    .foregroundColor(.green)
                                Text("Resend Verification Email")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                }
                
                // Help & Support Section
                Section("Support") {
                    Button(action: openHelpAndSupport) {
                        HStack {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.blue)
                            Text("Help & Support")
                            Spacer()
                            Image(systemName: "envelope")
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                // Account Management Section
                Section("Account Management") {
                    Button(action: { showSignOutAlert = true }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.orange)
                            Text("Sign Out")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Button(action: { showDeleteAccountAlert = true }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Delete Account")
                                .foregroundColor(.red)
                        }
                    }
                }
                
                // App Info Section
                Section("App Info") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build")
                        Spacer()
                        Text("1")
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: { showPrivacyPolicy = true }) {
                        HStack {
                            Text("Privacy Policy")
                            Spacer()
                            Image(systemName: "doc.text")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
        }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Delete Account", isPresented: $showDeleteAccountAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await authManager.deleteAccount()
                }
            }
        } message: {
            Text("This action cannot be undone. All your data will be permanently deleted.")
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
        }
        .sheet(isPresented: $showEmailVerification) {
            EmailVerificationView()
        }
        .sheet(isPresented: $showPrivacyPolicy) {
            PrivacyPolicyView()
        }
        .alert("Email Verification Sent", isPresented: $showEmailVerificationSent) {
            Button("OK") { }
        } message: {
            Text("Please check your email and click the verification link. You can refresh your profile to check if verification is complete.")
        }
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared
    @State private var displayName = ""
    @State private var isLoading = false
    
    var body: some View {
        NavigationView {
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
                            if authManager.errorMessage == nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(displayName.isEmpty || isLoading)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            displayName = authManager.currentUser?.displayName ?? ""
        }
        .alert("Error", isPresented: $authManager.showError) {
            Button("OK") { }
        } message: {
            Text(authManager.errorMessage ?? "An error occurred")
        }
    }
}



    private func openHelpAndSupport() {
        let subject = "Smart Inventory Support Request"
        let body = """
        Hello Smart Inventory Support Team,
        
        I need assistance with the Smart Inventory app.
        
        Device: \(UIDevice.current.model)
        iOS Version: \(UIDevice.current.systemVersion)
        App Version: 1.0.0
        
        Please describe your issue below:
        
        """
        
        let mailtoString = "mailto:\(HelpAndSupport.supportEmail)?subject=\(subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&body=\(body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: mailtoString) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Fallback: copy email to clipboard
                UIPasteboard.general.string = HelpAndSupport.supportEmail
                // You could show an alert here to inform the user that the email was copied
            }
        }
    }

#Preview {
    ProfileView()
} 
