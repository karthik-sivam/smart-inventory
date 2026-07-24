import Foundation
import SwiftData

// ActivityEvent records discrete things that happened in the inventory.
// Phase 2 will add: Received, Sold, Damaged, Transferred, Adjusted.
// Phase 4 will populate performedBy with the signed-in user's display name.

@Model
final class ActivityEvent {
    var id: UUID
    var eventType: String
    var itemName: String
    var storageName: String
    var quantityBefore: Double?
    var quantityAfter: Double?
    var notes: String
    var performedBy: String?
    var occurredAt: Date

    init(
        eventType: String,
        itemName: String,
        storageName: String,
        quantityBefore: Double? = nil,
        quantityAfter: Double? = nil,
        notes: String = "",
        performedBy: String? = nil
    ) {
        self.id = UUID()
        self.eventType = eventType
        self.itemName = itemName
        self.storageName = storageName
        self.quantityBefore = quantityBefore
        self.quantityAfter = quantityAfter
        self.notes = notes
        self.performedBy = performedBy
        self.occurredAt = Date()
    }

    var displayDescription: String {
        let storage = storageName.isEmpty
            ? String(localized: "activity.noStorage", defaultValue: "No Storage")
            : storageName
        switch eventType {
        case "ItemAdded":
            return String(
                format: String(localized: "activity.addedTo", defaultValue: "Added to %@"),
                storage
            )
        case "ItemCounted":
            if quantityBefore == nil && quantityAfter == nil {
                return String(
                    format: String(localized: "activity.countRecordedIn", defaultValue: "Count recorded in %@"),
                    storage
                )
            }
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after = quantityAfter.map { $0.smartFormatted } ?? "?"
            return String(
                format: String(localized: "activity.countUpdated", defaultValue: "Count updated: %1$@ → %2$@"),
                before,
                after
            )
        case "ItemUpdated":
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after = quantityAfter.map { $0.smartFormatted } ?? "?"
            if before == after {
                return String(localized: "activity.itemDetailsUpdated", defaultValue: "Item details updated")
            }
            return String(
                format: String(localized: "activity.quantityChanged", defaultValue: "Quantity: %1$@ -> %2$@"),
                before,
                after
            )
        case "ItemDeleted":
            return String(
                format: String(localized: "activity.removedFrom", defaultValue: "Removed from %@"),
                storage
            )
        case "LowStockAlert":
            return String(localized: "activity.lowStockAlert", defaultValue: "Low stock alert triggered")
        case "StorageCreated":
            return String(localized: "activity.storageCreated", defaultValue: "Storage area created")
        case "SaleMade":
            if let before = quantityBefore, let after = quantityAfter {
                let soldQty = (before - after).smartFormatted
                return String(
                    format: String(localized: "activity.saleRecordedQty", defaultValue: "Sale recorded: %1$@ sold from %2$@"),
                    soldQty,
                    storage
                )
            }
            return String(
                format: String(localized: "activity.saleRecordedFrom", defaultValue: "Sale recorded from %@"),
                storage
            )
        case "MovementLogged":
            if let before = quantityBefore, let after = quantityAfter {
                let change = after - before
                let sign = change >= 0 ? "+" : ""
                return String(
                    format: String(localized: "activity.movementChange", defaultValue: "Movement: %1$@%2$@ in %3$@"),
                    sign,
                    change.smartFormatted,
                    storage
                )
            }
            return String(
                format: String(localized: "activity.movementLoggedIn", defaultValue: "Movement logged in %@"),
                storage
            )
        case "BulkCountImported":
            return String(
                format: String(localized: "activity.bulkCountImported", defaultValue: "Bulk count imported in %@"),
                storage
            )
        default:
            return eventType
        }
    }

    var displayIcon: String {
        switch eventType {
        case "ItemAdded": return "plus.circle.fill"
        case "ItemCounted": return "list.clipboard.fill"
        case "ItemUpdated": return "pencil.circle.fill"
        case "ItemDeleted": return "trash.fill"
        case "LowStockAlert": return "exclamationmark.triangle.fill"
        case "StorageCreated": return "archivebox.fill"
        case "SaleMade": return "cart.fill"
        case "MovementLogged": return "arrow.up.arrow.down.circle.fill"
        case "BulkCountImported": return "list.clipboard.fill"
        default: return "circle.fill"
        }
    }

    var displayColor: String {
        switch eventType {
        case "ItemAdded": return "green"
        case "ItemCounted": return "blue"
        case "ItemUpdated": return "blue"
        case "ItemDeleted": return "red"
        case "LowStockAlert": return "orange"
        case "StorageCreated": return "purple"
        case "SaleMade": return "green"
        case "MovementLogged": return "blue"
        case "BulkCountImported": return "blue"
        default: return "gray"
        }
    }
}
