import Foundation
import SwiftData

@Model
final class InventoryItem {
    var id: UUID
    var name: String
    var itemDescription: String
    var sku: String
    var barcode: String
    var currentQuantity: Double
    var minQuantity: Double
    var maxQuantity: Double
    var unitCost: Double
    /// When > 0, overrides minQuantity for low-stock detection (percentage of maxQuantity).
    var reorderPercentage: Double = 0
    /// Price paid on the most recent purchase — separate from unitCost for variance tracking.
    var lastPurchasePrice: Double = 0
    var lastPurchasedAt: Date? = nil
    var category: String = "Uncategorised"
    var expiryDate: Date? = nil
    var photoURL: String? = nil
    /// Set when the item was created via "Use Template" — used for template impact warnings.
    var createdFromTemplateId: UUID? = nil
    var createdAt: Date
    var updatedAt: Date

    @Relationship var storage: Storage?
    @Relationship var uom: UOM?
    @Relationship(deleteRule: .cascade) var countHistory: [InventoryCount] = []
    @Relationship(deleteRule: .cascade) var batches: [InventoryBatch] = []

    static let predefinedCategories: [String] = [
        "Uncategorised",
        "Food & Beverage",
        "Cleaning & Hygiene",
        "Packaging & Supplies",
        "Electronics & Equipment",
        "Clothing & Apparel",
        "Health & Beauty",
        "Pharmaceutical",
        "Raw Materials",
        "Spare Parts",
        "Stationery & Office",
        "Other"
    ]

    init(
        name: String,
        description: String = "",
        sku: String = "",
        barcode: String = "",
        currentQuantity: Double = 0,
        minQuantity: Double = 0,
        maxQuantity: Double = 0,
        unitCost: Double = 0,
        category: String = "Uncategorised",
        expiryDate: Date? = nil,
        storage: Storage? = nil,
        uom: UOM? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.itemDescription = description
        self.sku = sku.isEmpty ? "SKU-\(UUID().uuidString.prefix(6))" : sku
        self.barcode = barcode
        self.currentQuantity = currentQuantity
        self.minQuantity = minQuantity
        self.maxQuantity = maxQuantity
        self.unitCost = unitCost
        self.category = category
        self.expiryDate = expiryDate
        self.storage = storage
        self.uom = uom
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var isOutOfStock: Bool {
        currentQuantity <= 0
    }

    var effectiveMinQuantity: Double {
        if reorderPercentage > 0 && maxQuantity > 0 {
            return maxQuantity * reorderPercentage / 100
        }
        return minQuantity
    }

    var isLowStock: Bool {
        effectiveMinQuantity > 0 &&
        currentQuantity > 0 &&
        currentQuantity <= effectiveMinQuantity
    }

    var isOverStock: Bool {
        currentQuantity >= maxQuantity && maxQuantity > 0
    }

    var totalValue: Double {
        currentQuantity * unitCost
    }

    /// The most urgent expiry date for this item:
    /// the earliest batch expiry if batches exist, otherwise the item's own
    /// stored `expiryDate`. Items without batches behave exactly as before.
    var nearestExpiryDate: Date? {
        let batchMin = batches.compactMap { $0.expiryDate as Date? }.min()
        return batchMin ?? expiryDate
    }

    var isExpiringSoon: Bool {
        guard let expiry = nearestExpiryDate else { return false }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expiry).day ?? 0
        return days >= 0 && days <= 7
    }

    var isExpired: Bool {
        guard let expiry = nearestExpiryDate else { return false }
        return expiry < Date()
    }

    var daysUntilExpiry: Int? {
        guard let expiry = nearestExpiryDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiry).day
    }

    var stockStatus: String {
        if isOutOfStock {
            return "Out of Stock"
        } else if isLowStock {
            return "Low Stock"
        } else if isOverStock {
            return "Over Stock"
        } else {
            return "In Stock"
        }
    }
}
