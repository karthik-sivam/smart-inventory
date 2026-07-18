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
        switch eventType {
        case "ItemAdded":
            return "Added to \(storageName)"
        case "ItemCounted":
            // Only show "?" if BOTH values are missing. If one is nil, fall back gracefully.
            if quantityBefore == nil && quantityAfter == nil {
                return "Count recorded in \(storageName)"
            }
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after  = quantityAfter.map  { $0.smartFormatted } ?? "?"
            return "Count updated: \(before) → \(after)"
        case "ItemUpdated":
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after  = quantityAfter.map  { $0.smartFormatted } ?? "?"
            return before == after
                ? "Item details updated"
                : "Quantity: \(before) -> \(after)"
        case "ItemDeleted":
            return "Removed from \(storageName)"
        case "LowStockAlert":
            return "Low stock alert triggered"
        case "StorageCreated":
            return "Storage area created"
        case "SaleMade":
            // quantityBefore = stock before sale, quantityAfter = stock after sale
            // soldQty = before - after
            if let before = quantityBefore, let after = quantityAfter {
                let soldQty = (before - after).smartFormatted
                return "Sale recorded: \(soldQty) sold from \(storageName)"
            }
            return "Sale recorded from \(storageName)"
        case "MovementLogged":
            // quantityBefore = stock before, quantityAfter = stock after
            if let before = quantityBefore, let after = quantityAfter {
                let change = after - before
                let sign = change >= 0 ? "+" : ""
                return "Movement: \(sign)\(change.smartFormatted) in \(storageName)"
            }
            return "Movement logged in \(storageName)"
        case "BulkCountImported":
            return "Bulk count imported in \(storageName)"
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
