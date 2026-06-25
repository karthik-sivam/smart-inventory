import Foundation
import SwiftData

@Model
final class ItemTemplate {
    var id: UUID
    var name: String
    var templateDescription: String
    var category: String
    var uomSymbol: String
    var uomName: String
    var defaultMinQty: Double
    var defaultMaxQty: Double
    var createdAt: Date

    init(name: String, description: String = "", category: String = "Uncategorised",
         uomSymbol: String = "pcs", uomName: String = "Pieces",
         defaultMinQty: Double = 0, defaultMaxQty: Double = 0) {
        self.id = UUID()
        self.name = name
        self.templateDescription = description
        self.category = category
        self.uomSymbol = uomSymbol
        self.uomName = uomName
        self.defaultMinQty = defaultMinQty
        self.defaultMaxQty = defaultMaxQty
        self.createdAt = Date()
    }
}
