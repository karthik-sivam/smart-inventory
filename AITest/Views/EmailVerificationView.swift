import SwiftUI
import FirebaseAuth

struct EmailVerificationView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared
    @State private var showResendAlert = false
    @State private var showSuccessAlert = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 30) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                        
                        Text("Verify Your Email")
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("We've sent a verification link to:")
                            .font(.body)
                            .foregroundColor(.secondary)
                        
                        Text(authManager.currentUser?.email ?? "")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }
                    .padding(.top, 50)
                    
                    // Status Card
                    VStack(spacing: 16) {
                        HStack {
                            Image(systemName: authManager.currentUser?.isEmailVerified == true ? "checkmark.circle.fill" : "clock.circle.fill")
                                .font(.title2)
                                .foregroundColor(authManager.currentUser?.isEmailVerified == true ? .green : .orange)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(authManager.currentUser?.isEmailVerified == true ? "Email Verified" : "Verification Pending")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text(authManager.currentUser?.isEmailVerified == true ? "Your email has been successfully verified." : "Please check your email and click the verification link.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    
                    // Instructions
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to verify your email:")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(alignment: .leading, spacing: 12) {
                            InstructionStep(
                                number: "1",
                                text: "Check your email inbox (and spam folder)"
                            )
                            
                            InstructionStep(
                                number: "2",
                                text: "Look for an email from Smart Inventory"
                            )
                            
                            InstructionStep(
                                number: "3",
                                text: "Click the verification link in the email"
                            )
                            
                            InstructionStep(
                                number: "4",
                                text: "Return to the app and refresh your profile"
                            )
                        }
                    }
                    .padding(.horizontal)
                    
                    // Action Buttons
                    VStack(spacing: 16) {
                        // Refresh Button
                        Button(action: refreshVerificationStatus) {
                            HStack {
                                if authManager.isLoading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                                
                                Text(authManager.isLoading ? "Checking..." : "Refresh Status")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .disabled(authManager.isLoading)
                        
                        // Resend Button
                        if authManager.currentUser?.isEmailVerified != true {
                            Button(action: resendVerificationEmail) {
                                HStack {
                                    Image(systemName: "paperplane")
                                    
                                    Text("Resend Verification Email")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(12)
                            }
                            .disabled(authManager.isLoading)
                        }
                        
                        // Open Email App Button
                        Button(action: openEmailApp) {
                            HStack {
                                Image(systemName: "envelope")
                                
                                Text("Open Email App")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal)
                    
                    Spacer(minLength: 50)
                }
            }
        }
        .navigationTitle("Email Verification")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .alert("Verification Email Sent", isPresented: $showResendAlert) {
            Button("OK") { }
        } message: {
            Text("A new verification email has been sent to your email address.")
        }
        .alert("Email Verified!", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Your email has been successfully verified. You can now use all features of the app.")
        }
        .alert("Error", isPresented: $authManager.showError) {
            Button("OK") { }
        } message: {
            Text(authManager.errorMessage ?? "An error occurred")
        }
    }
    
    private func refreshVerificationStatus() {
        Task {
            await authManager.reloadUser()
            
            // Check if email was verified
            if authManager.currentUser?.isEmailVerified == true {
                showSuccessAlert = true
            }
        }
    }
    
    private func resendVerificationEmail() {
        Task {
            await authManager.sendEmailVerification()
            if authManager.errorMessage == nil {
                showResendAlert = true
            }
        }
    }
    
    private func openEmailApp() {
        if let email = authManager.currentUser?.email {
            let mailtoUrl = "mailto:\(email)"
            if let url = URL(string: mailtoUrl) {
                UIApplication.shared.open(url)
            }
        }
    }
}

struct InstructionStep: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.blue)
                .frame(width: 24, height: 24)
                .overlay(
                    Text(number)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
            
            Text(text)
                .font(.body)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview {
    EmailVerificationView()
} 