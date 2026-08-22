import Foundation
import SwiftData

enum ReverseEntryResult {
    case success
    case outsideEditWindow
    case linkedToSale
}

enum SaleHelpers {
    /// Non-blocking negative-stock summary lines after a sale batch.
    static func negativeStockMessages(for items: [InventoryItem]) -> [String] {
        items.filter { $0.currentQuantity < 0 }.map { item in
            String(
                format: L("sale.negativeStock.warning", "%1$@ is now at negative stock (%2$@). You may have missed a stock count or a purchase entry."),
                item.name,
                item.currentQuantity.smartFormatted
            )
        }
    }

    static func applyFallbackPriceIfNeeded(_ row: inout ParsedSaleRow, from item: InventoryItem) {
        guard !row.priceWasEdited else { return }
        row.pricePerUnit = item.fallbackSalePrice
    }

    // MARK: - Reverse / delete (S27)

    @MainActor
    static func reverseSale(_ sale: SaleEvent, modelContext: ModelContext) -> ReverseEntryResult {
        guard EditPolicy.isWithinEditWindow(createdAt: sale.createdAt) else {
            return .outsideEditWindow
        }

        let saleId = sale.id
        let linkedMovements = (try? modelContext.fetch(FetchDescriptor<InventoryMovement>(
            predicate: #Predicate { $0.linkedSaleEventId == saleId }
        ))) ?? []

        if let item = sale.item {
            let qtyBefore = item.currentQuantity
            let qtyAfter = qtyBefore + sale.quantitySold
            let event = ActivityEvent(
                eventType: "SaleReversed",
                itemName: item.name,
                storageName: sale.storageName,
                quantityBefore: qtyBefore,
                quantityAfter: qtyAfter,
                notes: String(
                    format: L("sale.reverse.notes", "Reversed sale of %@"),
                    sale.quantitySold.smartFormatted
                )
            )
            modelContext.insert(event)
            modelContext.safeSave(context: "reverse sale activity")
            FirestoreManager.shared.syncActivity(event)

            item.currentQuantity = qtyAfter
            item.updatedAt = Date()
            FirestoreManager.shared.syncItem(item)
        } else {
            let event = ActivityEvent(
                eventType: "SaleReversed",
                itemName: sale.itemName,
                storageName: sale.storageName,
                notes: L("sale.reverse.itemMissing", "Reversed sale (item no longer exists)")
            )
            modelContext.insert(event)
            modelContext.safeSave(context: "reverse sale activity")
            FirestoreManager.shared.syncActivity(event)
        }

        for movement in linkedMovements {
            FirestoreManager.shared.deleteInventoryMovement(id: movement.id)
            modelContext.delete(movement)
        }

        FirestoreManager.shared.deleteSaleEvent(id: sale.id)
        modelContext.delete(sale)
        modelContext.safeSave(context: "ReverseSale")

        AnalyticsManager.shared.track(.saleReversed(
            itemId: sale.item?.id.uuidString ?? "",
            quantity: sale.quantitySold
        ))

        return .success
    }

    @MainActor
    static func reverseMovement(_ movement: InventoryMovement, modelContext: ModelContext) -> ReverseEntryResult {
        guard EditPolicy.isWithinEditWindow(createdAt: movement.createdAt) else {
            return .outsideEditWindow
        }
        if movement.linkedSaleEventId != nil {
            return .linkedToSale
        }

        if let item = movement.item {
            let qtyBefore = item.currentQuantity
            let qtyAfter = movement.isIN
                ? qtyBefore - movement.quantity
                : qtyBefore + movement.quantity
            let event = ActivityEvent(
                eventType: "MovementReversed",
                itemName: item.name,
                storageName: movement.storageName,
                quantityBefore: qtyBefore,
                quantityAfter: qtyAfter,
                notes: movement.localizedMovementTypeLabel
            )
            modelContext.insert(event)
            modelContext.safeSave(context: "reverse movement activity")
            FirestoreManager.shared.syncActivity(event)

            item.currentQuantity = qtyAfter
            item.updatedAt = Date()
            FirestoreManager.shared.syncItem(item)
        } else {
            let event = ActivityEvent(
                eventType: "MovementReversed",
                itemName: movement.itemName,
                storageName: movement.storageName,
                notes: L("movement.reverse.itemMissing", "Reversed movement (item no longer exists)")
            )
            modelContext.insert(event)
            modelContext.safeSave(context: "reverse movement activity")
            FirestoreManager.shared.syncActivity(event)
        }

        FirestoreManager.shared.deleteInventoryMovement(id: movement.id)
        modelContext.delete(movement)
        modelContext.safeSave(context: "ReverseMovement")

        AnalyticsManager.shared.track(.movementReversed(
            itemId: movement.item?.id.uuidString ?? "",
            movementType: movement.movementType
        ))

        return .success
    }
}
