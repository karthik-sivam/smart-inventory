import Foundation
import FacebookCore

/// Thin wrapper for Meta (Facebook) App Events — keeps SDK imports in one place.
enum MetaAppEvents {
    static func configureAutoLogging() {
        Settings.shared.isAutoLogAppEventsEnabled = true
    }

    static func setAdvertiserTrackingEnabled(_ enabled: Bool) {
        Settings.shared.isAdvertiserTrackingEnabled = enabled
    }

    static func activateApp() {
        AppEvents.shared.activateApp()
    }

    static func logCompletedRegistration() {
        AppEvents.shared.logEvent(.completedRegistration)
    }

    static func logPurchase(amount: Double, currency: String) {
        AppEvents.shared.logPurchase(amount: amount, currency: currency)
    }
}
