//
//  AuthManager.swift
//  AITest
//
//  Created by Karthikeyan Paramasivam on 7/19/25.
//

import Foundation
@preconcurrency import FirebaseAuth
import SwiftUI
@preconcurrency import GoogleSignIn
import CryptoKit
import AuthenticationServices

@MainActor
class AuthManager: ObservableObject {
    @Published var currentUser: User?
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showError = false
    
    static let shared = AuthManager()

    private var currentNonce: String?

    /// Display name for activity audit trail and team invites.
    var actorName: String {
        if let name = currentUser?.displayName?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
            return name
        }
        return currentUser?.email ?? "Unknown"
    }

    private init() {
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        _ = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor [weak self] in
                self?.currentUser = user
                self?.isAuthenticated = user != nil
                // Attribute this (possibly restored) session to the user in Amplitude.
                // Firebase persists logins, so returning users never re-hit sign-in;
                // this ensures every authenticated session carries user_id + email.
                if let user = user {
                    AnalyticsManager.shared.identify(
                        userId: user.uid,
                        email: user.email,
                        isPro: SubscriptionManager.shared.isPro
                    )
                }
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

            Task { await SubscriptionManager.shared.applyManualProGrantIfNeeded() }

            // Track completion for ad system
            // Analytics
            AnalyticsManager.shared.track(.userSignedUp(method: "email"))
            AnalyticsManager.shared.identify(userId: result.user.uid, email: result.user.email, isPro: false, signupMethod: "email")

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

            Task { await SubscriptionManager.shared.applyManualProGrantIfNeeded() }

            // Analytics
            AnalyticsManager.shared.track(.userSignedIn(method: "email"))
            AnalyticsManager.shared.identify(userId: result.user.uid, email: result.user.email, isPro: false, signupMethod: "email")

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

            Task { await SubscriptionManager.shared.applyManualProGrantIfNeeded() }

            // Analytics
            AnalyticsManager.shared.track(.userSignedIn(method: "google"))
            AnalyticsManager.shared.identify(userId: authResult.user.uid, email: authResult.user.email, isPro: false, signupMethod: "google")

            print("User signed in with Google successfully: \(authResult.user.email ?? "")")
        } catch {
            handleAuthError(error)
        }
        
        isLoading = false
    }

    // MARK: - Sign in with Apple

    func prepareAppleSignIn() -> String {
        let nonce = randomNonceString()
        currentNonce = nonce
        return sha256(nonce)
    }

    func signInWithApple(authorization: ASAuthorization) async {
        guard
            let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let nonce = currentNonce,
            let appleIDToken = appleCredential.identityToken,
            let idTokenString = String(data: appleIDToken, encoding: .utf8)
        else {
            errorMessage = "Unable to fetch identity token from Apple."
            showError = true
            return
        }
        let firebaseCredential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await Auth.auth().signIn(with: firebaseCredential)
            // Save display name immediately — Apple only sends fullName on the FIRST sign-in ever.
            // On all subsequent sign-ins it is nil, so this is the only chance to capture it.
            if let fullName = appleCredential.fullName,
               let givenName = fullName.givenName {
                let displayName = [givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !displayName.isEmpty {
                    let changeRequest = result.user.createProfileChangeRequest()
                    changeRequest.displayName = displayName
                    try? await changeRequest.commitChanges()
                }
            }
            currentUser = Auth.auth().currentUser // refresh after potential profile update
            isAuthenticated = true

            Task { await SubscriptionManager.shared.applyManualProGrantIfNeeded() }

            // Analytics
            AnalyticsManager.shared.track(.userSignedIn(method: "apple"))
            AnalyticsManager.shared.identify(userId: result.user.uid, email: result.user.email, isPro: false, signupMethod: "apple")
        } catch {
            handleAuthError(error)
        }
    }

    private func randomNonceString(length: Int = 32) -> String {
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        while remainingLength > 0 {
            let randoms: [UInt8] = (0 ..< 16).map { _ in
                var random: UInt8 = 0
                _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
                return random
            }
            randoms.forEach { random in
                if remainingLength == 0 { return }
                if random < charset.count {
                    result.append(charset[Int(random)])
                    remainingLength -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashedData = SHA256.hash(data: inputData)
        return hashedData.compactMap { String(format: "%02x", $0) }.joined()
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
            TeamManager.shared.reset()

            // Analytics — reset before clearing userId so the event is attributed correctly
            AnalyticsManager.shared.track(.userSignedOut)
            AnalyticsManager.shared.reset()

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


