//
//  AITestApp.swift
//  AITest — Smart Inventory
//
//  Created by Karthikeyan Paramasivam
//

import SwiftUI
import SwiftData
import Firebase
import FirebaseAuth
import FirebaseMessaging
import GoogleSignIn
import UserNotifications

// MARK: - Add these Firebase packages in Xcode (they're already in firebase-ios-sdk):
//   Project → Package Dependencies → firebase-ios-sdk → already added ✓
//   Target → Build Phases → Link Binary With Libraries → Add:
//     • FirebaseFirestore          (cloud sync)
//     • FirebaseCrashlytics        (crash reporting)
//     • FirebaseAnalytics          (usage analytics)
//     • FirebaseMessaging          (push notifications — Phase 2)
//
// NOTE: FirebaseCrashlytics requires a Run Script Build Phase.
//   See XCODE_SETUP_GUIDE.md for step-by-step instructions.

@main
struct AITestApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - SwiftData Container

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Storage.self,
            InventoryItem.self,
            UOM.self,
            InventoryCount.self
        ])
        do {
            return try ModelContainer(for: schema)
        } catch {
            // SwiftData is fundamental — crash loudly so it surfaces in development.
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    // MARK: - Shared Managers

    @StateObject private var authManager = AuthManager.shared
    @StateObject private var currencyManager = CurrencyManager()
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @StateObject private var firestoreManager = FirestoreManager.shared
    @StateObject private var trackingManager = TrackingPermissionManager.shared
    @StateObject private var notificationManager = NotificationManager.shared

    // MARK: - App Scene

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(currencyManager)
                .environmentObject(subscriptionManager)
                .environmentObject(firestoreManager)
                .environmentObject(trackingManager)
                .environmentObject(notificationManager)
                .onOpenURL { url in
                    // Handle Google Sign-In redirect URLs
                    GIDSignIn.sharedInstance.handle(url)
                }
                .task {
                    // Request App Tracking Transparency permission after UI loads.
                    // This must happen AFTER the first screen is visible — Apple enforces this.
                    await trackingManager.requestPermissionIfNeeded()
                }
                .task {
                    // Restore StoreKit purchases on launch (handles renewals / reinstalls)
                    await subscriptionManager.refreshPurchaseStatus()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Refresh subscription status when app returns to foreground
                    Task { await subscriptionManager.refreshPurchaseStatus() }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - AppDelegate

/// Handles Firebase initialization and other app lifecycle callbacks.
/// Using UIApplicationDelegateAdaptor is the correct pattern for FirebaseCrashlytics
/// which requires early initialization before the SwiftUI lifecycle runs.
@MainActor
class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {

        // 1. Firebase — must be first
        FirebaseApp.configure()

        // 2. Google Sign-In
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        } else {
            print("⚠️  GoogleService-Info.plist not found or CLIENT_ID missing.")
        }

        // 3. Crashlytics — automatically captures crashes after FirebaseApp.configure()
        //    No additional setup needed here. Ensure the Run Script build phase is added.
        //    See XCODE_SETUP_GUIDE.md → Step 5.
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        #if DEBUG
        print("🔥 Firebase configured. Crashlytics active (debug symbols uploaded on archive).")
        #endif

        // 4. Firestore offline persistence
        //    Firestore caches data locally so the app works offline.
        //    This is enabled by default in the iOS SDK — no extra setup needed.

        return true
    }

    // Handle Google Sign-In redirect
    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: - Push Notifications

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        Messaging.messaging().appDidReceiveMessage(userInfo)
        return .newData
    }

}

extension AppDelegate: @preconcurrency MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        UserDefaults.standard.set(fcmToken, forKey: "fcmToken")
        #if DEBUG
        print("📲 FCM token refreshed: \(fcmToken)")
        #endif
    }
}

extension AppDelegate: @preconcurrency UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
