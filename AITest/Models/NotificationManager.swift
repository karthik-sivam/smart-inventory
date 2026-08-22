import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    /// Legacy keys — migrated into `NotificationPrefs` on first launch (S33).
    static let dailySummaryEnabledKey = "stoqly_dailySummaryEnabled"
    static let dailySummaryHourKey    = "stoqly_dailySummaryHour"
    static let dailySummaryMinuteKey  = "stoqly_dailySummaryMinute"

    private static let dailyDigestIdentifier = "stoqly-daily-digest"

    private init() {}

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            AnalyticsManager.shared.track(.permissionResult(type: "notifications", granted: granted))
            if let error {
                print("Notification permission error: \(error.localizedDescription)")
                return
            }

            guard granted else { return }
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - S33 Phase 1 — aggregated local daily digest

    /// Recomputes and schedules the single on-device daily digest (Phase 1).
    func refreshLocalDigestSchedule(items: [InventoryItem]) {
        let prefs = NotificationPrefsManager.shared.prefs
        cancelDailyDigest()

        guard prefs.masterEnabled else { return }
        guard prefs.lowStockDaily || prefs.expiryDaily else { return }

        let lowStockCount = prefs.lowStockDaily
            ? items.filter { $0.isLowStock || $0.isOutOfStock }.count
            : 0
        let expiringCount = prefs.expiryDaily
            ? items.filter { $0.isExpiringSoon || $0.isExpired }.count
            : 0
        guard lowStockCount > 0 || expiringCount > 0 else { return }

        scheduleLocalDailyDigest(
            hour: prefs.preferredHour,
            minute: prefs.preferredMinute,
            lowStockCount: lowStockCount,
            expiringCount: expiringCount
        )
    }

    func scheduleLocalDailyDigest(hour: Int, minute: Int, lowStockCount: Int, expiringCount: Int) {
        cancelDailyDigest()

        let content = UNMutableNotificationContent()
        content.title = L("notifications.digest.title", "Stoqly Daily Summary")
        var parts: [String] = []
        if lowStockCount > 0 {
            let fmt = lowStockCount == 1
                ? L("notifications.digest.lowOne", "1 item low or out of stock")
                : String(format: L("notifications.digest.lowMany", "%lld items low or out of stock"), lowStockCount)
            parts.append(fmt)
        }
        if expiringCount > 0 {
            let fmt = expiringCount == 1
                ? L("notifications.digest.expiryOne", "1 item expiring soon")
                : String(format: L("notifications.digest.expiryMany", "%lld items expiring soon"), expiringCount)
            parts.append(fmt)
        }
        content.body = parts.joined(separator: " · ")
        content.sound = .default

        let route: String = if lowStockCount > 0 {
            NotificationRoute.reorder.rawValue
        } else {
            NotificationRoute.expiry.rawValue
        }
        content.userInfo = [
            "type": "daily_digest",
            "route": route,
            "low_stock_count": lowStockCount,
            "expiring_count": expiringCount
        ]

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: Self.dailyDigestIdentifier,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule daily digest: \(error.localizedDescription)")
            }
        }
    }

    func cancelDailyDigest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.dailyDigestIdentifier, "stoqly-daily-summary"]
        )
    }

    // MARK: - Deprecated per-item alerts (S33 — replaced by aggregated digest)

    /// Deprecated S33: per-item low-stock spam replaced by aggregated daily digest.
    func checkAndNotifyLowStock(items: [InventoryItem]) {
        refreshLocalDigestSchedule(items: items)
    }

    @available(*, deprecated, message: "Use refreshLocalDigestSchedule instead (S33)")
    func scheduleLowStockAlert(for item: InventoryItem) {
        // Intentionally no-op — Phase 1 uses aggregated digest only.
    }

    @available(*, deprecated, message: "Use scheduleLocalDailyDigest instead (S33)")
    func scheduleDailySummary(hour: Int, minute: Int, lowStockCount: Int, expiringCount: Int) {
        scheduleLocalDailyDigest(hour: hour, minute: minute, lowStockCount: lowStockCount, expiringCount: expiringCount)
    }

    @available(*, deprecated, message: "Use cancelDailyDigest instead (S33)")
    func cancelDailySummary() {
        cancelDailyDigest()
    }
}
