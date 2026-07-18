import Foundation
import SwiftData

/// Records a single sale transaction. Denormalized fields (itemName, itemSKU,
/// storageName, category) are captured at time of sale so that deleting an item
/// never erases historical revenue data.
@Model
final class SaleEvent {
    var id: UUID
    /// Soft reference — nil if the item was deleted after this sale.
    @Relationship var item: InventoryItem?
    // Denormalized at time of sale (never changes even if item is edited/deleted)
    var itemName: String
    var itemSKU: String
    var storageName: String
    var category: String
    var quantitySold: Double
    /// Price per unit at the time of the sale (may differ from item.sellingPrice if overridden).
    var pricePerUnit: Double
    /// Cost per unit at time of sale (snapshot of item.unitCost).
    var costPerUnit: Double
    var notes: String
    var occurredAt: Date
    var createdAt: Date

    init(
        item: InventoryItem?,
        itemName: String,
        itemSKU: String,
        storageName: String,
        category: String,
        quantitySold: Double,
        pricePerUnit: Double,
        costPerUnit: Double,
        notes: String = "",
        occurredAt: Date = Date()
    ) {
        self.id = UUID()
        self.item = item
        self.itemName = itemName
        self.itemSKU = itemSKU
        self.storageName = storageName
        self.category = category
        self.quantitySold = quantitySold
        self.pricePerUnit = pricePerUnit
        self.costPerUnit = costPerUnit
        self.notes = notes
        self.occurredAt = occurredAt
        self.createdAt = Date()
    }

    var revenue: Double { quantitySold * pricePerUnit }
    var cogs: Double { quantitySold * costPerUnit }
    var grossProfit: Double { revenue - cogs }
    var grossMarginPct: Double? {
        guard revenue > 0 else { return nil }
        return grossProfit / revenue * 100
    }
}
