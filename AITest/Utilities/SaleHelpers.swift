import Foundation

enum SaleHelpers {
    /// Non-blocking negative-stock summary lines after a sale batch.
    static func negativeStockMessages(for items: [InventoryItem]) -> [String] {
        items.filter { $0.currentQuantity < 0 }.map { item in
            String(
                format: String(
                    localized: "sale.negativeStock.warning",
                    defaultValue: "%1$@ is now at negative stock (%2$@). You may have missed a stock count or a purchase entry."
                ),
                item.name,
                item.currentQuantity.smartFormatted
            )
        }
    }

    static func applyFallbackPriceIfNeeded(_ row: inout ParsedSaleRow, from item: InventoryItem) {
        guard !row.priceWasEdited else { return }
        row.pricePerUnit = item.fallbackSalePrice
    }
}
