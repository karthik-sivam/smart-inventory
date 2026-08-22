import Foundation
import SwiftData

/// Transient review-time model for Smart Sales Entry — not persisted in SwiftData.
struct ParsedSaleRow: Identifiable {
    let id = UUID()
    var itemName: String
    var quantitySold: Double
    var pricePerUnit: Double
    var notes: String = ""
    var resolvedItem: InventoryItem? = nil
    var isSkipped: Bool = false
    /// True once the user edits the price field — preserves explicit 0 input.
    var priceWasEdited: Bool = false
}

struct ParsedSaleRowDTO: Decodable {
    let itemName: String
    let quantitySold: Double
    let pricePerUnit: Double
    let notes: String?

    func toParsedSaleRow() -> ParsedSaleRow {
        ParsedSaleRow(
            itemName: itemName,
            quantitySold: quantitySold,
            pricePerUnit: pricePerUnit,
            notes: notes ?? ""
        )
    }
}
