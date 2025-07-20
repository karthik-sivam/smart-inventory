//
//  AuthManager.swift
//  AITest
//
//  Created by Karthikeyan Paramasivam on 7/19/25.
//

import Foundation
import FirebaseAuth
import SwiftUI
import GoogleSignIn

@MainActor
class AuthManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    static let shared = AuthManager()
    
    private init() {
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            DispatchQueue.main.async {
                self?.currentUser = user
                self?.isAuthenticated = user != nil
            }
        }
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            currentUser = result.user
            isAuthenticated = true
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.userSignedUp)
            
            print("User signed up successfully: \(result.user.email ?? "")")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Sign In
    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            currentUser = result.user
            isAuthenticated = true
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.userSignedIn)
            
            print("User signed in successfully: \(result.user.email ?? "")")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Google Sign In
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        
        do {
            guard let presentingViewController = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController else {
                throw NSError(domain: "AuthError", code: AuthErrorCode.invalidCredential.rawValue, userInfo: [NSLocalizedDescriptionKey: "No presenting view controller found"])
            }
            
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            
            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(domain: "AuthError", code: AuthErrorCode.invalidCredential.rawValue, userInfo: [NSLocalizedDescriptionKey: "Failed to get ID token from Google"])
            }
            
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: result.user.accessToken.tokenString)
            let authResult = try await Auth.auth().signIn(with: credential)
            
            currentUser = authResult.user
            isAuthenticated = true
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.userSignedIn)
            
            print("User signed in with Google successfully: \(authResult.user.email ?? "")")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Sign Out
    func signOut() {
        do {
            // Sign out from Google
            GIDSignIn.sharedInstance.signOut()
            
            // Sign out from Firebase
            try Auth.auth().signOut()
            currentUser = nil
            isAuthenticated = false
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.userSignedOut)
            
            print("User signed out successfully")
        } catch {
            handleAuthError(error)
        }
    }
    
    // MARK: - Email Verification
    func sendEmailVerification() async {
        guard let user = currentUser else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await user.sendEmailVerification()
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.emailVerificationSent)
            
            print("Email verification sent to: \(user.email ?? "")")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    func reloadUser() async {
        guard let user = currentUser else { return }
        
        do {
            try await user.reload()
            // Update the current user reference
            currentUser = Auth.auth().currentUser
        } catch {
            handleAuthError(error)
        }
    }
    
    // MARK: - Forgot Password
    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.passwordResetRequested)
            
            print("Password reset email sent to: \(email)")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Delete Account
    func deleteAccount() async {
        guard let user = currentUser else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            try await user.delete()
            currentUser = nil
            isAuthenticated = false
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.accountDeleted)
            
            print("Account deleted successfully")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Update Profile
    func updateProfile(displayName: String? = nil, photoURL: URL? = nil) async {
        guard let user = currentUser else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let changeRequest = user.createProfileChangeRequest()
            if let displayName = displayName {
                changeRequest.displayName = displayName
            }
            if let photoURL = photoURL {
                changeRequest.photoURL = photoURL
            }
            
            try await changeRequest.commitChanges()
            
            // Track completion for ad system
            AdManager.shared.recordCompletion(event: AdManager.CompletionEvent.profileUpdated)
            
            print("Profile updated successfully")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }
    
    // MARK: - Error Handling
    private func handleAuthError(_ error: Error) {
        let authError = error as NSError
        
        switch authError.code {
        case AuthErrorCode.wrongPassword.rawValue:
            errorMessage = "Incorrect password. Please try again."
        case AuthErrorCode.invalidEmail.rawValue:
            errorMessage = "Invalid email address. Please check your email."
        case AuthErrorCode.emailAlreadyInUse.rawValue:
            errorMessage = "An account with this email already exists."
        case AuthErrorCode.weakPassword.rawValue:
            errorMessage = "Password is too weak. Please choose a stronger password."
        case AuthErrorCode.userNotFound.rawValue:
            errorMessage = "No account found with this email address."
        case AuthErrorCode.tooManyRequests.rawValue:
            errorMessage = "Too many failed attempts. Please try again later."
        case AuthErrorCode.networkError.rawValue:
            errorMessage = "Network error. Please check your connection."
        case AuthErrorCode.invalidCredential.rawValue:
            errorMessage = "Invalid credentials. Please try again."
        case AuthErrorCode.accountExistsWithDifferentCredential.rawValue:
            errorMessage = "An account already exists with the same email address but different sign-in credentials."
        default:
            errorMessage = "An error occurred. Please try again."
        }
        
        showError = true
        print("Auth error: \(error.localizedDescription)")
    }
    
    // MARK: - Validation
    func validateEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    func validatePassword(_ password: String) -> Bool {
        return password.count >= 6
    }
}


