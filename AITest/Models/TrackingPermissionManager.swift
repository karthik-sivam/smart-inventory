import Foundation
import AppTrackingTransparency
import SwiftUI

/// Manages the App Tracking Transparency (ATT) permission prompt.
///
/// Apple REQUIRES this prompt before AdMob can serve personalized ads on iOS 14.5+.
/// Skipping this causes AdMob to show lower-value non-personalized ads (hurts revenue)
/// and Apple may reject the app if AdMob is detected without the NSUserTrackingUsageDescription
/// key in Info.plist.
///
/// SETUP REQUIRED in Xcode:
/// Target → Info → Custom iOS Target Properties → Add:
///   Key:   NSUserTrackingUsageDescription
///   Value: "Smart Inventory uses your advertising ID to show you relevant ads that
///           support the free version of this app."
@MainActor
class TrackingPermissionManager: ObservableObject {

    @Published var authorizationStatus: ATTrackingManager.AuthorizationStatus = .notDetermined
    @Published var hasResolved = false

    static let shared = TrackingPermissionManager()

    private init() {
        authorizationStatus = ATTrackingManager.trackingAuthorizationStatus
        hasResolved = authorizationStatus != .notDetermined
    }

    // MARK: - Public

    /// Request ATT permission. Call this once, after the main UI is visible.
    /// Automatically initializes AdMob once the user responds.
    func requestPermissionIfNeeded() async {
        let currentStatus = ATTrackingManager.trackingAuthorizationStatus

        // Already decided by the user previously — just init AdMob.
        if currentStatus != .notDetermined {
            authorizationStatus = currentStatus
            hasResolved = true
            AdManager.shared.initializeAfterTrackingDecision()
            return
        }

        // Give the UI a moment to fully render before presenting the system alert.
        try? await Task.sleep(nanoseconds: 800_000_000) // 0.8 seconds

        let status = await ATTrackingManager.requestTrackingAuthorization()
        authorizationStatus = status
        hasResolved = true

        // Always initialize AdMob — it works with or without tracking permission.
        // With permission: personalized ads (higher CPM).
        // Without: non-personalized ads (lower CPM but still revenue).
        AdManager.shared.initializeAfterTrackingDecision()

        switch status {
        case .authorized:
            print("ATT ✅ Authorized — personalized ads enabled.")
        case .denied:
            print("ATT ⚠️  Denied — non-personalized ads will show.")
        case .restricted:
            print("ATT ⚠️  Restricted — non-personalized ads will show.")
        case .notDetermined:
            print("ATT ❓ Status still not determined.")
        @unknown default:
            print("ATT ❓ Unknown status.")
        }
    }

    // MARK: - Computed

    var isAuthorized: Bool {
        authorizationStatus == .authorized
    }

    /// Human-readable description for settings/profile screens.
    var statusDescription: String {
        switch authorizationStatus {
        case .authorized:   return "Personalized ads enabled"
        case .denied:       return "Non-personalized ads only"
        case .restricted:   return "Restricted by device policy"
        case .notDetermined: return "Not yet requested"
        @unknown default:   return "Unknown"
        }
    }
}
