import FirebaseMessaging
import FirebaseAuth

enum FCMTopicManager {
    private static let allUsersTopic = "all_users"
    private static let proTopic = "pro"
    private static let freeTopic = "free"
    private static let tokenDefaultsKey = "fcmToken"

    @MainActor
    static func syncRegistrationIfSignedIn(token: String? = nil) {
        let resolved = token ?? UserDefaults.standard.string(forKey: tokenDefaultsKey)
        guard let resolved, let uid = Auth.auth().currentUser?.uid else { return }
        FirestoreManager.shared.writeFCMToken(uid: uid, token: resolved)
        subscribeAllUsers()
        syncProTopics(isPro: SubscriptionManager.shared.isPro)
    }

    static func subscribeAllUsers() {
        Messaging.messaging().subscribe(toTopic: allUsersTopic) { error in
            if let error {
                print("[FCM] Failed to subscribe to \(allUsersTopic): \(error.localizedDescription)")
            }
        }
    }

    static func syncProTopics(isPro: Bool) {
        if isPro {
            Messaging.messaging().subscribe(toTopic: proTopic) { _ in }
            Messaging.messaging().unsubscribe(fromTopic: freeTopic) { _ in }
        } else {
            Messaging.messaging().subscribe(toTopic: freeTopic) { _ in }
            Messaging.messaging().unsubscribe(fromTopic: proTopic) { _ in }
        }
    }
}
