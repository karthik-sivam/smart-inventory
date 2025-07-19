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
    var isOutOfStock: Bool
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship var storage: Storage?
    @Relationship var uom: UOM?
    @Relationship(deleteRule: .cascade) var countHistory: [InventoryCount] = []
    
    init(name: String, description: String = "", sku: String = "", barcode: String = "", 
         currentQuantity: Double = 0, minQuantity: Double = 0, maxQuantity: Double = 0, 
         unitCost: Double = 0, isOutOfStock: Bool = false, storage: Storage? = nil, uom: UOM? = nil) {
        self.id = UUID()
        self.name = name
        self.itemDescription = description
        self.sku = sku.isEmpty ? "SKU-\(UUID().uuidString.prefix(6))" : sku
        self.barcode = barcode
        self.currentQuantity = currentQuantity
        self.minQuantity = minQuantity
        self.maxQuantity = maxQuantity
        self.unitCost = unitCost
        self.isOutOfStock = isOutOfStock
        self.storage = storage
        self.uom = uom
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var isLowStock: Bool {
        currentQuantity <= minQuantity
    }
    
    var isOverStock: Bool {
        currentQuantity >= maxQuantity && maxQuantity > 0
    }
    
    var totalValue: Double {
        currentQuantity * unitCost
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