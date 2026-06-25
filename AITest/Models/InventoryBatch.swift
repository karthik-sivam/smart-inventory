import Foundation
import SwiftData

/// `InventoryBatch` represents a single received lot of stock for an item.
///
/// e.g.  "30 kg of carrots received May 10, expires May 18"
///       "45 kg of carrots received May 13, expires Jun 12"
///
/// Batches are created when the user receives new stock (counts up) and chooses
/// to track it as a separate batch. SwiftData handles the additive migration
/// automatically on iOS 17+ — no migration code is needed for a new @Model.
@Model
final class InventoryBatch {
    var id: UUID
    var quantity: Double
    var expiryDate: Date
    var receivedDate: Date
    var notes: String

    @Relationship var item: InventoryItem?

    init(quantity: Double,
         expiryDate: Date,
         notes: String = "",
         item: InventoryItem? = nil) {
        self.id           = UUID()
        self.quantity     = quantity
        self.expiryDate   = expiryDate
        self.receivedDate = Date()
        self.notes        = notes
        self.item         = item
    }
}
