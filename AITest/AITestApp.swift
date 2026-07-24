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
import FirebaseInAppMessaging
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
            ItemTemplate.self,
            SaleEvent.self,
            InventoryMovement.self
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
    @StateObject private var localizationManager = LocalizationManager.shared

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
                .environmentObject(localizationManager)
                .environment(\.locale, localizationManager.effectiveLocale())
                .environment(\.layoutDirection, localizationManager.layoutDirection)
                .id(localizationManager.refreshID)
                .onAppear {
                    AppWindowCoordinator.register(
                        modelContainer: sharedModelContainer,
                        currencyManager: currencyManager
                    )
                }
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
                    // Restore StoreKit + re-check Firestore manualProUntil on launch.
                    // applyManualProGrantIfNeeded() refreshes StoreKit entitlements after
                    // syncing the grant flag so expired/removed grants do not stick.
                    await subscriptionManager.applyManualProGrantIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    // Re-fetch manual grant + StoreKit when returning to foreground so
                    // revoked/expired manualProUntil clears Pro without requiring relaunch.
                    Task { await subscriptionManager.applyManualProGrantIfNeeded() }
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
    static let stoqlyAnnouncement = Notification.Name("stoqly.announcement")
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
        Task { @MainActor in
            FCMTopicManager.syncRegistrationIfSignedIn(token: fcmToken)
        }
    }
}

private extension AppDelegate {
    nonisolated func postAnnouncementIfNeeded(from userInfo: [AnyHashable: Any]) {
        guard (userInfo["type"] as? String) == "announcement" else { return }
        let title = userInfo["title"] as? String ?? userInfo["gcm.notification.title"] as? String ?? ""
        let message = userInfo["message"] as? String ?? userInfo["gcm.notification.body"] as? String ?? ""
        let urlString = userInfo["url"] as? String
        guard !title.isEmpty || !message.isEmpty else { return }
        Task { @MainActor in
            var payload: [AnyHashable: Any] = [
                "type": "announcement",
                "title": title,
                "message": message
            ]
            if let urlString { payload["url"] = urlString }
            NotificationCenter.default.post(
                name: .stoqlyAnnouncement,
                object: nil,
                userInfo: payload
            )
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        postAnnouncementIfNeeded(from: notification.request.content.userInfo)
        completionHandler([.banner, .badge, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        postAnnouncementIfNeeded(from: response.notification.request.content.userInfo)
        completionHandler()
    }
}
