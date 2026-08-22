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
            ? L("activity.noStorage", "No Storage")
            : storageName
        switch eventType {
        case "ItemAdded":
            return String(
                format: L("activity.addedTo", "Added to %@"),
                storage
            )
        case "ItemCounted":
            if quantityBefore == nil && quantityAfter == nil {
                return String(
                    format: L("activity.countRecordedIn", "Count recorded in %@"),
                    storage
                )
            }
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after = quantityAfter.map { $0.smartFormatted } ?? "?"
            return String(
                format: L("activity.countUpdated", "Count updated: %1$@ → %2$@"),
                before,
                after
            )
        case "ItemUpdated":
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after = quantityAfter.map { $0.smartFormatted } ?? "?"
            if before == after {
                return L("activity.itemDetailsUpdated", "Item details updated")
            }
            return String(
                format: L("activity.quantityChanged", "Quantity: %1$@ -> %2$@"),
                before,
                after
            )
        case "ItemDeleted":
            return String(
                format: L("activity.removedFrom", "Removed from %@"),
                storage
            )
        case "LowStockAlert":
            return L("activity.lowStockAlert", "Low stock alert triggered")
        case "StorageCreated":
            return L("activity.storageCreated", "Storage area created")
        case "SaleMade":
            if let before = quantityBefore, let after = quantityAfter {
                let soldQty = (before - after).smartFormatted
                return String(
                    format: L("activity.saleRecordedQty", "Sale recorded: %1$@ sold from %2$@"),
                    soldQty,
                    storage
                )
            }
            return String(
                format: L("activity.saleRecordedFrom", "Sale recorded from %@"),
                storage
            )
        case "MovementLogged":
            if let before = quantityBefore, let after = quantityAfter {
                let change = after - before
                let sign = change >= 0 ? "+" : ""
                return String(
                    format: L("activity.movementChange", "Movement: %1$@%2$@ in %3$@"),
                    sign,
                    change.smartFormatted,
                    storage
                )
            }
            return String(
                format: L("activity.movementLoggedIn", "Movement logged in %@"),
                storage
            )
        case "BulkCountImported":
            return String(
                format: L("activity.bulkCountImported", "Bulk count imported in %@"),
                storage
            )
        case "SaleReversed":
            if let before = quantityBefore, let after = quantityAfter {
                return String(
                    format: L("activity.saleReversed", "Sale reversed: %1$@ → %2$@ in %3$@"),
                    before.smartFormatted,
                    after.smartFormatted,
                    storage
                )
            }
            return String(
                format: L("activity.saleReversedSimple", "Sale reversed in %@"),
                storage
            )
        case "MovementReversed":
            if let before = quantityBefore, let after = quantityAfter {
                return String(
                    format: L("activity.movementReversed", "Movement reversed: %1$@ → %2$@ in %3$@"),
                    before.smartFormatted,
                    after.smartFormatted,
                    storage
                )
            }
            return String(
                format: L("activity.movementReversedSimple", "Movement reversed in %@"),
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
        case "SaleReversed": return "arrow.uturn.backward.circle.fill"
        case "MovementReversed": return "arrow.uturn.backward.circle.fill"
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
        case "SaleReversed": return "orange"
        case "MovementReversed": return "orange"
        default: return "gray"
        }
    }
}
