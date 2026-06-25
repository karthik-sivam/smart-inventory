import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    static let dailySummaryEnabledKey = "stoqly_dailySummaryEnabled"
    static let dailySummaryHourKey    = "stoqly_dailySummaryHour"
    static let dailySummaryMinuteKey  = "stoqly_dailySummaryMinute"

    private init() {}

    func requestPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
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

    func scheduleLowStockAlert(for item: InventoryItem) {
        let content = UNMutableNotificationContent()
        content.title = "Low Stock: \(item.name)"
        content.body = "\(item.currentQuantity) \(item.uom?.symbol ?? "units") remaining in \(item.storage?.name ?? "storage")"
        content.sound = .default

        // Reuse one request per item so we update instead of stacking duplicates.
        // Fire after 1 hour in the background — long enough that the user won't
        // trigger it just by briefly switching apps.
        let identifier = "low-stock-\(item.id.uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3600, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule low stock alert: \(error.localizedDescription)")
            }
        }
    }

    func checkAndNotifyLowStock(items: [InventoryItem]) {
        let now = Date()
        let defaults = UserDefaults.standard
        let cooldownSeconds: TimeInterval = 86400 // 24 hours per item

        for item in items where item.isLowStock && !item.isOutOfStock {
            let key = "stoqly-notified-\(item.id.uuidString)"
            if let lastNotified = defaults.object(forKey: key) as? Date,
               now.timeIntervalSince(lastNotified) < cooldownSeconds {
                continue // Skip — already notified within the last 24 hours
            }
            defaults.set(now, forKey: key)
            scheduleLowStockAlert(for: item)
        }
    }

    func scheduleDailySummary(hour: Int, minute: Int, lowStockCount: Int, expiringCount: Int) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["stoqly-daily-summary"]
        )
        guard lowStockCount > 0 || expiringCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Stoqly Daily Summary"
        var parts: [String] = []
        if lowStockCount > 0 {
            parts.append("\(lowStockCount) item\(lowStockCount == 1 ? "" : "s") low/out of stock")
        }
        if expiringCount > 0 {
            parts.append("\(expiringCount) expiring soon")
        }
        content.body = parts.joined(separator: " · ")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(
            identifier: "stoqly-daily-summary",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule daily summary: \(error.localizedDescription)")
            }
        }
    }

    func cancelDailySummary() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["stoqly-daily-summary"]
        )
    }
}
