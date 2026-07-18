import Foundation
import SwiftData

/// Movement types for inventory IN flows.
enum MovementTypeIn: String, CaseIterable, Codable {
    case purchase       = "Purchase"
    case transferIn     = "Transfer In"
    case returnFromCustomer = "Return from Customer"
    case adjustmentUp   = "Adjustment (Up)"
    case openingStock   = "Opening Stock"
}

/// Movement types for inventory OUT flows.
enum MovementTypeOut: String, CaseIterable, Codable {
    case saleOut        = "Sale"
    case waste          = "Waste / Spoilage"
    case returnToSupplier = "Return to Supplier"
    case transferOut    = "Transfer Out"
    case adjustmentDown = "Adjustment (Down)"
}

/// Records a single inventory movement (stock in or out) with full audit trail.
/// Denormalized itemName and storageName survive item deletion.
@Model
final class InventoryMovement {
    var id: UUID
    /// Soft reference — nil if item was deleted after this movement.
    @Relationship var item: InventoryItem?
    // Denormalized at time of movement
    var itemName: String
    var itemSKU: String
    var storageName: String
    var category: String
    /// "IN" or "OUT"
    var direction: String
    /// The movement type string (use MovementTypeIn.rawValue or MovementTypeOut.rawValue)
    var movementType: String
    var quantity: Double
    /// Optional: purchase price per unit, waste cost per unit, etc.
    var pricePerUnit: Double
    var notes: String
    var occurredAt: Date
    var createdAt: Date
    /// Optional link to a SaleEvent if this movement was created by a Quick Sale.
    var linkedSaleEventId: UUID?

    init(
        item: InventoryItem?,
        itemName: String,
        itemSKU: String,
        storageName: String,
        category: String,
        direction: String,
        movementType: String,
        quantity: Double,
        pricePerUnit: Double = 0,
        notes: String = "",
        occurredAt: Date = Date(),
        linkedSaleEventId: UUID? = nil
    ) {
        self.id = UUID()
        self.item = item
        self.itemName = itemName
        self.itemSKU = itemSKU
        self.storageName = storageName
        self.category = category
        self.direction = direction
        self.movementType = movementType
        self.quantity = quantity
        self.pricePerUnit = pricePerUnit
        self.notes = notes
        self.occurredAt = occurredAt
        self.createdAt = Date()
        self.linkedSaleEventId = linkedSaleEventId
    }

    var totalValue: Double { quantity * pricePerUnit }
    var isIN: Bool { direction == "IN" }
}
