import SwiftUI
import UserNotifications
import UIKit

@MainActor
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

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
        let identifier = "low-stock-\(item.id.uuidString)"
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to schedule low stock alert: \(error.localizedDescription)")
            }
        }
    }

    func checkAndNotifyLowStock(items: [InventoryItem]) {
        for item in items where item.isLowStock && !item.isOutOfStock {
            scheduleLowStockAlert(for: item)
        }
    }
}
