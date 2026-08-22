import Foundation

/// Per-user notification preferences (S33 Phase 1 — iOS + Firestore sync).
struct NotificationPrefs: Codable, Equatable {
    var masterEnabled: Bool = true
    var lowStockDaily: Bool = true
    var expiryDaily: Bool = true
    var weeklySummary: Bool = true
    var monthlyCount: Bool = true
    var announcements: Bool = true
    var preferredHour: Int = 18
    var preferredMinute: Int = 0
    var timezone: String = TimeZone.current.identifier

    static let storageKey = "stoqly_notificationPrefs_v1"

    var preferredTimeDate: Date {
        Calendar.current.date(from: DateComponents(hour: preferredHour, minute: preferredMinute)) ?? Date()
    }
}

enum NotificationRoute: String {
    case reorder
    case expiry
    case count
    case reports

    static let notificationName = Notification.Name("stoqly.notificationRoute")
}

@MainActor
final class NotificationPrefsManager: ObservableObject {
    static let shared = NotificationPrefsManager()

    @Published private(set) var prefs: NotificationPrefs

    private init() {
        prefs = Self.loadFromDefaults()
        migrateLegacyDailySummaryIfNeeded()
    }

    func update(_ transform: (inout NotificationPrefs) -> Void) {
        var next = prefs
        transform(&next)
        next.timezone = TimeZone.current.identifier
        guard next != prefs else { return }
        prefs = next
        persistLocally()
        FirestoreManager.shared.syncNotificationPrefs(next)
    }

    func replace(with incoming: NotificationPrefs) {
        guard incoming != prefs else { return }
        prefs = incoming
        persistLocally()
    }

    private func persistLocally() {
        if let data = try? JSONEncoder().encode(prefs) {
            UserDefaults.standard.set(data, forKey: NotificationPrefs.storageKey)
        }
    }

    private static func loadFromDefaults() -> NotificationPrefs {
        guard
            let data = UserDefaults.standard.data(forKey: NotificationPrefs.storageKey),
            let decoded = try? JSONDecoder().decode(NotificationPrefs.self, from: data)
        else {
            return NotificationPrefs()
        }
        return decoded
    }

    /// Maps legacy end-of-day summary toggles into the unified prefs model.
    private func migrateLegacyDailySummaryIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: NotificationManager.dailySummaryEnabledKey) != nil else { return }
        guard defaults.data(forKey: NotificationPrefs.storageKey) == nil else { return }

        var migrated = NotificationPrefs()
        migrated.masterEnabled = defaults.bool(forKey: NotificationManager.dailySummaryEnabledKey)
        migrated.lowStockDaily = migrated.masterEnabled
        migrated.expiryDaily = migrated.masterEnabled
        migrated.preferredHour = defaults.integer(forKey: NotificationManager.dailySummaryHourKey)
        if migrated.preferredHour == 0 && !defaults.bool(forKey: NotificationManager.dailySummaryEnabledKey) {
            migrated.preferredHour = 18
        } else if migrated.preferredHour == 0 {
            migrated.preferredHour = 18
        }
        migrated.preferredMinute = defaults.integer(forKey: NotificationManager.dailySummaryMinuteKey)
        prefs = migrated
        persistLocally()
    }
}
