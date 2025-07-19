import Foundation
import SwiftData

@Model
final class InventoryCount {
    var id: UUID
    var previousQuantity: Double
    var countedQuantity: Double
    var adjustmentReason: String
    var notes: String
    var countDate: Date
    var countedBy: String
    
    @Relationship var item: InventoryItem?
    
    init(previousQuantity: Double, countedQuantity: Double, adjustmentReason: String = "", 
         notes: String = "", countedBy: String = "User", item: InventoryItem? = nil) {
        self.id = UUID()
        self.previousQuantity = previousQuantity
        self.countedQuantity = countedQuantity
        self.adjustmentReason = adjustmentReason
        self.notes = notes
        self.countDate = Date()
        self.countedBy = countedBy
        self.item = item
    }
    
    var variance: Double {
        countedQuantity - previousQuantity
    }
    
    var variancePercentage: Double {
        guard previousQuantity > 0 else { return 0 }
        return (variance / previousQuantity) * 100
    }
    
    var adjustmentType: String {
        if variance > 0 {
            return "Increase"
        } else if variance < 0 {
            return "Decrease"
        } else {
            return "No Change"
        }
    }
} 