//
//  AITestApp.swift
//  AITest — Stoqly
//
//  Created by Karthikeyan Paramasivam
//

import SwiftUI
import SwiftData
import CoreSpotlight
import Firebase
import FirebaseAuth
import FirebaseMessaging
import GoogleSignIn
import UserNotifications
import FirebaseFirestore

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
struct SmartInventoryApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - SwiftData Container

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Storage.self,
            InventoryItem.self,
            UOM.self,
            InventoryCount.self,
            ActivityEvent.self,
            InventoryBatch.self,
            TeamMember.self,
            ItemTemplate.self
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
    @StateObject private var teamManager = TeamManager.shared

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
                .environmentObject(teamManager)
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
                .onContinueUserActivity(CSSearchableItemActionType) { activity in
                    guard let id = activity.userInfo?[CSSearchableItemActivityIdentifier] as? String else { return }
                    NotificationCenter.default.post(
                        name: .spotlightItemSelected,
                        object: nil,
                        userInfo: ["itemID": id]
                    )
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

extension Notification.Name {
    static let spotlightItemSelected = Notification.Name("stoqly.spotlightItemSelected")
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

        // Enable offline persistence so writes queue locally when offline
        // and sync automatically when connectivity is restored.
        // Do not remove — required for Phase 4 multi-user sync.
        let firestoreSettings = FirestoreSettings()
        firestoreSettings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = firestoreSettings

        // 2. Google Sign-In
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        } else {
            print("⚠️  GoogleService-Info.plist not found or CLIENT_ID missing.")
        }

        // 3. Crashlytics — automatically captures crashes after FirebaseApp.configure()
        //    No additional setup needed here. Ensure the Run Script build phase is added in Xcode:
        //    Target → Build Phases → "+" → New Run Script Phase → paste:
        //    "${BUILD_DIR%Build/*}SourcePackages/checkouts/firebase-ios-sdk/Crashlytics/run"
        //    Then add input files:
        //      ${DWARF_DSYM_FOLDER_PATH}/${DWARF_DSYM_FILE_NAME}/Contents/Resources/DWARF/${TARGET_NAME}
        //      $(SRCROOT)/$(BUILT_PRODUCTS_DIR)/$(INFOPLIST_PATH)

        // 4. Amplitude — product analytics
        if let amplitudeKey = SecretsManager.amplitudeAPIKey {
            AnalyticsManager.shared.configure(apiKey: amplitudeKey)
        } else {
            #if DEBUG
            print("⚠️  Amplitude: AMPLITUDE_API_KEY missing from Secrets.plist — analytics disabled.")
            #endif
        }

        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        #if DEBUG
        print("🔥 Firebase configured. Crashlytics active (debug symbols uploaded on archive).")
        #endif

        // 4. Firestore — persistence configured immediately after FirebaseApp.configure() above.

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

extension AppDelegate: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        UserDefaults.standard.set(fcmToken, forKey: "fcmToken")
        #if DEBUG
        print("📲 FCM token refreshed: \(fcmToken)")
        #endif
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }
}
