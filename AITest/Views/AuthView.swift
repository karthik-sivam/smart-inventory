import SwiftUI

struct AuthView: View {
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSignUp = false
    @State private var showForgotPassword = false
    @State private var showSuccessMessage = false
    @State private var successMessage = ""
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.8)]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 30) {
                        // Header
                        VStack(spacing: 16) {
                            Image(systemName: "cube.box.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.white)
                            
                            Text("Smart Inventory")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                            
                            Text(isSignUp ? "Create your account" : "Welcome back")
                                .font(.title3)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.top, 50)
                        
                        // Auth Form
                        VStack(spacing: 20) {
                            // Email Field
                            AuthTextField(
                                text: $email,
                                placeholder: "Email",
                                icon: "envelope.fill"
                            )
                            
                            // Password Field
                            AuthTextField(
                                text: $password,
                                placeholder: "Password",
                                icon: "lock.fill",
                                isSecure: true
                            )
                            
                            // Confirm Password (Sign Up only)
                            if isSignUp {
                                AuthTextField(
                                    text: $confirmPassword,
                                    placeholder: "Confirm Password",
                                    icon: "lock.fill",
                                    isSecure: true
                                )
                            }
                            
                            // Action Button
                            Button(action: performAuthAction) {
                                HStack {
                                    if authManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: isSignUp ? "person.badge.plus" : "arrow.right.circle.fill")
                                    }
                                    
                                    Text(authManager.isLoading ? "Please wait..." : (isSignUp ? "Sign Up" : "Sign In"))
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    isFormValid ? Color.green : Color.gray
                                )
                                .cornerRadius(12)
                            }
                            .disabled(!isFormValid || authManager.isLoading)
                            
                            // Divider
                            HStack {
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.white.opacity(0.3))
                                
                                Text("OR")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                    .padding(.horizontal, 16)
                                
                                Rectangle()
                                    .frame(height: 1)
                                    .foregroundColor(.white.opacity(0.3))
                            }
                            
                            // Google Sign In Button
                            Button(action: signInWithGoogle) {
                                HStack {
                                    if authManager.isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "globe")
                                            .font(.title2)
                                            .foregroundColor(.blue)
                                    }
                                    
                                    Text(authManager.isLoading ? "Please wait..." : "Continue with Google")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
                            }
                            .disabled(authManager.isLoading)
                            
                            // Forgot Password (Sign In only)
                            if !isSignUp {
                                Button("Forgot Password?") {
                                    showForgotPassword = true
                                }
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.8))
                            }
                        }
                        .padding(.horizontal, 30)
                        
                        // Toggle Sign In/Sign Up
                        VStack(spacing: 12) {
                            Divider()
                                .background(Color.white.opacity(0.3))
                            
                            Button(action: { isSignUp.toggle() }) {
                                HStack {
                                    Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                                        .foregroundColor(.white.opacity(0.8))
                                    
                                    Text(isSignUp ? "Sign In" : "Sign Up")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding(.horizontal, 30)
                        
                        Spacer(minLength: 50)
                    }
                }
            }
        }
        .alert("Error", isPresented: $authManager.showError) {
            Button("OK") { }
        } message: {
            Text(authManager.errorMessage ?? "An error occurred")
        }
        .alert("Success", isPresented: $showSuccessMessage) {
            Button("OK") { }
        } message: {
            Text(successMessage)
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView()
        }
    }
    
    private var isFormValid: Bool {
        let emailValid = authManager.validateEmail(email)
        let passwordValid = authManager.validatePassword(password)
        
        if isSignUp {
            let confirmPasswordValid = password == confirmPassword && !confirmPassword.isEmpty
            return emailValid && passwordValid && confirmPasswordValid
        } else {
            return emailValid && passwordValid
        }
    }
    
    private func performAuthAction() {
        Task {
            if isSignUp {
                await authManager.signUp(email: email, password: password)
            } else {
                await authManager.signIn(email: email, password: password)
            }
        }
    }
    
    private func signInWithGoogle() {
        Task {
            await authManager.signInWithGoogle()
        }
    }
}

struct AuthTextField: View {
    @Binding var text: String
    let placeholder: String
    let icon: String
    var isSecure: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.gray)
                .frame(width: 20)
            
            if isSecure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)
    }
}

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var authManager = AuthManager.shared
    @State private var email = ""
    @State private var showSuccessMessage = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "lock.rotation")
                        .font(.system(size: 50))
                        .foregroundColor(.blue)
                    
                    Text("Reset Password")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Enter your email address and we'll send you a link to reset your password.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 50)
                
                // Email Field
                AuthTextField(
                    text: $email,
                    placeholder: "Email",
                    icon: "envelope.fill"
                )
                .padding(.horizontal, 30)
                
                // Reset Button
                Button(action: resetPassword) {
                    HStack {
                        if authManager.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                        
                        Text(authManager.isLoading ? "Sending..." : "Send Reset Link")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        authManager.validateEmail(email) ? Color.blue : Color.gray
                    )
                    .cornerRadius(12)
                }
                .disabled(!authManager.validateEmail(email) || authManager.isLoading)
                .padding(.horizontal, 30)
                
                Spacer()
            }
            .navigationTitle("Forgot Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Error", isPresented: $authManager.showError) {
            Button("OK") { }
        } message: {
            Text(authManager.errorMessage ?? "An error occurred")
        }
        .alert("Success", isPresented: $showSuccessMessage) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Password reset email sent! Please check your inbox.")
        }
    }
    
    private func resetPassword() {
        Task {
            await authManager.resetPassword(email: email)
            if authManager.errorMessage == nil {
                showSuccessMessage = true
            }
        }
    }
}

#Preview {
    AuthView()
} 