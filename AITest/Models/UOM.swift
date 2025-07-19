import Foundation
import SwiftData

@Model
final class UOM {
    var id: UUID
    var name: String
    var symbol: String
    var category: String
    var isDefault: Bool
    var createdAt: Date
    
    init(name: String, symbol: String, category: String, isDefault: Bool = false) {
        self.id = UUID()
        self.name = name
        self.symbol = symbol
        self.category = category
        self.isDefault = isDefault
        self.createdAt = Date()
    }
    
    static let standardUOMs = [
        UOM(name: "Pieces", symbol: "pcs", category: "Count", isDefault: true),
        UOM(name: "Kilograms", symbol: "kg", category: "Weight"),
        UOM(name: "Grams", symbol: "g", category: "Weight"),
        UOM(name: "Liters", symbol: "L", category: "Volume"),
        UOM(name: "Milliliters", symbol: "mL", category: "Volume"),
        UOM(name: "Meters", symbol: "m", category: "Length"),
        UOM(name: "Centimeters", symbol: "cm", category: "Length"),
        UOM(name: "Boxes", symbol: "box", category: "Count"),
        UOM(name: "Packs", symbol: "pack", category: "Count"),
        UOM(name: "Dozens", symbol: "doz", category: "Count")
    ]
} 