import Foundation
import SwiftData

/// Transient review-time model for Purchase Invoice Import — not persisted in SwiftData.
struct ParsedPurchaseRow: Identifiable {
    let id = UUID()
    var itemName: String
    var quantityReceived: Double
    var costPerUnit: Double
    var notes: String = ""
    var resolvedItem: InventoryItem? = nil
    var isSkipped: Bool = false
}

struct ParsedPurchaseRowDTO: Decodable {
    let itemName: String
    let quantityReceived: Double
    let costPerUnit: Double
    let notes: String?

    func toParsedPurchaseRow() -> ParsedPurchaseRow {
        ParsedPurchaseRow(
            itemName: itemName,
            quantityReceived: quantityReceived,
            costPerUnit: costPerUnit,
            notes: notes ?? ""
        )
    }
}
