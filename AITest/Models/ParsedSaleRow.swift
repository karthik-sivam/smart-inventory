import Foundation
import os.log
import SwiftData

/// Transient review-time model for Smart Sales Entry — not persisted in SwiftData.
struct ParsedSaleRow: Identifiable {
    let id = UUID()
    var itemName: String
    var quantitySold: Double
    var pricePerUnit: Double
    var confidence: Double
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
    let confidence: Double

    private enum CodingKeys: String, CodingKey {
        case itemName
        case quantitySold
        case pricePerUnit
        case notes
        case confidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemName = try container.decode(String.self, forKey: .itemName)
        quantitySold = try container.decode(Double.self, forKey: .quantitySold)
        pricePerUnit = try container.decode(Double.self, forKey: .pricePerUnit)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)

        if container.contains(.confidence) {
            confidence = try container.decode(Double.self, forKey: .confidence)
        } else {
            os_log(
                "ParsedSaleRowDTO response missing confidence; using 0.5 legacy fallback",
                log: .default,
                type: .default
            )
            confidence = 0.5
        }
    }

    func toParsedSaleRow() -> ParsedSaleRow {
        ParsedSaleRow(
            itemName: itemName,
            quantitySold: quantitySold,
            pricePerUnit: pricePerUnit,
            confidence: confidence,
            notes: notes ?? ""
        )
    }
}
