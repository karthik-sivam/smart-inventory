import Foundation
import SwiftData

@Model
final class Storage {
    var id: UUID
    var name: String
    var location: String
    var storageDescription: String
    var color: String
    var createdAt: Date
    var updatedAt: Date
    
    @Relationship(deleteRule: .cascade) var items: [InventoryItem] = []
    
    init(name: String, location: String = "", description: String = "", color: String = "#007AFF") {
        self.id = UUID()
        self.name = name
        self.location = location
        self.storageDescription = description
        self.color = color
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var itemCount: Int {
        items.count
    }
    
    var totalQuantity: Double {
        items.reduce(0) { $0 + $1.currentQuantity }
    }
} 