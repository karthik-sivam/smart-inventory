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
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after = quantityAfter.map { $0.smartFormatted } ?? "?"
            return "Count updated: \(before) → \(after)"
        case "ItemUpdated":
            let before = quantityBefore.map { $0.smartFormatted } ?? "?"
            let after = quantityAfter.map { $0.smartFormatted } ?? "?"
            return before == after
                ? "Item details updated"
                : "Quantity: \(before) -> \(after)"
        case "ItemDeleted":
            return "Removed from \(storageName)"
        case "LowStockAlert":
            return "Low stock alert triggered"
        case "StorageCreated":
            return "Storage area created"
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
        default: return "gray"
        }
    }
}
